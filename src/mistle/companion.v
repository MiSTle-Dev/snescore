//
// SNEStang specific interface to the MiSTle companion
//

//
// TODO: check $7fc0 first, so $ffc0 becomes the fallback
//

module companion (
    input	 clk,
    input	 resetn,

    // sd card
    output	 sd_clk,
    inout	 sd_cmd,
    inout [3:0]	 sd_dat,

    // This interface is only exposed in simulation when there
    // is no spi bus
    input	 mcu_data_strobe,
    input	 mcu_data_start,
    input [7:0]	 mcu_data_in,
    output [7:0] mcu_data_out,
    output	 mcu_irq,
    input	 mcu_iack,
		  
    // rom loader interface	  
    output [7:0] dout,
    output	 dout_valid,
    input	 dout_ready,
    output reg	 loading,
    input	 header_ok
);

reg [2:0] state;
   
wire [63:0] image_size;     // sd image size   
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
reg [15:0] rom_data_sectors;   
   
assign dout = sd_outdata;
assign dout_valid = 
	    ((state == 3'd1) && sd_outen && (sd_outaddr < 64)) ||
	    ((state == 3'd2) && sd_outen && (sd_outaddr >= 448)) ||
	    ((state == 3'd3) && sd_outen);   
   
always @(posedge clk) begin
   if(!resetn) begin
      state <= 3'd0;
      sd_rd <= 1'b0;
      loading <= 1'b0;      
   end else begin
      // sd card has delivered one byte
      if(sd_outen && (state == 3'd0))
	   $display("companion.v: Unexpeced sd card data");
      
      if(sd_busy)
	sd_rd <= 1'b0;
      
      if(sd_done) begin
	 // reading header sector from begin of file
	 if(state == 3'd1) begin
	    $display("companion.v: prepended header sector done: %d", header_ok);

	    if(header_ok) begin	    	    
	       sd_sector <= 32'd1;	    
	       state <= 3'd3;		  
	       sd_rd <= 1'b1;
	    end else begin
	       $display("companion.v: header parsing finally failed");
	    end
	 end // if (state == 3'd1)

	 // reading header sector from within the file
	 if(state == 3'd2) begin

	    // the embedded header may either be at offset $7fc0 or $ffc0. We
	    // check $ffc0 first and if the result does not seem to be a
	    // valid header, then we check at $7fc0	    
	    $display("companion.v: embedded header sector done: %d", header_ok);

	    // check if header was detected ok
	    if(header_ok) begin	    
	       state <= 3'd3;		  
	       sd_sector <= 32'd0;	    
	       sd_rd <= 1'b1;
	    end else if(sd_sector == 32'd127) begin
	       sd_sector <= 32'd63;
	       sd_rd <= 1'b1;
	    end else begin
	       $display("companion.v: header parsing finally failed");
	    end
	       
	 end // if (state == 3'd2)

	 // reading data sector
	 if(state == 3'd3) begin
	    rom_data_sectors <= rom_data_sectors - 16'd1;	    
	    
	    if(rom_data_sectors > 1) begin
	       sd_sector <= sd_sector + 32'd1;
	       sd_rd <= 1'b1;
	    end else
	      loading <= 1'b0;	    
	 end
      end // if (sd_done)
      
      
      // state == 0: fresh out of global reset
      if(state == 3'd0) begin
      
	 // wait for image to be mounted which means a cartridge
	 // is inserted
	 if(image_mounted[0]) begin
	    // check for a valid image length which is a multiple of
	    // 128 and may have an addional 512 byte header
	    // we can load images up to 4MB
	    
	    if((image_size & 64'hfffe0000) && 
	       !(image_size & 64'h1fdff) &&
	       ((image_size & 64'hfffe0000) < 64'd4194304)) begin

	       if(image_size[9]) begin	       
		  // some files have a 512 byte header of which the first
		  // 64 bytes are of interest
		  state <= 3'd1;
		  rom_data_sectors <= image_size[24:9] - 16'd1;
		  sd_sector <= 32'd0;
	       end else begin
		  // some don't have an extra header. Then the header data is
		  // at byte offset $7fc0 or $ffc0 which is the last 64
		  // bytes of sector 63 or 127
		  state <= 3'd2;
		  rom_data_sectors <= image_size[24:9];
		  sd_sector <= 32'd127;
	       end

	       // start download
	       sd_rd <= 1'b1;      
	       loading <= 1'b1;	       
	       
	    end else begin
	       $display("companion.v: Unsupported image size: %0d", image_size & 64'hfffe0000 );
	       // TODO: show some visible sign of this failure ...
	    end // else: !if((image_size & 64'hfffe0000) &&...
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
    .data_strobe(mcu_data_strobe),
    .data_start(mcu_data_start),
    .data_in(mcu_data_in),
    .data_out(mcu_data_out),

    .image_mounted(image_mounted),
    .image_size(image_size),           // length of image file

    // interrupt to signal communication request
    .irq(mcu_irq),
    .iack(mcu_iack),

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
