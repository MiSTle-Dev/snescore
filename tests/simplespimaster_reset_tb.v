`timescale 1ns/1ps

module simplespimaster_reset_tb;
    reg clk = 0;
    reg resetn = 0;
    reg reg_byte_we = 0;
    reg [31:0] reg_di = 32'h000000a5;
    wire sck;
    integer clocks_after_reset = 0;
    reg watch_idle = 0;

    always #5 clk = ~clk;

    simplespimaster dut (
        .clk(clk), .resetn(resetn), .sck(sck), .mosi(), .miso(1'b1),
        .reg_byte_we(reg_byte_we), .reg_word_we(1'b0),
        .reg_di(reg_di), .reg_do(), .reg_wait()
    );

    always @(posedge sck)
        if (watch_idle) clocks_after_reset = clocks_after_reset + 1;

    initial begin
        #22 resetn = 1;
        #10 reg_byte_we = 1;
        #10 reg_byte_we = 0;
        #40 reg_byte_we = 1; // Queue a second request while SPI is busy.
        #10 reg_byte_we = 0;
        #10 resetn = 0;
        #20 resetn = 1;
        watch_idle = 1;
        #500;
        if (clocks_after_reset != 0)
            $fatal(1, "queued SPI request survived reset");
        $display("simplespimaster_reset_tb PASS");
        $finish;
    end
endmodule
