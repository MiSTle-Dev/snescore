module ppuhoam (
    input clock,
    input [4:0] address,
    input [7:0] data,
    input wren,
    output [7:0] q
);

localparam GOWIN_BRAM =
`ifdef GOWIN
    1
`else
    0
`endif
`ifdef NANO
    && 0
`endif
;

generate
    if (GOWIN_BRAM)
        Gowin_SP_HOAM mem(.dout(q), .clk(clock), .oce(), .ce(1'b1), .reset(1'b0), .wre(wren), .ad(address), .din(data));
    else begin

        reg [7:0] mem [0:31];
        reg [7:0] dout;

        assign q = dout;

        always @(posedge clock) begin
            if (wren) begin
                mem[address] <= data;
        `ifdef GOWIN
            end else
                dout <= mem[address];
        `else
            end
            dout <= mem[address];
        `endif
        end
    end
endgenerate

endmodule
