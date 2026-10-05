//
// SNEStang specific interface to the MiSTle companion
//

module companion (
    input	  clk,
    input	  resetn,

    // sd card
    output	  sd_clk,
    inout	  sd_cmd,
    inout [3:0]	  sd_dat,

`ifdef VERILATOR		     
    // This interface is only exposed in simulation when there
    // is no spi bus and the sd card interface is driven directly
    input	  mcu_sdc_strobe,
    input	  mcu_data_start,
    input [7:0]	  mcu_data_out,	// from mcu
    output [7:0]  sdc_data_out,	// to mcu
    output	  sdc_int,
    input	  sdc_iack,
`else
    // FPGA Companion
    input	  mcu_din,
    output	  mcu_dout,
    input	  mcu_clk,
    input	  mcu_ss,
    output	  mcu_intn,
    input	  mcu_spare,

     // OSD video overlay
    input	  osd_clk,
    output	  osd_enable,
    input [7:0]	  osd_x,
    input [7:0]	  osd_y,
    output [14:0] osd_color,

    input [1:0]   buttons,
		  
    output [11:0] joy1_btns,
    output [11:0] joy2_btns,

    output	  system_reset,
`endif
		  
    // rom loader interface	  
    output [7:0]  dout,
    output	  dout_valid,
    input	  dout_ready,
    output reg	  loading,
    input	  header_ok
);

`ifndef VERILATOR		     
`ifdef LATTICE
// filter companion SPI clock
wire [15:0] mcu_clk_i_d = { mcu_clk_i_d[14:0], mcu_clk } /* synthesis syn_keep=1 */ /* synthesis syn_dont_touch=1 */;
wire        mcu_clk_i   = ( mcu_clk_i && mcu_clk_i_d != 16'h0000) ||
                          (!mcu_clk_i && mcu_clk_i_d == 16'hffff) /* synthesis syn_keep=1 */ /* synthesis syn_dont_touch=1 */;
`else
wire mcu_clk_i = mcu_clk;
`endif

wire mcu_data_strobe;   
wire	mcu_data_start;   
wire [7:0] mcu_data_in;   
wire [7:0] mcu_data_out;   

wire       mcu_sys_strobe;        // mcu message byte valid for sysctrl
wire       mcu_hid_strobe;        // -"- hid
wire       mcu_osd_strobe;        // -"- osd
wire	   mcu_data_start;

wire [7:0] mcu_data_out;
wire [7:0] sys_data_out;  
wire [7:0] hid_data_out;  
wire [7:0] osd_data_out = 8'h55;  // OSD actually has no data output

`ifndef VERILATOR
// these are driven externally in simulation
wire       mcu_sdc_strobe;        // -"- sdc
wire [7:0] sdc_data_out;
`endif
   
mcu_spi mcu (
  .clk(clk),
  .reset(!resetn),

  // SPI interface to FPGA Companion
  .spi_io_ss (mcu_ss),
  .spi_io_clk(mcu_clk),
  .spi_io_din(mcu_din),
  .spi_io_dout(mcu_dout),

  // byte wide data in/out to the submodules
  .mcu_sys_strobe(mcu_sys_strobe),
  .mcu_hid_strobe(mcu_hid_strobe),
  .mcu_osd_strobe(mcu_osd_strobe),
  .mcu_sdc_strobe(mcu_sdc_strobe),
  .mcu_start(mcu_data_start),
  .mcu_dout(mcu_data_out),
  .mcu_sys_din(sys_data_out),
  .mcu_hid_din(hid_data_out),
  .mcu_osd_din(osd_data_out),
  .mcu_sdc_din(sdc_data_out)
);

// decode SPI/MCU data received for human input devices (HID) and
// convert into Amiga compatible mouse and keyboard signals
wire [7:0] int_ack;
wire hid_int;
wire hid_iack = int_ack[1];
   
`ifndef VERILATOR
// these are provided externally in simulation
wire sdc_iack = int_ack[3];
wire sdc_int;
`endif
   
hid hid (
  .clk(clk),
  .reset(!resetn),

  .data_in_strobe(mcu_hid_strobe),
  .data_in_start(mcu_data_start),
  .data_in(mcu_data_out),
  .data_out(hid_data_out),

  .db9_port(6'b000000),
  .irq( hid_int ),
  .iack( hid_iack ),

  .mouse_buttons(),

  .kbd_mouse_level(),
  .kbd_mouse_type(),
  .kbd_mouse_data(),
  .kbd_reset(),

  .joystick0(joy1_btns),
  .joystick1(joy2_btns)
);

sysctrl sysctrl (
        .clk(clk),
        .reset(!resetn),

         // interface to send and receive generic system control
        .data_in_strobe(mcu_sys_strobe),
        .data_in_start(mcu_data_start),
        .data_in(mcu_data_out),
        .data_out(sys_data_out),

        // values controlled by the OSD
        .system_reset(system_reset),

        .int_out_n(mcu_intn),
        .int_in( { 4'b0000, sdc_int, 1'b0, hid_int, 1'b0 }),
        .int_ack( int_ack ),

        .buttons( buttons ),
        .leds(),
        .color()
);
   

osd_u8g2 osd_u8g2 (
        .clk(clk),
        .reset(!resetn),

        .data_in_strobe(mcu_osd_strobe),
        .data_in_start(mcu_data_start),
        .data_in(mcu_data_out),

        // OSD video overlay
        .osd_clk(osd_clk),
        .osd_enable(osd_enable),
        .osd_x(osd_x),
        .osd_y(osd_y),
        .osd_color(osd_color)
);   

`endif

// -------------------------- rom loader --------------------------
reg [1:0] state;
   
wire [23:0] image_size;     // cartridge image size   
wire [7:0] image_mounted;   // up to eight images supported


// IO requests to sd card
reg	   sd_rd;   
reg [31:0] sd_sector;   
wire	   sd_busy;   
wire	   sd_done;   

// data from sd card   
wire sd_outen;
wire [8:0] sd_outaddr;
wire [7:0] sd_outdata;  

// number of data sectors expected during download
reg [14:0] rom_data_sectors;   
   
assign dout = sd_outdata;
assign dout_valid = 
	    ((state == 2'd1) && sd_outen && (sd_outaddr < 64)) ||
	    ((state == 2'd2) && sd_outen && (sd_outaddr >= 448)) ||
	    ((state == 2'd3) && sd_outen);   
   
always @(posedge clk) begin
   if(!resetn) begin
      state <= 2'd0;
      sd_rd <= 1'b0;
      loading <= 1'b0;      
   end else begin
      // sd card has delivered one byte
      if(sd_outen && (state == 2'd0))
	   $display("companion.v: Unexpeced sd card data");
      
      if(sd_busy)
	sd_rd <= 1'b0;
      
      if(sd_done) begin
	 // reading header sector from begin of file
	 if(state == 2'd1) begin
	    $display("companion.v: prepended header sector done: %d", header_ok);

	    if(header_ok) begin	    	    
	       sd_sector <= 32'd1;	    
	       state <= 2'd3;		  
	       sd_rd <= 1'b1;
	    end else begin
	       $display("companion.v: header parsing finally failed");
	    end
	 end // if (state == 2'd1)

	 // reading header sector from within the file
	 if(state == 2'd2) begin

	    // the embedded header may either be at offset $7fc0 or $ffc0. We
	    // check $ffc0 first and if the result does not seem to be a
	    // valid header, then we check at $7fc0	    
	    $display("companion.v: embedded header sector done: %d", header_ok);

	    // check if header was detected ok
	    if(header_ok) begin	    
	       state <= 2'd3;		  
	       sd_sector <= 32'd0;	    
	       sd_rd <= 1'b1;
	    end else if(sd_sector == 32'd127) begin
	       sd_sector <= 32'd63;
	       sd_rd <= 1'b1;
	    end else begin
	       $display("companion.v: header parsing finally failed");
	    end
	       
	 end // if (state == 2'd2)

	 // reading data sector
	 if(state == 2'd3) begin
	    rom_data_sectors <= rom_data_sectors - 15'd1;	    
	    
	    if(rom_data_sectors > 1) begin
	       sd_sector <= sd_sector + 32'd1;
	       sd_rd <= 1'b1;
	    end else begin
	      loading <= 1'b0;	    
	       state <= 2'd0;
	    end
	 end
      end // if (sd_done)
      
      // state == 0: fresh out of global reset or cartridge running
      if(state == 2'd0) begin
      
	 // wait for image to be mounted which means a cartridge
	 // is inserted
	 if(image_mounted[0]) begin
	    // check for a valid image length which is a multiple of
	    // 128 and may have an addional 512 byte header
	    // we can load images up to 4MB
	    
	    if((image_size & 24'hfe0000) && 
	       !(image_size & 24'h1fdff) &&
	       ((image_size & 24'hfe0000) < 24'd4194304)) begin

	       if(image_size[9]) begin	       
		  // some files have a 512 byte header of which the first
		  // 64 bytes are of interest
		  state <= 2'd1;
		  rom_data_sectors <= image_size[23:9] - 15'd1;
		  sd_sector <= 32'd0;
	       end else begin
		  // some don't have an extra header. Then the header data is
		  // at byte offset $7fc0 or $ffc0 which is the last 64
		  // bytes of sector 63 or 127
		  state <= 2'd2;
		  rom_data_sectors <= image_size[23:9];
		  sd_sector <= 32'd127;
	       end

	       // start download
	       sd_rd <= 1'b1;      
	       loading <= 1'b1;	       
	       
	    end else begin
	       $display("companion.v: Unsupported image size: %0d", image_size & 24'hfe0000 );
	       // TODO: show some visible sign of this failure ...
	    end // else: !if((image_size & 24'hfe0000) &&...
	 end
      end
   end // else: !if(!resetn)
end // always @ (posedge clk)   

sd_card #(
    .CLK_DIV(3'd0)                  // for 21 Mhz clock
`ifdef VERILATOR
    , .SIMULATE(1)
`endif
) sd_card (
    .rstn(resetn),                  // rstn active-low, 1:working, 0:reset
    .clk(clk),                      // clock
  
    // SD card signals
    .sdclk(sd_clk),
    .sdcmd(sd_cmd),
    .sddat(sd_dat),

    // mcu interface
    .data_strobe(mcu_sdc_strobe),
    .data_start(mcu_data_start),
    .data_out(sdc_data_out),
    .data_in(mcu_data_out),

    .irq(sdc_int),
    .iack(sdc_iack),	   
	   
    .image_mounted(image_mounted),
    .image_size(image_size),           // length of image file

    // user read sector command interface (sync with clk32)
    .rstart({7'b0000000, sd_rd} ), 
    .wstart(8'b00000000), 
    .rsector(sd_sector),
    .rbusy(sd_busy),
    .rdone(sd_done),

    // sector data output interface (sync with clk32)
    .inbyte(),
    .outen(sd_outen),       // when outen=1, a byte of sector content is read out from outbyte
    .outaddr(sd_outaddr),   // outaddr from 0 to 511, because the sector size is 512
    .outbyte(sd_outdata)    // a byte of sector content
);
   
endmodule
