`timescale 1ns/1ps
// Behavioral controller boundary, not an SDRAM pin/timing model.
// req/ack/done are phases (toggles), not one-cycle pulses. ds=1 enables a byte.
module bsram_sdram_model (
    input wire clk, resetn,
    input wire [19:0] addr,
    input wire [15:0] din,
    input wire [1:0] ds,
    input wire we, req,
    output reg ack = 0, done = 0,
    output reg [15:0] dout = 0,
    input integer ack_delay, done_delay,
    input wire early_data, initial_ack, initial_done
);
    reg [15:0] mem [0:524287];
    reg active = 0, accepted = 0;
    reg phase;
    reg [19:0] saved_addr;
    reg [15:0] saved_din;
    reg [1:0] saved_ds;
    reg saved_we;
    integer wait_ack, wait_done;
    integer payload_changes_after_ack = 0;

    // The opposite edge makes this model independent of DUT NBA ordering.
    always @(negedge clk) begin
        if (!resetn) begin
            ack = initial_ack;
            done = initial_done;
            dout = 16'hdead;
            active = 0;
            accepted = 0;
        end else begin
            if (!active && req != ack) begin
                active = 1;
                accepted = 0;
                phase = req;
                saved_addr = addr;
                saved_din = din;
                saved_ds = ds;
                saved_we = we;
                wait_ack = ack_delay;
                wait_done = done_delay;
                if (addr[0] !== 1'b0 || ds == 0)
                    $fatal(1, "SDRAM request must be word aligned with nonzero byte enables");
            end
            if (active) begin
                if (req !== phase)
                    $fatal(1, "SDRAM req changed before done");
                if (!accepted && {addr, din, ds, we} !==
                    {saved_addr, saved_din, saved_ds, saved_we})
                    $fatal(1, "SDRAM payload changed before ack");
                if (accepted && {addr, din, ds, we} !==
                    {saved_addr, saved_din, saved_ds, saved_we})
                    payload_changes_after_ack = payload_changes_after_ack + 1;
                if (!accepted) begin
                    if (wait_ack == 0) begin
                        ack = phase;
                        accepted = 1;
                        if (!saved_we && early_data)
                            dout = mem[saved_addr[19:1]];
                    end else wait_ack = wait_ack - 1;
                end
                if (accepted) begin
                    if (wait_done == 0) begin
                        if (saved_we) begin
                            if (saved_ds[0]) mem[saved_addr[19:1]][7:0] = saved_din[7:0];
                            if (saved_ds[1]) mem[saved_addr[19:1]][15:8] = saved_din[15:8];
                        end else dout = mem[saved_addr[19:1]];
                        done = ~done;
                        active = 0;
                    end else wait_done = wait_done - 1;
                end
            end else if (!early_data) begin
                // Deliberately useless data between transfers catches early sampling.
                dout = 16'hdead;
            end
        end
    end
endmodule
