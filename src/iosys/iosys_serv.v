// IOSys - SERV-based IO subsystem for snestang
//
// IOSys provides the following functionality,
// - Menu system
// - ROM file loading
// - Configuration options
// - (Future) USB controller handling
// - (Future) Savestate handling
//
// This is similar to the IO controller of MIST, or HPS of MiSTer.
//
// The softcore runs RV32I at 21.6Mhz and uses SDRAM as main memory. Firmware is
// loaded from SPI flash on the board. Firmware source is in /snestang/firmware.
//
// Author: nand2mario, 1/2024
//         m1nl, 9/2026

`define MCU_SERV

module iosys_serv #(
    parameter        FREQ = 21_477_000,
    parameter [14:0] COLOR_LOGO = 15'b00000_10101_00000,
    parameter [15:0] CORE_ID = 1,   // 1: nestang, 2: snestang
    parameter        UART = 0
) (
    input clk,                      // SNES mclk
    input hclk,                     // HDMI clock
    input resetn,

    // OSD display interface
    output overlay,
    input [7:0] overlay_x,          // 0-255
    input [7:0] overlay_y,          // 0-223
    output [14:0] overlay_color,    // BGR5
    input [11:0] joy1,              // joystick 1: (R L X A RT LT DN UP START SELECT Y B)
    input [11:0] joy2,              // joystick 2

    // ROM loading interface
    output reg rom_loading,         // 0-to-1 loading starts, 1-to-0 loading is finished
    output [7:0] rom_do,            // first 64 bytes are snes header + 32 bytes after snes header
    output reg rom_do_valid,        // strobe for rom_do
    input  wire rom_do_ready,       // ready for rom_do

    // 32-bit wide memory interface for risc-v softcore
    // 0x_xxxx~6x_xxxx is RV RAM, 7x_xxxx is BSRAM
    output rv_valid,                // 1: active memory access
    input  rv_ready,                // pulse when access is done
    output [22:0] rv_addr,          // 8MB memory space
    output [31:0] rv_wdata,         // 32-bit write data
    output  [3:0] rv_wstrb,         // 4 byte write strobe
    input  [31:0] rv_rdata,         // 32-bit read data

    // SPI flash
    output flash_spi_cs_n,          // chip select
    input  flash_spi_miso,          // master in slave out
    output flash_spi_mosi,          // mster out slave in
    output flash_spi_clk,           // spi clock
    output flash_spi_wp_n,          // write protect
    output flash_spi_hold_n,        // hold operations

    // UART
    input uart_rx,
    output uart_tx,

    // SD card
    output sd_clk,
    inout  sd_cmd,                  // MOSI
    input  sd_dat0,                 // MISO
    output sd_dat1,                 // 1
    output sd_dat2,                 // 1
    output sd_dat3                  // 0 for SPI mode
);

/* verilator lint_off PINMISSING */
/* verilator lint_off WIDTHTRUNC */

localparam FIRMWARE_SIZE = 256 * 1024;

reg flash_loaded;
reg flash_loading;

reg [20:0] flash_addr = {21{1'b1}};

reg flash_start;
wire [7:0] flash_dout;
wire flash_out_strb;

assign flash_spi_hold_n = 1;
assign flash_spi_wp_n = 1;      // disable write protection

reg [7:0] flash_d;
reg [3:0] flash_wstrb;
reg flash_wr;

wire [31:0] spiflash_reg_do;
wire spiflash_reg_wait;

wire [20:0] flash_next_addr = flash_addr + 1;

always @(posedge clk, negedge resetn) begin
    if (~resetn) begin
        flash_loaded <= 0;
        flash_loading <= 0;
        flash_start <= 0;
        flash_wr <= 0;
        flash_d <= 0;
        flash_wstrb <= 0;
        flash_addr <= {21{1'b1}};

    end else begin
        flash_start <= 0;
        flash_wr <= 0;

        if (~flash_loaded && ~flash_loading) begin
            // start loading
            flash_start <= 1;
            flash_loading <= 1;
        end

        if (flash_loading) begin
            if (flash_out_strb) begin
                flash_addr <= flash_next_addr;
                flash_d <= flash_dout;
                flash_wr <= 1;

                case (flash_next_addr[1:0])
                2'b00: flash_wstrb <= 4'b0001;
                2'b01: flash_wstrb <= 4'b0010;
                2'b10: flash_wstrb <= 4'b0100;
                2'b11: flash_wstrb <= 4'b1000;
                endcase

                if (flash_next_addr == FIRMWARE_SIZE-1) begin
                    flash_loading <= 0;
                    flash_loaded <= 1;
                end
            end
        end
    end
end

// SERV softcore
wire mem_valid;
wire mem_ready;

wire [31:0] mem_addr, mem_wdata;
wire  [3:0] mem_wstrb;
wire [31:0] mem_rdata;

wire ram_ready;
wire [31:0] ram_rdata;

assign mem_ready = ram_ready;
assign mem_rdata = ram_rdata;

wire ext_valid;
wire ext_ready;

wire  [7:0] ext_addr;
wire [31:0] ext_wdata;
wire  [3:0] ext_wstrb;
wire [31:0] ext_rdata;

wire        textdisp_reg_char_sel= ext_valid && (ext_addr == 8'h00);

wire        simpleuart_reg_div_sel = ext_valid && (ext_addr == 8'h10);
wire [31:0] simpleuart_reg_div_do;

wire        simpleuart_reg_dat_sel = ext_valid && (ext_addr == 8'h14);
wire [31:0] simpleuart_reg_dat_do;
wire        simpleuart_reg_dat_wait;

wire        simplespimaster_reg_byte_sel = ext_valid && (ext_addr == 8'h20);
wire        simplespimaster_reg_word_sel = ext_valid && (ext_addr == 8'h24);
wire [31:0] simplespimaster_reg_do;
wire        simplespimaster_reg_wait;

wire        romload_reg_ctrl_sel = ext_valid && (ext_addr == 8'h30);       // write 1 to start loading, 0 to finish loading
wire        romload_stream_sel;
wire        romload_reg_data_sel = ext_valid && (ext_addr == 8'h34);       // write once to load 4 bytes
reg         romload_reg_data_ready;

wire        joystick_reg_sel = ext_valid && (ext_addr == 8'h40);

wire        time_reg_sel = ext_valid && (ext_addr == 8'h50);        // milli-seconds since start-up (overflows in 49 days)
wire        cycle_reg_sel = ext_valid && (ext_addr == 8'h54);       // cycles counter (overflows every 200 seconds)

wire        id_reg_sel = ext_valid && (ext_addr == 8'h60);

wire        spiflash_reg_byte_sel = ext_valid && (ext_addr == 8'h70);
wire        spiflash_reg_word_sel = ext_valid && (ext_addr == 8'h74);
wire        spiflash_reg_ctrl_sel = ext_valid && (ext_addr == 8'h78);

assign ext_ready = textdisp_reg_char_sel || simpleuart_reg_div_sel ||
            romload_reg_ctrl_sel || romload_reg_data_ready || joystick_reg_sel || time_reg_sel || cycle_reg_sel || id_reg_sel ||
            (simpleuart_reg_dat_sel && !simpleuart_reg_dat_wait) ||
            ((simplespimaster_reg_byte_sel || simplespimaster_reg_word_sel) && !simplespimaster_reg_wait) ||
            (spiflash_reg_byte_sel || spiflash_reg_word_sel) && !spiflash_reg_wait ||
            spiflash_reg_ctrl_sel;

assign ext_rdata = joystick_reg_sel ? {4'b0, joy2, 4'b0, joy1} :
        simpleuart_reg_div_sel ? simpleuart_reg_div_do :
        simpleuart_reg_dat_sel ? simpleuart_reg_dat_do :
        time_reg_sel ? time_reg :
        cycle_reg_sel ? cycle_reg :
        id_reg_sel ? {16'b0, CORE_ID} :
        (simplespimaster_reg_byte_sel | simplespimaster_reg_word_sel) ? simplespimaster_reg_do :
        (spiflash_reg_byte_sel | spiflash_reg_word_sel) ? spiflash_reg_do :
        32'h0;

localparam with_csr = 0;
localparam width    = 4;  // QERV

localparam csr_regs = with_csr * 4;
localparam rf_width = width * 2;
localparam rf_l2d   = $clog2((32+csr_regs)*32/rf_width);

wire [31:0] wb_mem_adr;
wire [31:0] wb_mem_dat;
wire  [3:0] wb_mem_sel;
wire        wb_mem_we;
wire        wb_mem_stb;
wire [31:0] wb_mem_rdt;
wire        wb_mem_ack;

wire [31:0] wb_ext_adr;
wire [31:0] wb_ext_dat;
wire  [3:0] wb_ext_sel;
wire        wb_ext_we;
wire        wb_ext_stb;
wire [31:0] wb_ext_rdt;
wire        wb_ext_ack;

wire [rf_l2d-1:0]   rf_waddr;
wire [rf_width-1:0] rf_wdata;
wire                rf_wen;
wire [rf_l2d-1:0]   rf_raddr;
wire                rf_ren;
wire [rf_width-1:0] rf_rdata;

serv_rf_ram #(
        .width(rf_width),
        .csr_regs(csr_regs)
) rf_ram (
        .i_clk    (clk),
        .i_waddr  (rf_waddr),
        .i_wdata  (rf_wdata),
        .i_wen    (rf_wen),
        .i_raddr  (rf_raddr),
        .i_ren    (rf_ren),
        .o_rdata  (rf_rdata)
);

servile #(
        .width    (width),
        .sim      (1'b0),
        .debug    (1'b0),
        .with_c   (1'b0),
        .with_csr (with_csr[0]),
        .with_mdu (1'b0)
) cpu (
        .i_clk       (clk),
        .i_rst       (~(resetn && flash_loaded)),
        .i_timer_irq (1'b0),

        .o_wb_mem_adr (wb_mem_adr),
        .o_wb_mem_dat (wb_mem_dat),
        .o_wb_mem_sel (wb_mem_sel),
        .o_wb_mem_we  (wb_mem_we),
        .o_wb_mem_stb (wb_mem_stb),
        .i_wb_mem_rdt (wb_mem_rdt),
        .i_wb_mem_ack (wb_mem_ack),

        .o_wb_ext_adr (wb_ext_adr),
        .o_wb_ext_dat (wb_ext_dat),
        .o_wb_ext_sel (wb_ext_sel),
        .o_wb_ext_we  (wb_ext_we),
        .o_wb_ext_stb (wb_ext_stb),
        .i_wb_ext_rdt (wb_ext_rdt),
        .i_wb_ext_ack (wb_ext_ack),

        .o_rf_waddr (rf_waddr),
        .o_rf_wdata (rf_wdata),
        .o_rf_wen   (rf_wen),
        .o_rf_raddr (rf_raddr),
        .o_rf_ren   (rf_ren),
        .i_rf_rdata (rf_rdata)
);

assign mem_valid = wb_mem_stb;
assign mem_addr  = wb_mem_adr;
assign mem_wdata = wb_mem_dat;
assign mem_wstrb = wb_mem_we ? wb_mem_sel : 4'b0000;

assign wb_mem_rdt = mem_rdata;
assign wb_mem_ack = mem_ready;

assign ext_valid = wb_ext_stb && ~wb_ext_adr[31];
assign ext_addr  = wb_ext_adr[7:0];
assign ext_wdata = wb_ext_dat;
assign ext_wstrb = wb_ext_we ? wb_ext_sel : 4'b0000;

assign romload_stream_sel = wb_ext_stb && wb_ext_adr[31];

assign wb_ext_rdt = ext_rdata;
assign wb_ext_ack = ext_ready;

// text display @ 0x0200_0000
textdisp #(.COLOR_LOGO(COLOR_LOGO)) disp (
    .clk(clk), .hclk(hclk), .resetn(resetn),
    .x(overlay_x), .y(overlay_y), .color(overlay_color),
    .reg_char_we(textdisp_reg_char_sel ? ext_wstrb : 4'b0),
    .reg_char_di(ext_wdata)
);

// toggle overlay display on/off
reg overlay_buf = 1;

assign overlay = overlay_buf;

always @(posedge clk, negedge resetn) begin
    if (~resetn) begin
        overlay_buf <= 1;
    end else begin
        if (textdisp_reg_char_sel && ext_wstrb[0]) begin
            case (ext_wdata[25:24])
            2'd1: overlay_buf <= 1;
            2'd2: overlay_buf <= 0;
            default: ;
            endcase
        end
    end
end

// uart @ 0x0200_0010
generate
    if (UART) begin
        simpleuart simpleuart (
            .clk         (clk),
            .resetn      (resetn),

            .ser_tx      (uart_tx),
            .ser_rx      (uart_rx),

            .reg_div_we  (simpleuart_reg_div_sel ? ext_wstrb : 4'b0),
            .reg_div_di  (ext_wdata),
            .reg_div_do  (simpleuart_reg_div_do),

            .reg_dat_we  (simpleuart_reg_dat_sel ? ext_wstrb[0] : 1'b0),
            .reg_dat_re  (simpleuart_reg_dat_sel && !ext_wstrb),
            .reg_dat_di  (ext_wdata),
            .reg_dat_do  (simpleuart_reg_dat_do),
            .reg_dat_wait(simpleuart_reg_dat_wait)
        );

    end else begin
        assign simpleuart_reg_dat_wait = 1'b0;
        assign simpleuart_reg_div_do   = 32'hxxxx;
        assign simpleuart_reg_dat_do   = 32'hxxxx;

        assign uart_tx = 1'b1;
    end
endgenerate

// spi sd card @ 0x0200_0020
assign sd_dat1 = 1;
assign sd_dat2 = 1;
assign sd_dat3 = 0;

simplespimaster simplespi (
    .clk(clk), .resetn(resetn),
    .sck(sd_clk), .mosi(sd_cmd), .miso(sd_dat0),
    .reg_byte_we(simplespimaster_reg_byte_sel ? ext_wstrb[0] : 1'b0),
    .reg_word_we(simplespimaster_reg_word_sel ? ext_wstrb[0] : 1'b0),
    .reg_di(ext_wdata),
    .reg_do(simplespimaster_reg_do),
    .reg_wait(simplespimaster_reg_wait)
);

// ROM loading I/O @ 0x02000_0030
wire romload_req = romload_stream_sel || romload_reg_data_sel;

reg  romload_seen;

reg [31:0] rom_do_buf;
reg  [2:0] rom_cnt;

assign rom_do = rom_do_buf[7:0];

// ROM loader data register
always @(posedge clk, negedge resetn) begin
    if (~resetn) begin
        romload_seen <= 1'b0;
        romload_reg_data_ready <= 1'b0;

        rom_cnt <= 3'd0;
        rom_do_valid <= 1'b0;
        rom_do_buf <= 0;

    end else begin
        if (!romload_req)
            romload_seen <= 1'b0;

        romload_reg_data_ready <= 1'b0;

        if (rom_do_ready || !rom_do_valid) begin
            rom_do_valid <= 1'b0;

            if (rom_cnt != 3'd0) begin
                rom_do_buf <= {8'd0, rom_do_buf[31:8]};
                rom_cnt <= rom_cnt - 3'd1;
                rom_do_valid <= 1;

            end else if (romload_req && !romload_seen) begin
                rom_do_buf <= ext_wstrb[0] ? ext_wdata                 :
                              ext_wstrb[1] ? {8'b0,  ext_wdata[31: 8]} :
                              ext_wstrb[2] ? {16'b0, ext_wdata[31:16]} :
                              ext_wstrb[3] ? {24'b0, ext_wdata[31:24]} : ext_wdata;

                rom_cnt <= {2'b0, ext_wstrb[0]} + {2'b0, ext_wstrb[1]} +
                           {2'b0, ext_wstrb[2]} + {2'b0, ext_wstrb[3]} - 3'd1;

                rom_do_valid <= |ext_wstrb;

                romload_seen <= 1'b1;
                romload_reg_data_ready <= 1;
            end
        end
    end
end

// ROM loader control register
always @(posedge clk, negedge resetn) begin
    if (~resetn) begin
        rom_loading <= 1'b0;
    end else begin
        if (romload_reg_ctrl_sel && ext_wstrb[0])
            rom_loading <= ext_wdata[0];
    end
end

// SPI flash @ 0x02000_0070
// Load 256KB of ROM from flash address 0x500000 into SDRAM at address 0x0
spiflash #(.ADDR(24'h500000), .LEN(FIRMWARE_SIZE)) flash (
    .clk(clk), .resetn(resetn),
    .ncs(flash_spi_cs_n), .miso(flash_spi_miso), .mosi(flash_spi_mosi),
    .sck(flash_spi_clk),

    .start(flash_start), .dout(flash_dout), .dout_strb(flash_out_strb), .busy(),

    .reg_byte_we(spiflash_reg_byte_sel ? ext_wstrb[0] : 1'b0),
    .reg_word_we(spiflash_reg_word_sel ? ext_wstrb[0] : 1'b0),
    .reg_ctrl_we(spiflash_reg_ctrl_sel ? ext_wstrb[0] : 1'b0),
    .reg_di(ext_wdata), .reg_do(spiflash_reg_do), .reg_wait(spiflash_reg_wait)
);

// RV memory access
assign rv_addr  = flash_loading ? {11'b0, flash_addr} : mem_addr;
assign rv_wdata = flash_loading ? {flash_d, flash_d, flash_d, flash_d} : mem_wdata;
assign rv_wstrb = flash_loading ? flash_wstrb : mem_wstrb;
assign rv_valid = flash_loading ? flash_wr : mem_valid;

assign ram_rdata = rv_rdata;
assign ram_ready = rv_ready;

// Time counter register
reg [31:0] time_reg, cycle_reg;
reg [$clog2(FREQ/1000)-1:0] time_cnt;

always @(posedge clk, negedge resetn) begin
    if (~resetn) begin
        time_reg <= 0;
        time_cnt <= 0;
        cycle_reg <= 0;

    end else begin
        cycle_reg <= cycle_reg + 1;
        time_cnt <= time_cnt + 1;
        if (time_cnt == FREQ/1000-1) begin
            time_cnt <= 0;
            time_reg <= time_reg + 1;
        end
    end
end

endmodule
