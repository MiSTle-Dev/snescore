// Simulation model of the SDRAM controller for Verilator.
`include "config.vh"
// mclk     /   \___/   \___/   \___/   \___/   \___/   \___
// clkref   |   1   |   0   |   1   |   0   |   1   |   0   |
// cpu/rv   |  req  |  ack  |  data |
//                          |  req  |  ack  |  data |
// aram             |  req  |  ack  |  data |
//                                  |  req  |  ack  |  data |
`ifdef CHIP_GSU
module sdram_snes_gsu
`else
module sdram_snes
`endif
(
    input             clk,
    input             mclk,         // snes mclk
    input             clkref,
    input             resetn,

    // SDRAM side interface
    inout      [15:0] SDRAM_DQ,
    output     [12:0] SDRAM_A,
    output     [1:0]  SDRAM_BA,
    output reg        SDRAM_nCS, 
    output            SDRAM_nWE,
    output            SDRAM_nRAS,
    output            SDRAM_nCAS,
    output            SDRAM_CKE, 
    output reg  [1:0] SDRAM_DQM,

    // CPU access (ROM and WRAM) uses bank 0 and 1 (total 16MB)
	input      [15:0] cpu_din,
	input             cpu_port,
	output reg [15:0] cpu_port0,    // output register for bank 0
	output reg [15:0] cpu_port1,    // output register for bank 1
	input      [22:1] cpu_addr,     // 16MB memory space
	input             cpu_req,
    output reg        cpu_req_ack,
	input             cpu_we,
	input       [1:0] cpu_ds,       // byte enable

`ifdef CHIP_GSU
    input      [21:0] gsu_addr,   // 16-bit ROM word address
    input             gsu_req,
    output reg        gsu_req_ack,
    output reg        gsu_done,
    output reg [15:0] gsu_dout,
`endif

    input      [19:0] bsram_addr,
    input       [7:0] bsram_din,
    output reg [15:0] bsram_dout,
    input             bsram_req,
    output reg        bsram_req_ack,
    input             bsram_we,

    // ARAM access uses bank 2
	input             aram_16,      //16-bit access
	input      [15:0] aram_addr,
	input      [15:0] aram_din,
	output reg [15:0] aram_dout,
	input             aram_req,
    output reg        aram_req_ack,
    input             aram_we,

`ifdef SDRAM_3CH
    input      [14:0] vram1_addr,
    input       [7:0] vram1_din,
    output reg  [7:0] vram1_dout,
    input             vram1_req,
    output reg        vram1_ack,
    input             vram1_we,

    input      [14:0] vram2_addr,
    input       [7:0] vram2_din,
    output reg  [7:0] vram2_dout,
    input             vram2_req,
    output reg        vram2_ack,
    input             vram2_we,
`endif

    // Risc-V softcore uses bank 0-1 of 2nd chip
    input      [22:1] rv_addr,      // 8MB RV memory space
    input      [15:0] rv_din,       // 16-bit accesses
    input      [1:0]  rv_ds,
    output reg [15:0] rv_dout,      
    input             rv_req,
    output reg        rv_req_ack,
    input             rv_we,

    output            refreshing,

    output            ready
);

reg [15:0] mem_cpu [4*1024*1024];       // max 8MB
reg [15:0] mem_aram [32*1024];          // 64KB
reg [15:0] mem_bsram[64*1024];           // max 128KB
reg [15:0] mem_rv [0:1024*1024-1];      // RV's 2MB SDRAM region
reg [7:0] mem_vram1 [0:32*1024-1];
reg [7:0] mem_vram2 [0:32*1024-1];

initial $readmemh("random_4m_words.hex", mem_cpu);

reg cycle;          // cycle=1 at clkref posedge
reg clkref_r;

assign refreshing = 1'b0;
assign ready = 1'b1;           // Simulation memory has no initialization delay.

always @(posedge mclk) begin
    cycle <= ~cycle;
    clkref_r <= clkref;
    if (clkref & ~clkref_r)
        cycle <= 0;
end

localparam PORT_NONE = 0;

localparam PORT_CPU = 1;
localparam PORT_BSRAM = 2;
localparam PORT_RV = 3;
localparam PORT_GSU = 4;

localparam PORT_ARAM = 1;

reg [2:0] port [2];
reg cpu_req_r, bsram_req_r, aram_req_r;
reg we_latch[2], oe_latch[2];
reg [15:0] cpu_dout_pre, aram_dout_pre;
reg cpu_req_new, bsram_req_new, aram_req_new;
reg cpu_port_latch;
reg gsu_turn;

always @(posedge mclk) begin
    automatic reg cpu_req_new_t = cpu_req ^ cpu_req_r;
    automatic reg bsram_req_new_t = bsram_req ^ bsram_req_r;
    automatic reg aram_req_new_t = aram_req ^ aram_req_r;
    cpu_req_r <= cpu_req;
    bsram_req_r <= bsram_req;
    aram_req_r <= aram_req;
    cpu_req_new <= cpu_req_new_t;
    bsram_req_new <= bsram_req_new_t;
    aram_req_new <= aram_req_new_t;

    if (~resetn) begin
        port[0] <= 0;
        port[1] <= 0;
        cpu_req_ack <= 0;
        bsram_req_ack <= 0;
        aram_req_ack <= 0;
        rv_req_ack <= 0;
        gsu_turn <= 1;
`ifdef CHIP_GSU
        gsu_req_ack <= 0;
        gsu_done <= 0;
`endif
`ifdef SDRAM_3CH
        vram1_ack <= 0;
        vram2_ack <= 0;
`endif
    end else begin

`ifdef SDRAM_3CH
        // VRAM has its own SDRAM channel in the three-channel design.
        if (vram1_req != vram1_ack) begin
            if (vram1_we) mem_vram1[vram1_addr] <= vram1_din;
            else vram1_dout <= mem_vram1[vram1_addr];
            vram1_ack <= vram1_req;
        end
        if (vram2_req != vram2_ack) begin
            if (vram2_we) mem_vram2[vram2_addr] <= vram2_din;
            else vram2_dout <= mem_vram2[vram2_addr];
            vram2_ack <= vram2_req;
        end
`endif

        // RAS
        if (cycle == 1'b1) begin
            if (cpu_req_new_t || cpu_req_new) begin                 // CPU
                cpu_req_new <= 0;
                port[0] <= PORT_CPU;
                cpu_port_latch <= cpu_port;
                {we_latch[0], oe_latch[0]} <= {cpu_we, ~cpu_we};
                if (cpu_we) begin
                    case(cpu_ds)
                    2'b00: ;
                    2'b10: begin
                        mem_cpu[cpu_addr][15:8] <= cpu_din[15:8];
                        // $fdisplay(32'h80000002, "[%06x] <= %02x", {cpu_addr, 1'b1}, cpu_din[15:8]);
                    end
                    2'b01: begin
                        mem_cpu[cpu_addr][7:0] <= cpu_din[7:0];
                        // $fdisplay(32'h80000002, "[%06x] <= %02x", {cpu_addr, 1'b0}, cpu_din[7:0]);
                    end
                    2'b11:
                        mem_cpu[cpu_addr] <= cpu_din;
                    endcase
                end else
                    cpu_dout_pre <= mem_cpu[cpu_addr];
            end else if (bsram_req_new_t || bsram_req_new) begin    // BSRAM
                bsram_req_new <= 0;
                port[0] <= PORT_BSRAM;
                {we_latch[0], oe_latch[0]} <= {bsram_we, ~bsram_we};
                if (bsram_we) begin
                    if (bsram_addr[0])
                        mem_bsram[bsram_addr[16:1]][15:8] <= bsram_din;
                    else
                        mem_bsram[bsram_addr[16:1]][7:0] <= bsram_din;
                end else
                    cpu_dout_pre <= mem_bsram[bsram_addr[16:1]];
`ifdef CHIP_GSU
            end else if ((gsu_req ^ gsu_req_ack) &&
                         (!(rv_req ^ rv_req_ack) || gsu_turn)) begin
                port[0] <= PORT_GSU;
                gsu_turn <= 0;
                cpu_dout_pre <= mem_cpu[gsu_addr];
`endif
            end else if (rv_req ^ rv_req_ack) begin
                port[0] <= PORT_RV;
                gsu_turn <= 1;
                if (rv_we) begin
                    if (rv_ds[0]) mem_rv[rv_addr[20:1]][7:0] <= rv_din[7:0];
                    if (rv_ds[1]) mem_rv[rv_addr[20:1]][15:8] <= rv_din[15:8];
                end else
                    cpu_dout_pre <= mem_rv[rv_addr[20:1]];
            end
        end

        if (cycle == 1'b0) begin
            if (aram_req_new_t || aram_req_new) begin               // ARAM 
                aram_req_new <= 0;
                port[1] <= PORT_ARAM;
                {we_latch[1], oe_latch[1]} <= {aram_we, ~aram_we};
                if (aram_we) begin
                    if (aram_16)
                        mem_aram[aram_addr[15:1]] <= aram_din;
                    else if (aram_addr[0]) begin
                        mem_aram[aram_addr[15:1]][15:8] <= aram_din[15:8];
                        // $fdisplay(32'h80000002, "ARAM[%04x] <= %02x", aram_addr, aram_din[15:8]);
                    end else begin
                        mem_aram[aram_addr[15:1]][7:0] <= aram_din[7:0];
                        // $fdisplay(32'h80000002, "ARAM[%04x] <= %02x", aram_addr, aram_din[7:0]);
                    end
                end else if (aram_16)
                    aram_dout_pre <= mem_aram[aram_addr[15:1]];
                else if (aram_addr[0])
                    aram_dout_pre[15:8] <= mem_aram[aram_addr[15:1]][15:8];
                else
                    aram_dout_pre[7:0] <= mem_aram[aram_addr[15:1]][7:0]; 
            end
        end

        // CAS
        if (cycle == 1'b0) begin
            if (port[0] == PORT_CPU) begin                  // CPU
                cpu_req_ack <= cpu_req;
                if (cpu_port_latch)
                    cpu_port1 <= cpu_dout_pre; 
                else
                    cpu_port0 <= cpu_dout_pre; 
            end else if (port[0] == PORT_BSRAM) begin       // BSRAM
                bsram_req_ack <= bsram_req;
                bsram_dout <= cpu_dout_pre;
`ifdef CHIP_GSU
            end else if (port[0] == PORT_GSU) begin
                gsu_req_ack <= gsu_req;
                gsu_dout <= cpu_dout_pre;
                gsu_done <= ~gsu_done;
`endif
            end else if (port[0] == PORT_RV) begin
                rv_req_ack <= rv_req;
                rv_dout <= cpu_dout_pre;
            end
            port[0] <= PORT_NONE;
        end
        
        if (cycle == 1'b1) begin
            if (port[1] == PORT_ARAM) begin                 // ARAM 
                aram_req_ack <= aram_req;
                aram_dout <= aram_dout_pre;
            end
            port[1] <= PORT_NONE;
        end

        // DATA is readied in CAS phase
    end
end

endmodule
