`timescale 1ns/1ps

module spiflash_init_tb;
    reg clk = 0;
    reg resetn = 0;
    reg start = 0;
    wire ncs, mosi, sck;
    wire [7:0] dout;
    wire dout_strb;
    integer transaction = -1;
    integer bits = 0;
    integer bytes_in_transaction = 0;
    integer clocks_per_transaction [0:3];
    reg [7:0] sampled = 0;
    reg [7:0] sent [0:3][0:5];
    integer received = 0;

    always #5 clk = ~clk;

    spiflash #(.ADDR(24'h500000), .LEN(2)) dut (
        .clk(clk), .resetn(resetn), .ncs(ncs), .miso(1'b1),
        .mosi(mosi), .sck(sck), .start(start), .busy(),
        .dout(dout), .dout_strb(dout_strb),
        .reg_byte_we(1'b0), .reg_word_we(1'b0), .reg_ctrl_we(1'b0),
        .reg_di(32'b0), .reg_do(), .reg_wait()
    );

    always @(negedge ncs) begin
        transaction = transaction + 1;
        bits = 0;
        bytes_in_transaction = 0;
        clocks_per_transaction[transaction] = 0;
    end

    always @(posedge sck) begin
        if (!ncs) begin
            clocks_per_transaction[transaction] = clocks_per_transaction[transaction] + 1;
            sampled = {sampled[6:0], mosi};
            bits = bits + 1;
            if (bits == 8) begin
                sent[transaction][bytes_in_transaction] = sampled;
                bytes_in_transaction = bytes_in_transaction + 1;
                bits = 0;
            end
        end
    end

    always @(posedge clk)
        if (dout_strb) received = received + 1;

    initial begin
        #23 resetn = 1;
        #10 start = 1; // Request firmware while mode-exit clocks are in progress.
        #10 start = 0;
        wait (received == 2);
        #100;
        if (transaction != 1 || clocks_per_transaction[0] != 16 ||
            sent[0][0] !== 8'hff || sent[0][1] !== 8'hff)
            $fatal(1, "flash mode-exit sequence is not 16 ones");
        if (clocks_per_transaction[1] != 48 ||
            sent[1][0] !== 8'h03 || sent[1][1] !== 8'h50 ||
            sent[1][2] !== 8'h00 || sent[1][3] !== 8'h00)
            $fatal(1, "firmware READ command or length is wrong");
        resetn = 0;
        #20 resetn = 1;
        #10 start = 1;
        #10 start = 0;
        wait (received == 4);
        #100;
        if (transaction != 3 || clocks_per_transaction[2] != 16 ||
            sent[2][0] !== 8'hff || sent[2][1] !== 8'hff ||
            clocks_per_transaction[3] != 48 || sent[3][0] !== 8'h03)
            $fatal(1, "reset did not repeat flash mode exit and read");
        $display("spiflash_init_tb PASS");
        $finish;
    end

    initial begin
        #20000;
        $fatal(1, "timed out waiting for firmware bytes");
    end
endmodule
