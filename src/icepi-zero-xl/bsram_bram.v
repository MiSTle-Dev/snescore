// 64 KiB BSRAM with independent SNES byte and RISC-V halfword ports.
// Both ports use mclk. Same-address simultaneous writes are undefined.
module bsram_bram (
    input             clk,
    input             snes_en,
    input      [15:0] snes_addr,
    input             snes_we,
    input       [7:0] snes_din,
    output wire [7:0] snes_dout,
    input             rv_en,
    input      [14:0] rv_addr,
    input             rv_we,
    input       [1:0] rv_ds,
    input      [15:0] rv_din,
    output wire [15:0] rv_dout
);

wire [15:0] snes_word;
reg snes_high_sel;
assign snes_dout = snes_high_sel ? snes_word[15:8] : snes_word[7:0];

always @(posedge clk)
    if (snes_en) snes_high_sel <= snes_addr[0];

bsram_bram_lattice ram (
    .DataInA({snes_din, snes_din}), .DataInB(rv_din),
    .ByteEnA(snes_addr[0] ? 2'b10 : 2'b01), .ByteEnB(rv_ds),
    .AddressA(snes_addr[15:1]), .AddressB(rv_addr),
    .ClockA(clk), .ClockB(clk),
    .ClockEnA(snes_en), .ClockEnB(rv_en),
    .WrA(snes_we), .WrB(rv_we),
    .ResetA(1'b0), .ResetB(1'b0),
    .QA(snes_word), .QB(rv_dout)
);

endmodule
