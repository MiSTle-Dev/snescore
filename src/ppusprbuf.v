// PPU SPR_BUF: 256 * 9 bits

module ppusprbuf (
    input clock,
    input [7:0] address_a,
    input [7:0] address_b,
    input [8:0] data_a,
    input wren_a,
    input wren_b,
    output [8:0] q_b
);

reg [8:0] mem [0:255];
reg [8:0] doutb;

assign q_b = doutb;

always @(posedge clock) begin
    if (wren_a)
        mem[address_a] <= data_a;
end

always @(posedge clock) begin
    if (wren_b) begin
        mem[address_b] <= 9'd0;
`ifdef GOWIN
    end else
       doutb <= mem[address_b];
`else
    end
    doutb <= mem[address_b];
`endif
end

endmodule
