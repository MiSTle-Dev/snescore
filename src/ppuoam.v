// PPU OAM: 512 bytes dual port

module ppuoam (
    input clock,
    input [7:0] address_a,
    input [6:0] address_b,
    input [15:0] data_a,
    input wren_a,
    output [15:0] q_a,
    output [31:0] q_b
);

`ifdef GOWIN

Gowin_DPB_OAM mem(.douta(q_a), .doutb(q_b), .clka(clock), .ocea(), .cea(1'b1), .reseta(1'b0),
            .wrea(wren_a), .clkb(clock), .oceb(), .ceb(1'b1), .resetb(1'b0),
            .wreb(1'b0), .ada(address_a), .dina(data_a), .adb(address_b), .dinb(32'b0));

`else

reg [15:0] mem [0:255];
reg [15:0] douta;
reg [31:0] doutb;

assign q_a = douta;
assign q_b = doutb;

always @(posedge clock) begin
    if (wren_a) begin
        mem[address_a] <= data_a;
`ifdef GOWIN
    end else
       douta <= mem[address_a];
`else
    end
    douta <= mem[address_a];
`endif
end

always @(posedge clock) begin
    doutb <= {mem[{address_b, 1'd1}], mem[{address_b, 1'd0}]};
end

`endif

endmodule
