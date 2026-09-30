// Run with: iverilog -g2012 -s tb_sdr_chip_model -o /tmp/tb_sdr_chip_model
//   verilator/tb_sdr_chip_model.sv verilator/sdr_chip_model.v
//   && vvp /tmp/tb_sdr_chip_model
module sdr_case #(
    parameter W = 16,
    parameter R = W == 16 ? 13 : 11,
    parameter C = W == 16 ? 9 : 8
) (output reg done = 0);
    reg clk = 0;
    always #5 clk = ~clk;

    tri [W-1:0] dq;
    reg drive = 0;
    reg [W-1:0] write_data = 0;
    assign dq = drive ? write_data : {W{1'bz}};

    reg [R-1:0] addr = 0;
    reg [W/8-1:0] dqm = 0;
    reg [1:0] ba = 0;
    reg cs_n = 1, ras_n = 1, cas_n = 1, we_n = 1;

    sdr_chip_model #(.DATA_WIDTH(W), .ROW_WIDTH(R), .COL_WIDTH(C)) chip (
        .clk(clk), .dq(dq), .addr(addr), .dqm(dqm), .ba(ba),
        .cs_n(cs_n), .ras_n(ras_n), .cas_n(cas_n), .we_n(we_n)
    );

    task command(input [2:0] code, input [1:0] bank,
                 input [R-1:0] address);
        @(negedge clk);
        ba = bank;
        addr = address;
        {cs_n, ras_n, cas_n, we_n} = {1'b0, code};
        @(posedge clk);
        #1;
        {cs_n, ras_n, cas_n, we_n} = 4'b1111;
    endtask

    localparam [R-1:0] ROW0 = 13'h1123;
    localparam [R-1:0] ROW1 = 13'h1abc;
    localparam [R-1:0] ROW2 = 13'h0555;
    localparam [R-1:0] COL = (1 << (C-1)) | 3;
    localparam [W-1:0] DATA0 = {W/8{8'h11}};
    localparam [W-1:0] DATA1 = {W/8{8'h22}};
    localparam [W-1:0] DATA2 = {W/8{8'h33}};
    localparam [W-1:0] MASKED_DATA0 = { {(W-8)/8{8'h11}}, 8'ha5 };
    localparam [2+R+C-1:0] INDEX0 = {2'd0, ROW0, COL[C-1:0]};
    localparam [2+R+C-1:0] INDEX1 = {2'd1, ROW1, COL[C-1:0]};
    localparam [2+R+C-1:0] INDEX2 = {2'd2, ROW2, COL[C-1:0]};

    initial begin
        command(3'b000, 0, 0); // mode register, single-word bursts
        command(3'b011, 0, ROW0);
        command(3'b011, 1, ROW1);
        command(3'b011, 2, ROW2);

        drive = 1;
        write_data = DATA0;
        command(3'b100, 0, COL);
        write_data = DATA1;
        command(3'b100, 1, COL);
        write_data = DATA2;
        command(3'b100, 2, COL);

        // Check the writes at their word addresses before exercising reads.
        if (chip.mem[INDEX0] !== DATA0) $fatal(1, "%0d-bit: bank 0 write: %h", W, chip.mem[INDEX0]);
        if (chip.mem[INDEX1] !== DATA1) $fatal(1, "%0d-bit: bank 1 write: %h", W, chip.mem[INDEX1]);
        if (chip.mem[INDEX2] !== DATA2) $fatal(1, "%0d-bit: bank 2 write: %h", W, chip.mem[INDEX2]);

        // DQM masks each byte independently; a fully masked write changes nothing.
        write_data = {W/8{8'ha5}};
        dqm = {W/8{1'b1}};
        dqm[0] = 1'b0;
        command(3'b100, 0, COL);
        if (chip.mem[INDEX0] !== MASKED_DATA0)
            $fatal(1, "%0d-bit: masked write: %h", W, chip.mem[INDEX0]);
        dqm = {W/8{1'b1}};
        command(3'b100, 1, COL);
        if (chip.mem[INDEX1] !== DATA1)
            $fatal(1, "%0d-bit: fully masked write changed bank 1: %h", W, chip.mem[INDEX1]);
        if (chip.mem[INDEX2] !== DATA2)
            $fatal(1, "%0d-bit: write changed bank 2: %h", W, chip.mem[INDEX2]);
        drive = 0;
        dqm = 0;

        command(3'b101, 0, COL); // read edges N, N+1, N+2
        if (dq !== {W{1'bz}}) $fatal(1, "%0d-bit: early data at N", W);
        command(3'b101, 1, COL);
        if (dq !== {W{1'bz}}) $fatal(1, "%0d-bit: early data at N+1", W);
        command(3'b101, 2, COL);
        if (dq !== MASKED_DATA0) $fatal(1, "%0d-bit: bank 0 at N+2: %h", W, dq);
        @(posedge clk); #1;
        if (dq !== DATA1) $fatal(1, "%0d-bit: bank 1 at N+3: %h", W, dq);
        @(posedge clk); #1;
        if (dq !== DATA2) $fatal(1, "%0d-bit: bank 2 at N+4: %h", W, dq);
        @(posedge clk); #1;
        if (dq !== {W{1'bz}}) $fatal(1, "%0d-bit: data lasted too long", W);

        $display("%0d-bit writes, bank interleaving and CL=2 passed", W);
        done = 1;
    end
endmodule

module tb_sdr_chip_model;
    wire done16, done32;
    sdr_case #(.W(16)) test16(done16);
    sdr_case #(.W(32)) test32(done32);
    initial begin
        wait(done16 && done32);
        $finish;
    end
endmodule
