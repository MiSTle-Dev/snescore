/*
 * Top level for snestang
 * nand2mario, 2023.6
 */

//`define STEP_TRACE

`include "config.vh"

`ifndef SDRAM_3CH
`error "Only three-channel SDRAM controller is supported for now"
`endif

`ifndef VERILATOR
`ifndef MEGA
`ifndef PRIMER
`ifndef NANO
`ifndef LATTICE
`error "Need to define VERILATOR, MEGA, PRIMER, NANO or LATTICE"
`endif
`endif
`endif
`endif
`endif

`ifndef VERILATOR
`ifndef LATTICE
`define GOWIN
`endif
`endif

module snestang_top #(
    parameter SNES_FREQ = `SNES_FREQ,
    parameter PIXEL_FREQ = `PIXEL_FREQ,
    parameter SDRAM_DATA_WIDTH = `SDRAM_DATA_WIDTH,
    parameter SDRAM_ROW_WIDTH = `SDRAM_ROW_WIDTH,
    parameter CORE_ID = 2 // SNEStang
) (
    input sys_clk,

`ifdef S0_N
    input s0_n,
`else
    input s0,
`endif

    // UART
    input UART_RXD,
    output UART_TXD,

    // HDMI TX
    output       tmds_clk_p,
    output [2:0] tmds_d_p,

`ifndef LATTICE
    output       tmds_clk_n,
    output [2:0] tmds_d_n,
`endif

    // MicroSD
`ifdef ENABLE_COMPANION
    output			    sdclk,
    inout			    sdcmd,
    inout [3:0]			    sddat, 

    input			    mcu_data_strobe,
    input			    mcu_data_start,
    input [7:0]			    mcu_data_in,
    output [7:0]		    mcu_data_out,
    output			    mcu_irq,
    input			    mcu_iack,  
`else
    output sd_clk,
    inout  sd_cmd,      // MOSI
    input  sd_dat0,     // MISO
    output sd_dat1,
    output sd_dat2,
    output sd_dat3,
`endif

    // SPI flash
    output flash_spi_cs_n,          // chip select
    input flash_spi_miso,           // master in slave out
    output flash_spi_mosi,          // mster out slave in
`ifndef LATTICE
    output flash_spi_clk,           // spi clock
`endif
    output flash_spi_wp_n,          // write protect
    output flash_spi_hold_n,        // hold operations

`ifdef CONTROLLER_SNES
    // snes controllers
    output joy1_strb,
    output joy1_clk,
    input joy1_data,
    output joy2_strb,
    output joy2_clk,
    input joy2_data,
`endif

`ifdef CONTROLLER_DS2
    // dualshock controllers
    output ds_clk,
    input ds_miso,
    output ds_mosi,
    output ds_cs,
    output ds_clk2,
    input ds_miso2,
    output ds_mosi2,
    output ds_cs2,
`endif

`ifdef CONTROLLER_USB_HID
    // Two USB HID gamepads; each port is connected directly to USB D+/D-.
    inout [1:0] usb_dp,
    inout [1:0] usb_dn,
    output [1:0] usb_pull_dp,
    output [1:0] usb_pull_dn,
`endif

`ifdef CONTROLLER_MISTLE
    // FPGA Companion
    input mcu_din,
    output mcu_dout,
    input mcu_clk,
    input mcu_ss,
    output mcu_intn,
    input mcu_spare,
`endif

`ifdef LATTICE
    input flash_spi_clk_ts,
`endif

`ifndef VERILATOR
    // SDRAM
    output O_sdram_clk,
    output O_sdram_cke,
    output O_sdram_cs_n,            // chip select
    output O_sdram_cas_n,           // columns address select
    output O_sdram_ras_n,           // row address select
    output O_sdram_wen_n,           // write enable
    inout [SDRAM_DATA_WIDTH-1:0] IO_sdram_dq,       // 31 bit bidirectional data bus
    output [SDRAM_ROW_WIDTH-1:0] O_sdram_addr,     // 11 bit multiplexed address bus
    output [SDRAM_DATA_WIDTH/8-1:0] O_sdram_dqm,       //
    output [1:0] O_sdram_ba,        // 4 banks
`endif

    // LED
    output [1:0] led
);

`ifdef VERILATOR
// sdram signals are internal in simulation since the simulated sdram is embedded
// here. To be able to use the --pins-inout-enables option for the remaining
// top level inout signals, these sdram signals must not be exposed. Otherwise the sdram
// inouts won't work with that option set.
wire O_sdram_clk;
wire O_sdram_cke;
wire O_sdram_cs_n;            // chip select
wire O_sdram_cas_n;           // columns address select
wire O_sdram_ras_n;           // row address select
wire O_sdram_wen_n;           // write enable
wire [SDRAM_DATA_WIDTH-1:0] IO_sdram_dq;       // 31 bit bidirectional data bus
wire [SDRAM_ROW_WIDTH-1:0]  O_sdram_addr;      // 11 bit multiplexed address bus
wire [SDRAM_DATA_WIDTH/8-1:0] O_sdram_dqm;     //
wire [1:0] O_sdram_ba;        // 4 banks
`endif

// Clock signals
wire mclk /* synthesis syn_keep = 1 */;                      // SNES master clock at 21.5054Mhz (~21.477)
wire fclk /* synthesis syn_keep = 1 */;                      // Fast clock for sdram for SDRAM
wire fclk_p /* synthesis syn_keep = 1 */;                    // 180-degree shifted fclk
wire clk27 /* synthesis syn_keep = 1 */;                     // 27Mhz for hdmi clock generation
wire hclk5 /* synthesis syn_keep = 1 */;                     // 720p pixel clock at 74.25Mhz, and 5x high-speeid
wire hclk /* synthesis syn_keep = 1 */;
// Board-specific 60 MHz USB clock. Supply it from a PLL when USB HID is enabled.
wire uclk /* synthesis syn_keep = 1 */;

assign O_sdram_clk = fclk_p;

wire pause;

`ifdef S0_N
wire s0 = ~s0_n;
`endif

wire pll_snes_lock, pll_hdmi_lock;
wire sdram_ready;
wire resetn, hclk_resetn, uclk_resetn, sdram_resetn;
wire iosys_resetn = resetn & ~s0;
wire reset = ~resetn;

`ifdef VERILATOR
// Simulated clocks for verilator
assign pll_snes_lock = 1'b1;
assign pll_hdmi_lock = 1'b1;

reg [2:0] clk_cnt = 0;          // 0 1 2 3 4 5 6 7

assign mclk   = clk_cnt[2];     // 0 0 0 0 1 1 1 1
assign fclk   = ~clk_cnt[0];    // 1 0 1 0 1 0 1 0
assign fclk_p = ~fclk;          // SDRAM samples half a fast cycle later.

always @(posedge sys_clk)
    clk_cnt <= clk_cnt + 1;

`elsif LATTICE
// Clocks for Lattice ECP5
ecp5_pll pll_snes (
    .clkin(sys_clk),
    .clkout0(uclk),
    .clkout1(mclk),
    .clkout2(fclk),
    .clkout3(clk27),
    .locked(pll_snes_lock)
);

ecp5_hdmi_pll pll_hdmi (
    .clkin(clk27),
    .clkout0(hclk5),
    .clkout1(hclk),
    .locked(pll_hdmi_lock)
);

ODDRX1F ddr_fclk_p (
    .D0(1'b0),
    .D1(1'b1),
    .Q(fclk_p),
    .SCLK(fclk),
    .RST(1'b0)
);

`elsif NANO
// Clocks for Nano 20K
assign clk27 = sys_clk;
gowin_pll_hdmi pll_hdmi (
    .clkin(sys_clk),            // 27 Mhz input
    .clkout(hclk5),             // 371.25Mhz
    .lock(pll_hdmi_lock)
);

CLKDIV #(.DIV_MODE(5)) div5 (
    .CLKOUT(hclk),              // 74.25Mhz
    .HCLKIN(hclk5),
    .RESETN(pll_hdmi_lock),
    .CALIB(1'b0)
);

gowin_pll_snes pll_snes (
    .clkin(sys_clk),
    .clkout(fclk),              // 86.4
    .clkoutp(fclk_p),           // 225-degrees shifted
    .clkoutd(mclk),             // 21.6
    .lock(pll_snes_lock)
);

`else
// Clocks for other Gowin boards
wire pll_27_lock, pll_hdmi_core_lock;
assign pll_hdmi_lock = pll_27_lock & pll_hdmi_core_lock;
gowin_pll_snes pll_snes (
    .clkout0(mclk),             // 21.4844
    .clkout1(fclk),
    .clkout2(fclk_p),
    .lock(pll_snes_lock),
    .clkin(sys_clk)             // 50 Mhz input
);

// HDMI clocks
gowin_pll_27 pll_27 (
    .clkin(sys_clk),
    .clkout0(clk27),
    .lock(pll_27_lock)
);
gowin_pll_hdmi pll_hdmi (
    .clkin(clk27),              // 27 Mhz input
    .clkout0(hclk5),
    .clkout1(hclk),
    .lock(pll_hdmi_core_lock)
);
`endif

rst_sync resets (
    .clk_mclk(mclk), .clk_fclk(fclk), .clk_hclk(hclk), .clk_uclk(uclk),
    .pll_snes_lock(pll_snes_lock), .pll_hdmi_lock(pll_hdmi_lock),
    .sdram_ready(sdram_ready),
    .rst_mclk_n(resetn),
    .rst_hclk_n(hclk_resetn), .rst_uclk_n(uclk_resetn),
    .rst_sdram_n(sdram_resetn)
);

wire DOT_CLK_CE;

wire [23:0] ROM_ADDR;
wire        ROM_CE_N;
wire        ROM_OE_N;
wire        ROM_WE_N;
wire        ROM_WORD;
wire [15:0] ROM_D;
wire [15:0] ROM_Q;

wire [22:0] GSU_ROM_ADDR;

wire        GSU_ROM_REQ;
reg         GSU_ROM_ACCEPT;
reg         GSU_ROM_DONE;
wire [15:0] gsu_rom_word;
reg         gsu_byte_sel;
wire [7:0]  GSU_ROM_Q = gsu_byte_sel ? gsu_rom_word[15:8] : gsu_rom_word[7:0];

wire [16:0] WRAM_ADDR;
wire        WRAM_CE_N;
wire        WRAM_OE_N;
wire        WRAM_RD_N;
wire        WRAM_WE_N;
wire  [7:0] WRAM_Q;
wire  [7:0] WRAM_D;

wire [19:0] BSRAM_ADDR;
wire        BSRAM_CE_N;
wire        BSRAM_OE_N;
wire        BSRAM_WE_N;
wire        BSRAM_RD_N;
wire  [7:0] BSRAM_Q;
wire  [7:0] BSRAM_D;

wire [15:0] VRAM1_ADDR;
wire [15:0] VRAM2_ADDR;
wire        VRAM_OE_N;
wire        VRAM1_WE_N;
wire        VRAM2_WE_N;
wire  [7:0] VRAM1_D, VRAM1_Q;
wire  [7:0] VRAM2_D, VRAM2_Q;

wire [15:0] ARAM_ADDR;
wire        ARAM_CE_N;
wire        ARAM_OE_N;
wire        ARAM_WE_N;
wire  [7:0] ARAM_Q;
wire  [7:0] ARAM_D;

wire BLEND = 1'b0;
wire PAL   = 1'b0; // we do support NTSC only

wire [7:0] R_OUT  /*verilator public*/;
wire [7:0] G_OUT  /*verilator public*/;
wire [7:0] B_OUT  /*verilator public*/;

wire [8:0] x_out /*verilator public*/;
wire [8:0] y_out /*verilator public*/;

wire       dotclk  /*verilator public*/;
wire       hblankn, vblankn;

wire [15:0] audio_l /*verilator public*/;
wire [15:0] audio_r /*verilator public*/;
wire        audio_ready /*verilator public*/;

wire       snes_joy_strb;
wire       snes_joy1_clk, snes_joy2_clk;
wire [1:0] snes_joy1_di, snes_joy2_di;

// Controller sources share a wired OR so enabled controllers can coexist.
wor  [11:0] joy1_btns, joy2_btns;
wire [11:0] hid1, hid2;

`ifndef MCU_BL616
assign hid1 = 12'b0;
assign hid2 = 12'b0;
`endif

// SNES order: R L X A Right Left Down Up Start Select Y B.
// For pads without Start/Select, hold X+Y and press A/B respectively.
// Consume the face buttons while a chord is active so games see only
// Start/Select (plus any held directions or shoulder buttons).
function [11:0] map_joy_chords;
    input [11:0] buttons;
    input chord_start, chord_select;
    reg chord_active;
    begin
        chord_active = chord_start | chord_select;
        map_joy_chords = buttons;
        map_joy_chords[9:8] = buttons[9:8] & {2{~chord_active}}; // X, A
        map_joy_chords[3] = buttons[3] | chord_start;   // Start
        map_joy_chords[2] = buttons[2] | chord_select;  // Select
        map_joy_chords[1:0] = buttons[1:0] & {2{~chord_active}}; // Y, B
    end
endfunction

wire [11:0] joy_raw [0:1];
wire [11:0] hid_raw [0:1];
wire [11:0] joy_mapped [0:1];
wire [11:0] joy_snes_mapped [0:1];

assign joy_raw[0] = joy1_btns;
assign joy_raw[1] = joy2_btns;
assign hid_raw[0] = hid1;
assign hid_raw[1] = hid2;

genvar joy_idx;
generate for (joy_idx = 0; joy_idx < 2; joy_idx = joy_idx + 1) begin : joy_chords
    wire [11:0] snes_raw = joy_raw[joy_idx] | hid_raw[joy_idx];
    reg [1:0] chord_q, snes_chord_q; // {Start, Select}

    // Only chord detection is registered; ordinary buttons stay combinational.
    always @(posedge mclk or negedge resetn) begin
        if (!resetn) begin
            chord_q <= 2'b0;
            snes_chord_q <= 2'b0;
        end else begin
            chord_q <= {joy_raw[joy_idx][9] & joy_raw[joy_idx][1] & joy_raw[joy_idx][8],
                        joy_raw[joy_idx][9] & joy_raw[joy_idx][1] & joy_raw[joy_idx][0]};
            snes_chord_q <= {snes_raw[9] & snes_raw[1] & snes_raw[8],
                             snes_raw[9] & snes_raw[1] & snes_raw[0]};
        end
    end

    assign joy_mapped[joy_idx] = map_joy_chords(joy_raw[joy_idx], chord_q[1], chord_q[0]);
    assign joy_snes_mapped[joy_idx] = map_joy_chords(snes_raw, snes_chord_q[1], snes_chord_q[0]);
end endgenerate

wire [11:0] joy1_mapped = joy_mapped[0], joy2_mapped = joy_mapped[1];
wire [11:0] joy1_snes_mapped = joy_snes_mapped[0], joy2_snes_mapped = joy_snes_mapped[1];

wire pause_snes_for_frame_sync;

wire [7:0] loader_do;
wire loader_do_valid, loader_do_ready;
wire loading, header_finished;

`ifdef ENABLE_COMPANION
wire header_ok;
`endif
   
reg loaded;

reg [22:0] loader_addr = 0;

wire [7:0] rom_type;
wire [3:0] rom_size, ram_size;
wire [23:0] rom_mask, ram_mask;

wire sdram_refreshing;

wire refresh;
wire snes_enable;

reg snes_resetn = 1'b0;

always @(posedge mclk, negedge iosys_resetn) begin
    if (~iosys_resetn)
        snes_resetn <= 1'b0;
    else
        snes_resetn <= iosys_resetn & ~loading;
end

assign snes_enable = loaded && ~pause_snes_for_frame_sync;

wire sysclkf_ce, sysclkr_ce;
wire overlay;

`ifdef CHIP_DSPn
parameter USE_DSPn = 1;
`else
parameter USE_DSPn = 0;
`endif

`ifdef CHIP_GSU
parameter USE_GSU = 1;
`else
parameter USE_GSU = 0;
`endif

`ifndef DISABLE_SNES
main #(
    .USE_DSPn(USE_DSPn),
    .USE_GSU(USE_GSU),
    .USE_SS(1'b0)
) main (
    .MCLK(mclk), .ACLK(mclk), .RESET_N(snes_resetn), .ENABLE(snes_enable),
    .SYSCLKF_CE(sysclkf_ce), .SYSCLKR_CE(sysclkr_ce), .REFRESH(refresh),

    .ROM_TYPE(rom_type), .ROM_MASK(rom_mask), .RAM_MASK(ram_mask), .RAM_SIZE(ram_size),

    .ROM_ADDR(ROM_ADDR), .ROM_D(ROM_D), .ROM_Q(ROM_Q),
    .ROM_CE_N(ROM_CE_N), .ROM_OE_N(ROM_OE_N), .ROM_WE_N(ROM_WE_N),
    .ROM_WORD(ROM_WORD),

    .GSU_ROM_ADDR(GSU_ROM_ADDR), .GSU_ROM_REQ(GSU_ROM_REQ), .GSU_ROM_OWNED(),
    .GSU_ROM_ACCEPT(GSU_ROM_ACCEPT), .GSU_ROM_DONE(GSU_ROM_DONE),
    .GSU_ROM_Q(GSU_ROM_Q),

    .BSRAM_ADDR(BSRAM_ADDR), .BSRAM_D(BSRAM_D),	.BSRAM_Q(BSRAM_Q),
    .BSRAM_CE_N(BSRAM_CE_N), .BSRAM_OE_N(BSRAM_OE_N), .BSRAM_WE_N(BSRAM_WE_N),
    .BSRAM_RD_N(BSRAM_RD_N),

    .WRAM_ADDR(WRAM_ADDR), .WRAM_D(WRAM_D),	.WRAM_Q(WRAM_Q),
    .WRAM_CE_N(WRAM_CE_N), .WRAM_OE_N(WRAM_OE_N), .WRAM_WE_N(WRAM_WE_N),
    .WRAM_RD_N(WRAM_RD_N),

    .VRAM1_ADDR(VRAM1_ADDR), .VRAM1_DI(VRAM1_Q), .VRAM1_DO(VRAM1_D),
    .VRAM1_WE_N(VRAM1_WE_N), .VRAM2_ADDR(VRAM2_ADDR), .VRAM2_DI(VRAM2_Q),
    .VRAM2_DO(VRAM2_D), .VRAM2_WE_N(VRAM2_WE_N), .VRAM_OE_N(VRAM_OE_N),

    .ARAM_ADDR(ARAM_ADDR), .ARAM_Q(ARAM_Q), .ARAM_D(ARAM_D),
    .ARAM_CE_N(ARAM_CE_N), .ARAM_OE_N(ARAM_OE_N), .ARAM_WE_N(ARAM_WE_N),

    .BLEND(BLEND), .PAL(PAL), .HIGH_RES(), .FIELD(), .INTERLACE(),
    .DOTCLK(dotclk), .R(R_OUT), .G(G_OUT), .B(B_OUT), .HBLANKn(hblankn),
    .VBLANKn(vblankn), .X_OUT(x_out), .Y_OUT(y_out),

    .JOY1_DI(overlay?2'b11:snes_joy1_di), .JOY2_DI(overlay?2'b11:snes_joy2_di), .JOY_STRB(snes_joy_strb),
    .JOY1_CLK(snes_joy1_clk), .JOY2_CLK(snes_joy2_clk),

    .AUDIO_L(audio_l), .AUDIO_R(audio_r), .AUDIO_READY(audio_ready),

    .JOY1_P6(), .JOY2_P6(), .JOY2_P6_in(1'b0), .DOT_CLK_CE(DOT_CLK_CE), .EXT_RTC(65'd0),
    .GG_EN(1'b0), .GG_CODE(129'd0), .GG_RESET(1'b0), .GG_AVAILABLE(),
    .SPC_MODE(1'b0), .IO_ADDR(17'd0), .IO_DAT(16'd0), .IO_WR(1'b0),

    .TURBO(1'b0), .DSP_FREQ(1'b0),

    .GSU_TURBO(1'b0), .GSU_FASTROM(1'b0), .SUFAMI_SWAP(1'b0), .CC_DIP(8'd0),

    .MSU_TRACK_MOUNTING(1'b0), .MSU_TRACK_MISSING(1'b0), .MSU_AUDIO_STOP(1'b0),
    .MSU_AUDIO_SECTOR(22'd0), .MSU_AUDIO_LOOP_INDEX(32'd0),
    .MSU_DATA(8'd0), .MSU_DATA_ACK(1'b0), .MSU_ENABLE(1'b0),

    .SS_SAVE(1'b0), .SS_TOSD(1'b0), .SS_LOAD(1'b0), .SS_SLOT(2'b00),
    .SS_DDR_DI(64'd0), .SS_DDR_ACK(1'b0),

    .DBG_BG_EN(5'b11111), .DBG_CPU_EN(1'b1)
);
`endif

`ifdef DISABLE_SNES
assign GSU_ROM_REQ = 1'b0;
`endif

// SDRAM for SNES ROM, WRAM and ARAM
reg         cpu_port;
wire [15:0] cpu_port0;
wire [15:0] cpu_port1;

reg         cpu_req;
wire        cpu_req_ack;
reg  [1:0]  cpu_ds;
reg [15:0]  cpu_din;
reg [22:0]  cpu_addr;
reg         cpu_we;

reg [22:0]  rom_addr_sd;
reg         rom_word_valid;
wire        rom_rd = ~ROM_CE_N; // && ~ROM_OE_N;
// ROM_OE_N fires too late for SDRAM transaction to finish

reg [16:0]  wram_addr_sd;
reg         wram_word_valid;
reg         wram_wr_r;
wire        wram_rd = ~WRAM_CE_N & ~WRAM_RD_N;
wire        wram_wr = ~WRAM_CE_N & ~WRAM_WE_N;

reg         bsram_req;
wire        bsram_req_ack;
reg [19:0]  bsram_addr_sd;
reg [7:0]   bsram_din;
wire [7:0]  bsram_dout;
wire [15:0] bsram_word;
reg         bsram_wr_r;
reg         bsram_word_valid;
wire        bsram_rv_write_done;
wire        bsram_rd = ~BSRAM_CE_N & (~BSRAM_RD_N || rom_type[7:4] == 4'hC);
wire        bsram_wr = ~BSRAM_CE_N & ~BSRAM_WE_N;

reg         aram_req;
wire        aram_req_ack;
reg  [15:0] aram_addr_sd;
reg   [7:0] aram_din;
wire [15:0] aram_word;
reg         aram_word_valid;
reg         aram_wr_r;
wire        aram_rd = ~ARAM_CE_N & ~ARAM_OE_N;
wire        aram_wr = ~ARAM_CE_N & ~ARAM_WE_N;

assign ROM_Q  = (ROM_WORD || ~ROM_ADDR[0]) ? cpu_port0 : { cpu_port0[7:0], cpu_port0[15:8] };
assign WRAM_Q = WRAM_ADDR[0] ? cpu_port1[15:8] : cpu_port1[7:0];

`ifdef BSRAM_BRAM
assign BSRAM_Q = bsram_dout;
`else
assign BSRAM_Q = BSRAM_ADDR[0] ? bsram_word[15:8] : bsram_word[7:0];
`endif

assign ARAM_Q = ARAM_ADDR[0] ? aram_word[15:8] : aram_word[7:0];

// The GSU uses its own SDRAM request and data path for ROM access.
`ifdef CHIP_GSU
reg        gsu_req_toggle, gsu_inflight, gsu_req_armed, gsu_ack_seen, gsu_done_seen;
reg [22:1] gsu_word_addr, gsu_cached_addr;
reg        gsu_cache_valid;
wire       gsu_req_ack, gsu_read_done;

always @(posedge mclk) begin
    if (!resetn) begin
        gsu_req_toggle <= gsu_req_ack;
        gsu_inflight <= 0;
        gsu_req_armed <= 1;
        gsu_ack_seen <= gsu_req_ack;
        gsu_done_seen <= gsu_read_done;
        GSU_ROM_ACCEPT <= 0;
        GSU_ROM_DONE <= 0;
        gsu_cache_valid <= 0;

    end else begin
        GSU_ROM_ACCEPT <= 0;
        GSU_ROM_DONE <= 0;
        if (!GSU_ROM_REQ) gsu_req_armed <= 1;
        if (gsu_req_ack != gsu_ack_seen) begin
            gsu_ack_seen <= gsu_req_ack;
            GSU_ROM_ACCEPT <= 1;
        end
        if (gsu_read_done != gsu_done_seen) begin
            gsu_done_seen <= gsu_read_done;
            GSU_ROM_DONE <= 1;
            gsu_inflight <= 0;
            gsu_cached_addr <= gsu_word_addr;
            gsu_cache_valid <= 1;
        end
        if (GSU_ROM_REQ && gsu_req_armed && !gsu_inflight) begin
            gsu_byte_sel <= GSU_ROM_ADDR[0];
            gsu_req_armed <= 0;
            if (gsu_cache_valid && gsu_cached_addr == GSU_ROM_ADDR[22:1]) begin
                GSU_ROM_ACCEPT <= 1;
                GSU_ROM_DONE <= 1;
            end else begin
                gsu_word_addr <= GSU_ROM_ADDR[22:1];
                gsu_req_toggle <= ~gsu_req_toggle;
                gsu_inflight <= 1;
            end
        end
        if (loading || !snes_resetn) gsu_cache_valid <= 0;
    end
end
`endif

// Generate requests for the SDRAM ports.
always @(posedge mclk) begin
    if (~resetn) begin
        wram_wr_r <= 0;
        bsram_wr_r <= 0;
        aram_wr_r <= 0;
        rom_word_valid <= 0;
        wram_word_valid <= 0;
        bsram_word_valid <= 0;
        aram_word_valid <= 0;

    end else begin
        if (!wram_wr) wram_wr_r <= 0;
        if (!bsram_wr) bsram_wr_r <= 0;
        if (!aram_wr) aram_wr_r <= 0;

        if (bsram_rv_write_done) bsram_word_valid <= 0;

        if (cpu_req == cpu_req_ack) begin
            if ((loading  && loader_do_valid && loader_do_ready && header_finished && loader_addr[0]) ||
                (~loading && (rom_rd && (ROM_ADDR[22:1] != rom_addr_sd[22:1] || !rom_word_valid)))) begin
                rom_addr_sd <= loading ? loader_addr : ROM_ADDR[22:0];
                rom_word_valid <= ~loading;

                cpu_req <= ~cpu_req;
                cpu_addr <= loading ? loader_addr : ROM_ADDR[22:0];
                cpu_we <= loading;
                cpu_ds <= 2'b11;
                cpu_din <= {loader_do, loader_do_r};
                cpu_port <= 0;
            end

            if ((wram_rd && (WRAM_ADDR[16:1] != wram_addr_sd[16:1] || !wram_word_valid)) ||
                (wram_wr && (WRAM_ADDR[16:0] != wram_addr_sd[16:0])) ||
                (wram_wr && ~wram_wr_r)) begin
                wram_addr_sd <= WRAM_ADDR;
                wram_word_valid <= ~wram_wr;
                wram_wr_r <= wram_wr;

                cpu_req <= ~cpu_req;
                cpu_addr <= {6'b111_111, WRAM_ADDR[16:0]};
                cpu_we <= wram_wr;
                cpu_ds <= {WRAM_ADDR[0], ~WRAM_ADDR[0]};
                cpu_din <= {WRAM_D, WRAM_D};
                cpu_port <= 1;
            end
        end

        if (bsram_req == bsram_req_ack) begin
            if ((bsram_rd && (BSRAM_ADDR[19:1] != bsram_addr_sd[19:1] || !bsram_word_valid)) ||
                (bsram_wr && (BSRAM_ADDR[19:0] != bsram_addr_sd[19:0])) ||
                (bsram_wr && ~bsram_wr_r)) begin
                bsram_addr_sd <= BSRAM_ADDR;
                bsram_word_valid <= ~bsram_wr;
                bsram_wr_r <= bsram_wr;

                bsram_req <= ~bsram_req;
                bsram_din <= BSRAM_D;
            end
        end

        if (aram_req == aram_req_ack) begin
            if ((aram_rd && (ARAM_ADDR[15:1] != aram_addr_sd[15:1] || !aram_word_valid)) ||
                (aram_wr && (ARAM_ADDR[15:0] != aram_addr_sd[15:0])) ||
                (aram_wr && ~aram_wr_r)) begin
                aram_addr_sd <= ARAM_ADDR;
                aram_word_valid <= ~aram_wr;
                aram_wr_r <= aram_wr;

                aram_req <= ~aram_req;
                aram_din <= ARAM_D;
            end
        end
    end
end

localparam RV_IDLE_REQ0 = 3'd0;
localparam RV_WAIT0_REQ1 = 3'd1;
localparam RV_DATA0 = 3'd2;
localparam RV_WAIT1 = 3'd3;
localparam RV_DATA1 = 3'd4;

reg [2:0]   rvst;

wire        rv_valid;
reg         rv_ready;
wire [22:0] rv_addr;
wire [31:0] rv_wdata;
wire [3:0]  rv_wstrb;
reg  [15:0] rv_dout0;
wire [31:0] rv_rdata = {rv_dout, rv_dout0};
reg         rv_valid_r;
reg         rv_word;           // which word
reg         rv_req;            // SDRAM request toggle
wire        rv_sdram_req_ack;
wire [15:0] rv_sdram_dout;
reg [1:0]   rv_ds;
reg         rv_new_req;
wire        rv_write = |rv_wstrb;
wire        rv_new_req_t = rv_valid & ~rv_valid_r;
`ifdef MCU_BL616
assign      bsram_rv_write_done = 1'b0;
`else
assign      bsram_rv_write_done = rv_ready && rv_write;
`endif

`ifdef BSRAM_BRAM
// IOSys maps 0x700000-0x7fffff to BSRAM. The 64 KiB block RAM mirrors
// throughout that window, as it does for the SNES BSRAM address port.
wire        rv_bsram_sel = rv_addr[22:20] == 3'b111;
reg         rv_bram_req, rv_bram_req_ack;
wire [15:0] rv_bram_dout;
reg         bsram_bram_req_ack;
wire        rv_req_ack = rv_bsram_sel ? rv_bram_req_ack : rv_sdram_req_ack;
wire        rv_req_active = rv_bsram_sel ? rv_bram_req : rv_req;
wire [15:0] rv_dout = rv_bsram_sel ? rv_bram_dout : rv_sdram_dout;
wire        bsram_bram_en = resetn;  // continuous read
`ifdef MCU_BL616
wire        rv_bram_en = 1'b0;
`else
wire        rv_bram_en = resetn && (rv_bram_req ^ rv_bram_req_ack);
`endif

bsram_bram bsram_mem (
    .clk(mclk),
    .snes_en(bsram_bram_en), .snes_addr(BSRAM_ADDR[15:0]),
    .snes_we(bsram_wr), .snes_din(BSRAM_D), .snes_dout(bsram_dout),
    .rv_en(rv_bram_en), .rv_addr({rv_addr[15:2], rv_word}),
    .rv_we(rv_write), .rv_ds(rv_ds),
    .rv_din(rv_word ? rv_wdata[31:16] : rv_wdata[15:0]), .rv_dout(rv_bram_dout)
);

always @(posedge mclk) begin
    if (~resetn) begin
        bsram_bram_req_ack <= 0;
        rv_bram_req_ack <= 0;

    end else begin
        bsram_bram_req_ack <= bsram_req;
        rv_bram_req_ack <= rv_bram_req;
    end
end
assign bsram_req_ack = bsram_bram_req_ack;
`else
wire        rv_req_ack = rv_sdram_req_ack;
wire        rv_req_active = rv_req;
wire [15:0] rv_dout = rv_sdram_dout;
`endif

reg [14:0] vram1_addr_sd, vram2_addr_sd;
reg vram1_we_n_r, vram2_we_n_r;
reg vram1_req /* synthesis syn_keep=1 */;
reg vram2_req /* synthesis syn_keep=1 */;
reg [7:0] vram1_din, vram2_din;

always @(posedge mclk) begin
    vram1_we_n_r <= VRAM1_WE_N;
    if ((~VRAM1_WE_N && vram1_we_n_r) || (~VRAM_OE_N && (VRAM1_ADDR[14:0] != vram1_addr_sd))) begin
        vram1_addr_sd <= VRAM1_ADDR[14:0];
        vram1_din <= VRAM1_D;
        vram1_req <= ~vram1_req;
    end

    vram2_we_n_r <= VRAM2_WE_N;
    if ((~VRAM2_WE_N && vram2_we_n_r) || (~VRAM_OE_N && (VRAM2_ADDR[14:0] != vram2_addr_sd))) begin
        vram2_addr_sd <= VRAM2_ADDR[14:0];
        vram2_din <= VRAM2_D;
        vram2_req <= ~vram2_req;
    end
end

`ifdef CHIP_GSU
sdram_snes_gsu sdram(
`else
sdram_snes sdram(
`endif
    .clk(fclk), .mclk(mclk), .clkref(DOT_CLK_CE), .resetn(sdram_resetn), .ready(sdram_ready), .refreshing(sdram_refreshing),

    // SDRAM pins
    .SDRAM_DQ(IO_sdram_dq), .SDRAM_A(O_sdram_addr), .SDRAM_BA(O_sdram_ba),
    .SDRAM_nCS(O_sdram_cs_n), .SDRAM_nWE(O_sdram_wen_n), .SDRAM_nRAS(O_sdram_ras_n),
    .SDRAM_nCAS(O_sdram_cas_n), .SDRAM_CKE(O_sdram_cke), .SDRAM_DQM(O_sdram_dqm),

    // CPU accesses
    .cpu_addr(cpu_addr[22:1]), .cpu_port(cpu_port), .cpu_din(cpu_din), .cpu_port0(cpu_port0), .cpu_port1(cpu_port1),
    .cpu_req(cpu_req), .cpu_req_ack(cpu_req_ack), .cpu_we(cpu_we), .cpu_ds(cpu_ds),

    // GSU rom accesses
`ifdef CHIP_GSU
    .gsu_addr(gsu_word_addr), .gsu_req(gsu_req_toggle),
    .gsu_req_ack(gsu_req_ack), .gsu_done(gsu_read_done), .gsu_dout(gsu_rom_word),
`endif

    // BSRAM accesses
`ifdef BSRAM_BRAM
    .bsram_addr(20'b0), .bsram_din(8'b0), .bsram_dout(),
    .bsram_req(1'b0), .bsram_req_ack(), .bsram_we(1'b0),
`else
    .bsram_addr(bsram_addr_sd), .bsram_din(bsram_din), .bsram_dout(bsram_word),
    .bsram_req(bsram_req), .bsram_req_ack(bsram_req_ack), .bsram_we(bsram_wr_r),
`endif

    // ARAM accesses
    .aram_addr(aram_addr_sd), .aram_din(aram_din), .aram_dout(aram_word),
    .aram_req(aram_req), .aram_req_ack(aram_req_ack), .aram_we(aram_wr_r),

    // VRAM accesses
    .vram1_addr(vram1_addr_sd), .vram1_din(vram1_din), .vram1_dout(VRAM1_Q),
    .vram1_req(vram1_req), .vram1_ack(), .vram1_we(~vram1_we_n_r),

    .vram2_addr(vram2_addr_sd), .vram2_din(vram2_din), .vram2_dout(VRAM2_Q),
    .vram2_req(vram2_req), .vram2_ack(), .vram2_we(~vram2_we_n_r),

    // IOSys risc-v softcore
`ifdef MCU_BL616
    .rv_addr(), .rv_din(), .rv_dout(),
    .rv_req(), .rv_req_ack(), .rv_ds(), .rv_we()
`else
    .rv_addr({rv_addr[22:2], rv_word}), .rv_din(rv_word ? rv_wdata[31:16] : rv_wdata[15:0]), .rv_dout(rv_sdram_dout),
    .rv_req(rv_req), .rv_req_ack(rv_sdram_req_ack), .rv_ds(rv_ds), .rv_we(rv_wstrb != 0)
`endif
);

assign loader_do_ready = cpu_req == cpu_req_ack;

reg [7:0] loader_do_r;
reg loading_r;

// Parse 64-byte rom header into rom_type and etc
smc_parser smc (
    .clk(mclk), .resetn(resetn & ~(loading & ~loading_r)),
    .rom_d(loader_do), .rom_strb(loader_do_valid),
    .rom_type(rom_type), .rom_mask(rom_mask), .ram_mask(ram_mask),
    .rom_size(rom_size), .ram_size(ram_size),
`ifdef ENABLE_COMPANION		  
    .header_ok(header_ok),
`endif
    .header_finished(header_finished)
);

always @(posedge mclk, negedge resetn) begin
    if (~resetn) begin
        loader_addr <= 0;
        loading_r <= 0;
        loaded <= 0;

    end else begin
        loading_r <= loading;
        if (loader_do_valid && loader_do_ready && header_finished) begin
            loader_addr <= loader_addr + 23'd1;
            loader_do_r <= loader_do;
        end
        if (loading & ~loading_r) begin
            loader_addr <= 0;
            loaded <= 0;
        end
        if (~loading & loading_r)
            loaded <= 1;
    end
end

`ifndef VERILATOR

// Controller input
`ifdef CONTROLLER_SNES
controller_snes joy1_snes (
    .clk(mclk), .resetn(resetn), .buttons(joy1_btns),
    .joy_strb(joy1_strb), .joy_clk(joy1_clk), .joy_data(joy1_data)
);
controller_snes joy2_snes (
    .clk(mclk), .resetn(resetn), .buttons(joy2_btns),
    .joy_strb(joy2_strb), .joy_clk(joy2_clk), .joy_data(joy2_data)
);
`endif

`ifdef CONTROLLER_DS2
controller_ds2 joy1_ds2 (
    .clk(mclk), .snes_buttons(joy1_btns),
    .ds_clk(ds_clk), .ds_miso(ds_miso), .ds_mosi(ds_mosi), .ds_cs(ds_cs)
);
controller_ds2 joy2_ds2 (
   .clk(mclk), .snes_buttons(joy2_btns),
   .ds_clk(ds_clk2), .ds_miso(ds_miso2), .ds_mosi(ds_mosi2), .ds_cs(ds_cs2)
);
`endif

`ifdef CONTROLLER_USB_HID
wire [1:0] usb_oe, usb_dp_o, usb_dm_o;
wire [9:0] usb_rom_addr [0:1];
wire [3:0] usb_rom_data [0:1];
wire [11:0] usb_game_buttons [0:1];

genvar usb_port;
generate for (usb_port = 0; usb_port < 2; usb_port = usb_port + 1) begin : usb_hid_ports
    wire [1:0] typ;
    wire game_l, game_r, game_u, game_d;
    wire game_a, game_b, game_x, game_y, game_sel, game_sta;
    wire [3:0] game_extra;

    assign usb_dp[usb_port] = usb_oe[usb_port] ? usb_dp_o[usb_port] : 1'bz;
    assign usb_dn[usb_port] = usb_oe[usb_port] ? usb_dm_o[usb_port] : 1'bz;

    assign usb_pull_dp = 2'b00;
    assign usb_pull_dn = 2'b00;

    usb_hid_host #(
        .FULL_SPEED(1), .KEYBOARD_SUPPORT(0), .MOUSE_SUPPORT(0), .GAME_SUPPORT(1)
    ) usb_host (
        .clk(uclk), .reset(~uclk_resetn), .cs(1'b1),
        .usb_dp_i(usb_dp[usb_port]), .usb_dm_i(usb_dn[usb_port]),
        .usb_dp_o(usb_dp_o[usb_port]), .usb_dm_o(usb_dm_o[usb_port]),
        .usb_oe(usb_oe[usb_port]), .typ(typ),
        .game_l(game_l), .game_r(game_r), .game_u(game_u), .game_d(game_d),
        .game_a(game_a), .game_b(game_b), .game_x(game_x), .game_y(game_y),
        .game_sel(game_sel), .game_sta(game_sta), .game_extra(game_extra),
        .rom_addr(usb_rom_addr[usb_port]), .rom_dout(usb_rom_data[usb_port])
    );

    // SNES order: R L X A Right Left Down Up Start Select Y B.
    // Either shoulder or trigger activates the corresponding SNES shoulder.
    assign usb_game_buttons[usb_port] = typ == 2'd3 ?
        {game_extra[1] | game_extra[0], game_extra[3] | game_extra[2],
         game_x, game_a, game_r, game_l, game_d, game_u,
         game_sta, game_sel, game_y, game_b} : 12'b0;

end endgenerate

usb_hid_host_dual_rom #(
`ifdef LATTICE
    .MEMORY_FILE("../usb_hid_host/rom/usb_hid_host_rom.mem")
`else
    .MEMORY_FILE("src/usb_hid_host/rom/usb_hid_host_rom.mem")
`endif
) usb_rom (
    .clk(uclk),
    .addra(usb_rom_addr[0]), .douta(usb_rom_data[0]), .ena(1'b1),
    .addrb(usb_rom_addr[1]), .doutb(usb_rom_data[1]), .enb(1'b1)
);

`ifdef LATTICE
// Swap controllers for IcePi (better physical access to 2nd USB port)
assign joy1_btns = usb_game_buttons[1];
assign joy2_btns = usb_game_buttons[0];
`else
assign joy1_btns = usb_game_buttons[0];
assign joy2_btns = usb_game_buttons[1];
`endif
`endif

`ifdef CONTROLLER_MISTLE
wire mcu_hid_strobe;
wire mcu_start;

wire [7:0] mcu_data_out;
wire [7:0] hid_data_out;

`ifdef LATTICE
// filter companion SPI clock
wire [15:0] mcu_clk_i_d = { mcu_clk_i_d[14:0], mcu_clk } /* synthesis syn_keep=1 */ /* synthesis syn_dont_touch=1 */;
wire        mcu_clk_i   = ( mcu_clk_i && mcu_clk_i_d != 16'h0000) ||
                          (!mcu_clk_i && mcu_clk_i_d == 16'hffff) /* synthesis syn_keep=1 */ /* synthesis syn_dont_touch=1 */;
`else
wire mcu_clk_i = mcu_clk;
`endif

mcu_spi mcu (
  .clk(mclk),
  .reset(reset),

  // SPI interface to FPGA Companion
  .spi_io_ss (mcu_ss),
  .spi_io_clk(mcu_clk),
  .spi_io_din(mcu_din),
  .spi_io_dout(mcu_dout),

  // byte wide data in/out to the submodules
  .mcu_sys_strobe(),
  .mcu_hid_strobe(mcu_hid_strobe),
  .mcu_osd_strobe(),
  .mcu_sdc_strobe(),
  .mcu_start(mcu_start),
  .mcu_dout(mcu_data_out),
  .mcu_sys_din(8'b0),
  .mcu_hid_din(hid_data_out),
  .mcu_osd_din(8'b0),
  .mcu_sdc_din(8'b0)
);

assign mcu_intn = 1'b1;

hid hid (
  .clk(mclk),
  .reset(reset),

  .data_in_strobe(mcu_hid_strobe),
  .data_in_start(mcu_start),
  .data_in(mcu_data_out),
  .data_out(hid_data_out),

  .db9_port(6'b000000),
  .irq(),
  .iack(1'b1),

  .mouse_buttons(),

  .kbd_mouse_level(),
  .kbd_mouse_type(),
  .kbd_mouse_data(),
  .kbd_reset(),

  .joystick0(joy1_btns),
  .joystick1(joy2_btns)
);

`endif

// output button presses to SNES
controller_adapter joy1_adapter (
    .clk(mclk), .snes_joy_strb(snes_joy_strb),
    .snes_buttons(joy1_snes_mapped), .snes_joy_clk(snes_joy1_clk), .snes_joy_di(snes_joy1_di[0])
);
controller_adapter joy2_adapter (
    .clk(mclk), .snes_joy_strb(snes_joy_strb),
    .snes_buttons(joy2_snes_mapped), .snes_joy_clk(snes_joy2_clk), .snes_joy_di(snes_joy2_di[0])
);

assign snes_joy1_di[1] = 0;  // P3
assign snes_joy2_di[1] = 0;  // P4

wire [14:0] overlay_color;
wire [7:0] overlay_x;
wire [7:0] overlay_y;

wire [14:0] rgb5 = {B_OUT[7:3], G_OUT[7:3], R_OUT[7:3]};

`ifdef LATTICE
wire       tmds_clk_n;
wire [2:0] tmds_d_n;
`endif

snes2hdmi #(.SNES_FREQ(SNES_FREQ), .PIXEL_FREQ(PIXEL_FREQ)) s2h (
    .clk(mclk), .resetn(resetn), .pixel_resetn(hclk_resetn), .snes_refresh(refresh),
    .pause_snes_for_frame_sync(pause_snes_for_frame_sync),
    .dotclk(dotclk), .hblank(~hblankn),.vblank(~vblankn),.rgb5(rgb5),
    .xs(x_out), .ys(y_out),
    .overlay(overlay), .overlay_x(overlay_x), .overlay_y(overlay_y),
    .overlay_color(overlay_color),
    .audio_l(audio_l), .audio_r(audio_r), .audio_ready(audio_ready),
    .clk_pixel(hclk),.clk_5x_pixel(hclk5),
    .tmds_clk_n(tmds_clk_n), .tmds_clk_p(tmds_clk_p),
    .tmds_d_n(tmds_d_n), .tmds_d_p(tmds_d_p)
);

`ifdef MCU_BL616

iosys_bl616 #(.CORE_ID(CORE_ID), .FREQ(SNES_FREQ)) iosys (
    .clk(mclk), .hclk(hclk), .resetn(iosys_resetn),
    .overlay(overlay), .overlay_x(overlay_x), .overlay_y(overlay_y),
    .overlay_color(overlay_color),
    .joy1(joy1_mapped), .joy2(joy2_mapped), .hid1(hid1), .hid2(hid2),
    .uart_tx(UART_TXD), .uart_rx(UART_RXD),
    .rom_loading(loading), .rom_do(loader_do), .rom_do_valid(loader_do_valid)
);

`else

// IOSys for menu, rom loading...
`ifdef MCU_SERV
iosys_serv
`else
iosys_picorv32
`endif
    #(.CORE_ID(CORE_ID), .FREQ(SNES_FREQ)) iosys (
    .clk(mclk), .hclk(hclk), .resetn(iosys_resetn),

    .overlay(overlay), .overlay_x(overlay_x), .overlay_y(overlay_y),
    .overlay_color(overlay_color),

    .joy1(joy1_mapped), .joy2(joy2_mapped),

    .rom_loading(loading), .rom_do(loader_do), .rom_do_valid(loader_do_valid), .rom_do_ready(loader_do_ready),

    .rv_valid(rv_valid), .rv_ready(rv_ready), .rv_addr(rv_addr),
    .rv_wdata(rv_wdata), .rv_wstrb(rv_wstrb), .rv_rdata(rv_rdata),

    .flash_spi_cs_n(flash_spi_cs_n), .flash_spi_miso(flash_spi_miso),
    .flash_spi_mosi(flash_spi_mosi), .flash_spi_clk(flash_spi_clk),
    .flash_spi_wp_n(flash_spi_wp_n), .flash_spi_hold_n(flash_spi_hold_n),

    .uart_tx(UART_TXD), .uart_rx(UART_RXD),

    .sd_clk(sd_clk), .sd_cmd(sd_cmd), .sd_dat0(sd_dat0), .sd_dat1(sd_dat1),
    .sd_dat2(sd_dat2), .sd_dat3(sd_dat3)
);

`ifdef LATTICE
USRMCLK usrmclk (
    .USRMCLKI(flash_spi_clk),
    .USRMCLKTS(flash_spi_clk_ts)   // 0 = drive clock, this cannot be a constant!
) /* synthesis syn_noprune=1 */ ;
`endif

always @(posedge mclk) begin            // RV
    if (~resetn) begin
        rvst <= RV_IDLE_REQ0;
        rv_ready <= 0;
        rv_valid_r <= 0;
        rv_new_req <= 0;
        // Keep the toggle handshake idle across a warm reset.
        rv_req <= rv_sdram_req_ack;
`ifdef BSRAM_BRAM
        rv_bram_req <= rv_bram_req_ack;
`endif
    end else begin
        if (rv_new_req_t) rv_new_req <= 1;

        rv_ready <= 0;
        rv_valid_r <= rv_valid;

        case (rvst)
        RV_IDLE_REQ0: if (rv_new_req || rv_new_req_t) begin
            rv_new_req <= 0;
`ifdef BSRAM_BRAM
            if (rv_bsram_sel)
                rv_bram_req <= ~rv_bram_req;
            else
`endif
            rv_req <= ~rv_req;
            if (rv_write && rv_wstrb[1:0] == 2'b0) begin
                // shortcut for only writing the upper word
                rv_word <= 1;
                rv_ds <= rv_wstrb[3:2];
                rvst <= RV_WAIT1;
            end else begin
                rv_word <= 0;
                if (rv_write)
                    rv_ds <= rv_wstrb[1:0];
                else
                    rv_ds <= 2'b11;
                rvst <= RV_WAIT0_REQ1;
            end
        end

        RV_WAIT0_REQ1: begin
            if (rv_req_active == rv_req_ack) begin
                if (rv_write && rv_wstrb[3:2] == 2'b0) begin
                    // Only the lower halfword was written.
                    rv_ready <= 1;
                    rvst <= RV_IDLE_REQ0;
                end else begin
`ifdef BSRAM_BRAM
                    if (rv_bsram_sel)
                        rv_bram_req <= ~rv_bram_req;
                    else
`endif
                    rv_req <= ~rv_req;  // request upper halfword
                    rv_word <= 1;
                    rv_ds <= rv_write ? rv_wstrb[3:2] : 2'b11;
                    rvst <= rv_write ? RV_WAIT1 : RV_DATA0;
                end
            end
        end

        RV_DATA0: begin
            rv_dout0 <= rv_dout;
            rvst <= RV_WAIT1;
        end

        RV_WAIT1:
            if (rv_req_active == rv_req_ack) begin
                if (rv_write) begin
                    rv_ready <= 1;
                    rvst <= RV_IDLE_REQ0;
                end else
                    rvst <= RV_DATA1;
            end

        RV_DATA1: begin
            rv_ready <= 1;
            rvst <= RV_IDLE_REQ0;
        end

        default:;
        endcase
    end
end

`endif      // MCU_BL616

`else       // VERILATOR

`ifdef ENABLE_COMPANION
companion companion 
   (
    .clk(mclk), .resetn(resetn),

    .sd_clk(sdclk), .sd_cmd(sdcmd), .sd_dat(sddat),

    .mcu_data_strobe(mcu_data_strobe),
    .mcu_data_start(mcu_data_start),
    .mcu_data_in(mcu_data_in),
    .mcu_data_out(mcu_data_out),
    .mcu_irq(mcu_irq),
    .mcu_iack(mcu_iack),        
    
    .dout(loader_do), .dout_valid(loader_do_valid), .dout_ready(loader_do_ready),
    .loading(loading),

    .header_ok(header_ok)
);   
`else
// test loader with embedded rom
test_loader test_loader (
    .clk(mclk), .resetn(resetn),
    .dout(loader_do), .dout_valid(loader_do_valid), .dout_ready(loader_do_ready),
    .loading(loading), .fail()
);
`endif
		     
// test audio sink: FIFO-like rate limiting to sound sample generation
reg [3:0] sample_counter = 0;

always @(posedge mclk) begin
    if (audio_ready)
        sample_counter <= 0;
    else
        sample_counter <= sample_counter == 15 ? 15 : sample_counter + 1;
end

// test video sync by turning on pause_snes_for_frame_sync periodically
reg test_halt_snes, test_sync_done;
reg [3:0] test_halt_cnt = 0;

assign pause_snes_for_frame_sync = test_halt_snes;

always @(posedge mclk) begin    // halt SNES during snes dram refresh on line 2
    if (~resetn) begin
        test_halt_cnt <= 0;
        test_halt_snes <= 0;
        test_sync_done <= 0;

    end else begin
        if (~test_sync_done) begin
            if (~test_halt_snes) begin
                if (y_out[7:0] == 2 && refresh) begin
                    test_halt_snes <= 1;
                    test_halt_cnt <= 4'd12;        // halt snes for 13 cycles
                end
            end else begin
                if (test_halt_cnt != 0) begin
                    test_halt_cnt <= test_halt_cnt - 4'd1;
                end else begin
                    test_halt_snes <= 0;
                    test_sync_done <= 1;
                end
            end
        end else if (y_out[7:0] == 8'd200)
            test_sync_done <= 0;
    end
end
`endif

`ifdef LED_N
assign led[0] = ~resetn;
assign led[1] = ~loaded;
`else
assign led[0] = resetn;
assign led[1] = loaded;
`endif

`ifdef VERILATOR
sdr_chip_model #(
    .DATA_WIDTH(SDRAM_DATA_WIDTH),
    .ROW_WIDTH(SDRAM_ROW_WIDTH)
) sdram_chip (
    .clk(O_sdram_clk), .dq(IO_sdram_dq), .addr(O_sdram_addr),
    .dqm(O_sdram_dqm), .ba(O_sdram_ba), .cs_n(O_sdram_cs_n),
    .ras_n(O_sdram_ras_n), .cas_n(O_sdram_cas_n), .we_n(O_sdram_wen_n)
);
`endif

endmodule
