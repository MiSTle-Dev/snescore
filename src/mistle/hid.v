/*
    hid.v

    hid (keyboard, mouse etc) interface to the IO MCU
*/

module hid (
    input clk,
    input reset,

    input            data_in_strobe,
    input            data_in_start,
    input      [7:0] data_in,
    output reg [7:0] data_out,

    output reg [11:0] joystick0,
    output reg [11:0] joystick1
);

  reg [3:0] state;
  reg [7:0] command;
  reg [7:0] device;  // used for joystick

  reg irq_enable;
  reg [5:0] db9_portD;
  reg [5:0] db9_portD2;

  // process mouse events
  always @(posedge clk, posedge reset) begin
    if (reset) begin
      state <= 4'd0;
      joystick0 <= 12'b0;
      joystick1 <= 12'b0;
    end else begin
      if (data_in_strobe) begin
        if (data_in_start) begin
          state   <= 4'd0;
          command <= data_in;
        end else begin
          if (state != 4'd15) state <= state + 4'd1;

          // CMD 0: status data
          if (command == 8'd0) begin
            // return some dummy data for now ...
            if (state == 4'd0) data_out <= 8'h01;  // hid version 1
            if (state == 4'd1) data_out <= 8'h00;  // subversion 0
          end

          // CMD 1: keyboard data
          if (command == 8'd1) begin
            if (state == 4'd0) begin
            end
          end

          // CMD 3: receive digital joystick data
          if (command == 8'd3) begin
            if (state == 4'd0) device <= data_in;
            if (state == 4'd1) begin
              if (device == 8'd0) begin
                joystick0[7] <= data_in[0];
                joystick0[6] <= data_in[1];
                joystick0[5] <= data_in[2];
                joystick0[4] <= data_in[3];
                joystick0[8] <= data_in[4];
                joystick0[0] <= data_in[5];
                joystick0[9] <= data_in[6];
                joystick0[1] <= data_in[7];
              end
              if (device == 8'd1) begin
                joystick1[7] <= data_in[0];
                joystick1[6] <= data_in[1];
                joystick1[5] <= data_in[2];
                joystick1[4] <= data_in[3];
                joystick1[8] <= data_in[4];
                joystick1[0] <= data_in[5];
                joystick1[9] <= data_in[6];
                joystick1[1] <= data_in[7];
              end
            end
            if (state == 4'd4) begin
              if (device == 8'd0) begin
                joystick0[10] <= data_in[0];
                joystick0[11] <= data_in[1];
                joystick0[2]  <= data_in[2];
                joystick0[3]  <= data_in[3];
              end
              if (device == 8'd1) begin
                joystick1[10] <= data_in[0];
                joystick1[11] <= data_in[1];
                joystick1[2]  <= data_in[2];
                joystick1[3]  <= data_in[3];
              end
            end
          end
        end
      end
    end
  end

endmodule
