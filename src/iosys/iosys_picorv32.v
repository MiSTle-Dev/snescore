// IOSys - PICORV32-based IO subsystem for snestang
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

`define MCU_PICORV32

`ifndef PICORV32_REGS
`ifdef PICORV32_V
`error "iosys.v must be read before picorv32.v!"
`endif

`define PICORV32_REGS picosoc_regs
`endif

`ifndef PICOSOC_MEM
`define PICOSOC_MEM picosoc_mem
`endif

// this macro can be used to check if the verilog files in your
// design are read in the correct order.
`define PICOSOC_V

module iosys_picorv32 #(
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

// PICORV32 softcore
wire mem_sel;
wire mem_valid;
wire mem_ready;

wire [31:0] mem_addr, mem_wdata;
wire  [3:0] mem_wstrb;
wire [31:0] mem_rdata;

wire ram_ready;
wire [31:0] ram_rdata;

assign mem_ready = ram_ready;
assign mem_rdata = ram_rdata;

wire ext_sel;
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

wire cpu_valid;
wire cpu_ready;

wire [31:0] cpu_addr, cpu_wdata;;
wire  [3:0] cpu_wstrb;
wire [31:0] cpu_rdata;

picorv32 #(
    .CATCH_ILLINSN(0),
    .ENABLE_COUNTERS(0),
    .ENABLE_COUNTERS64(0),
    .CATCH_MISALIGN(0),
    .TWO_STAGE_SHIFT(0)
) rv32 (
    .clk(clk), .resetn(resetn & flash_loaded),
    .mem_valid(cpu_valid), .mem_ready(cpu_ready), .mem_addr(cpu_addr),
    .mem_wdata(cpu_wdata), .mem_wstrb(cpu_wstrb), .mem_rdata(cpu_rdata)
);

assign mem_sel   = cpu_addr[31:30] == 2'b00;
assign mem_valid = cpu_valid && mem_sel;
assign mem_addr  = cpu_addr;
assign mem_wdata = cpu_wdata;
assign mem_wstrb = cpu_wstrb;

assign ext_sel   = cpu_addr[31:30] == 2'b01;
assign ext_valid = cpu_valid && ext_sel;
assign ext_addr  = cpu_addr[7:0];
assign ext_wdata = cpu_wdata;
assign ext_wstrb = cpu_wstrb;

assign romload_stream_sel = cpu_valid && cpu_addr[31];

assign cpu_rdata = ext_sel ? ext_rdata : mem_rdata;
assign cpu_ready = mem_ready | ext_ready;

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

module picosoc_regs (
	input clk, wen,
	input [5:0] waddr,
	input [5:0] raddr1,
	input [5:0] raddr2,
	input [31:0] wdata,
	output [31:0] rdata1,
	output [31:0] rdata2
);
	reg [31:0] regs [0:31];

	always @(posedge clk)
		if (wen) regs[waddr[4:0]] <= wdata;

	assign rdata1 = regs[raddr1[4:0]];
	assign rdata2 = regs[raddr2[4:0]];
endmodule
