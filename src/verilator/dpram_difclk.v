// Dual-clock RAM used by the GSU cache. The VHDL implementation uses
// write-first reads for the non-Gowin configuration selected by Verilator.
module dpram_difclk #(
    parameter ADDR_WIDTH = 7,
    parameter DATA_WIDTH = 8
) (
    input                         clock0,
    input                         clock1,
    input      [DATA_WIDTH-1:0]   data_a,
    input      [DATA_WIDTH-1:0]   data_b,
    input      [ADDR_WIDTH-1:0]   address_a,
    input      [ADDR_WIDTH-1:0]   address_b,
    input                         wren_a,
    input                         wren_b,
    output reg [DATA_WIDTH-1:0]   q_a,
    output reg [DATA_WIDTH-1:0]   q_b
);

reg [DATA_WIDTH-1:0] mem [0:(1<<ADDR_WIDTH)-1];

always @(posedge clock0) begin
    if (wren_a)
        mem[address_a] <= data_a;
    q_a <= wren_a ? data_a : mem[address_a];
end

always @(posedge clock1) begin
    if (wren_b)
        mem[address_b] <= data_b;
    q_b <= wren_b ? data_b : mem[address_b];
end

endmodule
