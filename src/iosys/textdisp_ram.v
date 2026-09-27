module textdisp_ram #(
    parameter DATA_WIDTH = 8,
    parameter ADDR_WIDTH = 11,
    parameter DEPTH      = (1 << ADDR_WIDTH)
) (
    // Port A
    input                       clka,
    output reg [DATA_WIDTH-1:0] douta,
    input                       wrena,
    input  [ADDR_WIDTH-1:0]     addra,
    input  [DATA_WIDTH-1:0]     dina,

    // Port B
    input                       clkb,
    output reg [DATA_WIDTH-1:0] doutb,
    input                       wrenb,
    input  [ADDR_WIDTH-1:0]     addrb,
    input  [DATA_WIDTH-1:0]     dinb
);

    reg [DATA_WIDTH-1:0] mem [0:DEPTH-1];
    integer i;

    initial begin
`ifdef LATTICE
        $readmemh("../iosys/logo/logo_pi.hex", mem, 896);
        $readmemh("../iosys/font/font.hex", mem, 1024);
`else
        $readmemh("logo/logo_tang.hex", mem, 896);
        $readmemh("font/font.hex", mem, 1024);
`endif
    end

    // Port A
    always @(posedge clka) begin
        if (wrena) begin
            mem[addra] <= dina;
`ifdef GOWIN
        end else
            douta <= mem[addra];
`else
        end
        douta <= mem[addra];
`endif
    end

    // Port B
    always @(posedge clkb) begin
        if (wrenb) begin
            mem[addrb] <= dinb;
`ifdef GOWIN
        end else
            doutb <= mem[addrb];
`else
        end
        doutb <= mem[addrb];
`endif
    end

endmodule
