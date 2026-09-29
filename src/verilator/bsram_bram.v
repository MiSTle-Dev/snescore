// Simulation model for the 64 KiB BSRAM block RAM.
// Port A is the SNES byte-wide port; port B is the RISC-V halfword port.
// Both ports share the simulation clock, while keeping independent enables
// and byte write strobes.
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
    output reg  [15:0] rv_dout
);

reg [15:0] mem [0:32767];
reg [15:0] snes_word;
reg        snes_high_sel;

assign snes_dout = snes_high_sel ? snes_word[15:8] : snes_word[7:0];

always @(posedge clk) begin
    if (snes_en) begin
        snes_high_sel <= snes_addr[0];
        snes_word <= mem[snes_addr[15:1]];
        if (snes_we) begin
            if (snes_addr[0])
                mem[snes_addr[15:1]][15:8] <= snes_din;
            else
                mem[snes_addr[15:1]][7:0] <= snes_din;
        end
    end

    if (rv_en) begin
        rv_dout <= mem[rv_addr];
        if (rv_we) begin
            if (rv_ds[0])
                mem[rv_addr][7:0] <= rv_din[7:0];
            if (rv_ds[1])
                mem[rv_addr][15:8] <= rv_din[15:8];
        end
    end
end

endmodule
