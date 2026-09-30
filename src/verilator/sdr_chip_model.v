// Behavioral SDR SDRAM model for the SNES controller simulation.
// DATA_WIDTH=16 models 32 MiB (4 banks x 8192 rows x 512 columns).
// DATA_WIDTH=32 models 8 MiB (4 banks x 2048 rows x 256 columns).
// The array is word addressed and public for testbench preloading.
module sdr_chip_model #(
    parameter DATA_WIDTH = 16,
    parameter ROW_WIDTH = DATA_WIDTH == 16 ? 13 : 11,
    parameter COL_WIDTH = DATA_WIDTH == 16 ? 9 : 8
) (
    input                         clk,
    inout      [DATA_WIDTH-1:0]   dq,
    input      [ROW_WIDTH-1:0]    addr,
    input      [DATA_WIDTH/8-1:0] dqm,
    input      [1:0]              ba,
    input                         cs_n,
    input                         ras_n,
    input                         cas_n,
    input                         we_n
);

/* verilator no_inline_module */

localparam WORD_ADDR_WIDTH = 2 + ROW_WIDTH + COL_WIDTH;
localparam WORD_COUNT = 1 << WORD_ADDR_WIDTH;

reg [DATA_WIDTH-1:0] mem [0:WORD_COUNT-1] /* verilator public_flat_rw */;
reg [ROW_WIDTH-1:0] row [0:3]; // independent active row for each bank

wire [2:0] command = {ras_n, cas_n, we_n};
localparam CMD_ACTIVE    = 3'b011;
localparam CMD_READ      = 3'b101;
localparam CMD_WRITE     = 3'b100;
localparam CMD_LOAD_MODE = 3'b000;

// A READ sampled on edge N drives DQ after edge N+2 (CL=2).
// Capture each read at its command edge so consecutive reads to different
// banks retain their own row, column and data as they pass through the pipe.
reg [2:0] read_valid = 3'b000;
reg [DATA_WIDTH-1:0] read_data0, read_data1, read_data2;
wire [WORD_ADDR_WIDTH-1:0] col_addr = {ba, row[ba], addr[COL_WIDTH-1:0]};

always @(posedge clk) begin
    read_valid[2:1] <= read_valid[1:0];
    read_valid[0] <= 1'b0;
    read_data1 <= read_data0;
    read_data2 <= read_data1;

    if (!cs_n) begin
        case (command)
            CMD_LOAD_MODE: ; // single-word accesses only
            CMD_ACTIVE: row[ba] <= addr;
            CMD_READ: begin
                read_data0 <= mem[col_addr];
                read_valid[0] <= 1'b1;
            end
            CMD_WRITE: begin
                for (integer byte_index = 0; byte_index < DATA_WIDTH/8; byte_index = byte_index + 1)
                    if (!dqm[byte_index]) begin
                        mem[col_addr][8*byte_index +: 8] <= dq[8*byte_index +: 8];
                    end
            end
            default: ; // NOP, refresh and precharge
        endcase
    end
end

assign dq = read_valid[2] ? read_data2 : {DATA_WIDTH{1'bz}};

endmodule
