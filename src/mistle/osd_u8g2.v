/*
    osd_u8g2.v
 
    on-screen-display using a memory layout that matches the 
    one of 128x64 OLED displays and is thus supported by u8g2
  */

module osd_u8g2 (
  input        clk,
  input        reset,

  input        data_in_strobe,
  input        data_in_start,
  input [7:0]  data_in,
	    
  input        osd_clk,
  output       osd_enable,
  input [7:0]  osd_x,
  input [7:0]  osd_y,
  output [14:0] osd_color
);

// OSD is enabled and visible
reg enabled;
  
// some fake/test overlay when the iosys is not included
assign osd_enable = enabled?(osd_x >= 64 && osd_x < 192 && osd_y >= 64 && osd_y < 128):0;   

// bgr555: white foreground pixel, dark red background
wire osd_pix;   
assign osd_color = osd_pix?15'b11111_11111_11111:15'b00000_00000_01111;		     

// -------------------------- OSD painting -------------------------------

// 1024 bytes = 8192 pixels = 128 x 64 pixels
reg [7:0] buffer [1024];  

// external data interface to write to buffer
reg [9:0] data_cnt;
reg [7:0] command;
reg data_addr_state;
   
always @(posedge clk) begin
    if(reset) begin
        enabled <= 1'b0;
    end else begin

      if(data_in_strobe) begin
        if(data_in_start) begin
            command <= data_in;
            data_addr_state <= 1'b1;
            data_cnt <= 10'd0;
        end else begin
            data_addr_state <= 1'b0;

            // OSD command 1: enabled (show) or disable (hide) OSD
            if((command == 8'd1) && data_addr_state)
                enabled <= data_in[0];   // en/disable

            // OSD command 2: display data for give tile
            if(command == 8'd2) begin
                if(data_addr_state)
                    data_cnt <= { data_in[6:0], 3'b000 };
                else begin	 
                    buffer[data_cnt] <= data_in;
                    data_cnt <= data_cnt + 10'd1;
                end
            end
         end
      end
   end
end
   
wire [7:0] hpix  = osd_x-64;    // horizontal pixel position inside OSD   
wire [7:0] hpixD = hpix+1;      // latch byte one pixel in advance
wire [6:0] vpix  = osd_y-64;    // vertical pixel position inside OSD   

reg [7:0] buffer_byte;
assign osd_pix = buffer_byte[vpix[2:0]];
always @(posedge osd_clk)
  buffer_byte <= buffer[{ vpix[5:3], hpixD[6:0] }];
   
endmodule
