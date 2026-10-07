//
// sd_card.v - sd card wrapper currently used to interface to sd_rw.v
//
// This mainly multiplexes between the SD card and the core or MCU. The core
// has its own 512 byte sector buffer and will store SD card data such that
// it can internally read and write at any rate. This file also has a 512
// byte sector buffer to allow the same for the MCU communicating via SPI.
//
// The main testbench for this is the NanoMac's testbench. It allows to
// stress test concurrent FPGA Companion and Core accesses etc.
//

module sd_card # (
    parameter [2:0]	CLK_DIV = 3'd2,
    parameter		SIMULATE = 0
) (
    // rstn active-low, 1:working, 0:reset
    input			  rstn,
    input			  clk,
    output			  sdclk,
    inout			  sdcmd, 
    inout [3:0]		  sddat,

    // mcu interface
    input			  data_strobe,
    input			  data_start,
    input [7:0]		  data_in,
    output reg [7:0]  data_out,

    output reg		  irq,
    input			  iack,
   
    // export sd image size   
    output reg [23:0] image_size,
    output reg		  image_mounted,

    // read sector command interface (sync with clk), this once was
    // directly tied to the sd card. Now this goes to the MCU via the
    // MCU interface as the MCU translates sector numbers from those
    // the core tries to use to physical ones inside the file system
    // of the sd card
	input			  rstart,
    input			  wstart, 
    input [31:0]	  rsector,
    output			  rbusy,   //        busy and done are valid
    output			  rdone,

    // sector data output interface (sync with clk)
    input [7:0]		  inbyte,

	output			  outen,   // when outen=1, a byte of sector content
                               // is read out from outbyte
	output [8:0]	  outaddr, // outaddr from 0 to 511, because the
                               // sector size is 512
	output [7:0]	  outbyte  // a byte of sector content
);

wire [3:0] card_stat;  // show the sdcard initialize status
wire [1:0] card_type;  // 0=UNKNOWN    , 1=SDv1    , 2=SDv2  , 3=SDHCv2

reg [7:0] command;
reg [7:0] sub_command;
reg [3:0] byte_cnt;  

reg	  rstart_int;   
reg	  wstart_int;   
reg [31:0] lsector;  

// local buffer to hold one sector to be forwarded to the MCU
reg [8:0]  mcu_tx_cnt;
   
// only export outen if the resulting data is for the core
wire louten;  

// ===== keep track of MCU requesting sector IO ======
reg [2:0]  mcu_request;
localparam [2:0] MCU_REQ_IDLE       = 3'd0,   // waitring for mcu requests
				 MCU_REQ_READ       = 3'd1,   // received read request
				 MCU_REQ_WRITE      = 3'd2,   // received write request
				 MCU_READING        = 3'd3,   // SD card read in progress, writing data to local buffer
				 MCU_READY2TRANSFER = 3'd4,   // SD card read done, signal MCU that it may read from buffer
				 MCU_TRANSFERRING   = 3'd5,   // MCU is reading from buffer
				 MCU_READY2WRITE    = 3'd6,   // MCU has filled write buffer and sd write can be started
				 MCU_WRITING        = 3'd7;   // MCU is writing to SD card
   
reg [31:0] mcu_sector;   // sector requested by MCU

// ===== keep track of Core requesting sector IO ======
reg [2:0]  core_request;
localparam [2:0] CORE_REQ_IDLE      = 3'd0,   //waitring for core requests
				 CORE_REQ_READ      = 3'd1,
				 CORE_REQ_WRITE     = 3'd2,
				 CORE_READING       = 3'd3,   
				 CORE_WRITING       = 3'd4;
      
reg [31:0] core_sector;  // sector requested by core

wire	   busy_int;   // the internal/original busy signal as coming from the sd_rw
wire	   done_int;   //                   -"- done -"-

// The internal busy and done are only exposed to the core if a core transfer is being
// handled. This will prevent the core from seeing external MCU transfers and assuming
// its own request is being handled
wire core_in_progress = (core_request == CORE_READING) || (core_request == CORE_WRITING);   
assign rbusy = core_in_progress?busy_int:1'b0;
assign rdone = core_in_progress?done_int:1'b0;   
   
// drive outen only if the core reads data for itself
assign outen = (core_request == CORE_READING)?louten:1'b0;   
   
wire [7:0] inbyte_int;  

// interrupt handling
wire start = rstart || wstart;

// The MCU may allow for direct SD card access if the image is
// continous (not fragmeneted) on card. In that case only the
// start sector has to be known and the core will read and
// write from and to the sd card without and further interaction
// with the Companion.
//
// This 8-entry x 32-bit table is written by the MCU (indexed by
// image_target) and read by the core request logic (indexed by
// drive). Neither address is ever a function of the other, so a
// single synchronous write port plus a single asynchronous read
// port (dual-port pseudo RAM) is enough -- no address muxing
// between sources is needed. This shape lets ECP5 synthesis infer
// LUTRAM instead of a bank of muxed flip-flops.
reg [31:0] direct_start;

reg         direct_start_we;
reg  [31:0] direct_start_wdata;
wire [31:0] direct_start_rdata = direct_start;

// Asynchronous read
wire direct_enable = direct_start_rdata != 32'd0;

// Synchronous write
always @(posedge clk) begin
	if(direct_start_we)
		direct_start <= direct_start_wdata;
end
   
wire [7:0] doutb;
reg  dinb_we;
   
`ifdef INFER_DPRAM
sector_dpram #(8, 9) buffer
(
	.clock(clk),

    // SD card side of buffer
	.address_a(outaddr), 
	.wren_a((mcu_request == MCU_READING) && louten),
	.data_a(outbyte),
	.q_a(inbyte_int),

    // MCU/FPGA Companion side of buffer
	.address_b(mcu_tx_cnt),
	.wren_b(dinb_we),
	.data_b(data_in),
	.q_b(doutb)
);
`else   
sector_dpram buffer(
    // SD card side of buffer
    .clka(clk),
    .reseta(1'b0), 
    .cea(1'b1), 					
    .ada(outaddr), 
    .wrea((mcu_request == MCU_READING) && louten), 
    .dina(outbyte),
    .ocea(1'b1), 
    .douta(inbyte_int),
					
    // MCU/FPGA Companion side of buffer
    .clkb(clk), 
    .resetb(1'b0), 
    .ceb(1'b1), 
    .adb(mcu_tx_cnt), 
    .wreb(dinb_we), 
    .dinb(data_in),
    .oceb(1'b1), 
    .doutb(doutb)					
);
`endif

always @(posedge clk, negedge rstn) begin
   reg	  startD;   
   
   if(!rstn) begin
      irq <= 1'b0;
      startD <= 1'b0;
   end else begin
      startD <= start;

	  // Raising edge of start means that the core
	  // is requesting a sector read or write. If the requesting
	  // device is not enabled for direct io, then the MCU needs
	  // to be triggered for sector translation.
	  
      // iack clears interrupt
      if(iack)
        irq <= 1'b0;

      // rising edge of start raises interrupt
      if(start && !startD && !direct_enable)
        irq <= 1'b1;
   end   
end
   
reg [15:0] fifo_available;

// register the rising edge of rstart and clear it once
// it has been reported to the MCU
always @(posedge clk, negedge rstn) begin
   if(!rstn) begin
      byte_cnt <= 4'd15;
      command <= 8'hff;
      rstart_int <= 1'b0;
      wstart_int <= 1'b0;
      image_size <= 24'd0;
      image_mounted <= 1'b0;
      direct_start_we <= 1'b0;
      dinb_we <=1'b0;
	  
	  // no MCU or core request by now
	  mcu_request <= MCU_REQ_IDLE;	  
	  core_request <= CORE_REQ_IDLE;	  
   end else begin
      image_mounted <= 1'b0;
      direct_start_we <= 1'b0;

	  // handle MCU/core requests
	  if(!busy_int && !done_int) begin
		 // honour requests if SD card is idle
		 if(core_request == CORE_REQ_WRITE) begin
			$display("sd_card.v: Process pending core write request");
			core_request <= CORE_WRITING;

			lsector <= core_sector; // latch sector to be read
			wstart_int <= 1'b1;     // request sector to be written to sd card
		 end 

		 else if(core_request == CORE_REQ_READ) begin
			$display("sd_card.v: Process pending core read request");
			core_request <= CORE_READING;

			lsector <= core_sector; // latch sector to be read
			rstart_int <= 1'b1;     // request sector to be read from sd card			
		 end

		 else if(mcu_request == MCU_REQ_READ) begin
			$display("sd_card.v: Process pending MCU read request");
			mcu_request <= MCU_READING;
			
			lsector <= mcu_sector;  // latch sector to be read
			rstart_int <= 1'b1;     // request sector to be read from sd card
		 end

		 else if(mcu_request == MCU_READY2WRITE) begin
			$display("sd_card.v: Process pending MCU write request");
			mcu_request <= MCU_WRITING;
			
			lsector <= mcu_sector;  // latch sector to be written
			wstart_int <= 1'b1;     // request sector to be written to sd card
			mcu_tx_cnt <= 9'd0;
		 end
	  end

	  // a SD card transfer has ended, in case of a read, the MCU
	  // may now read the data
	  if(done_int) begin
		 // done from sd reader acknowledges/clears start
		 rstart_int <= 1'b0;
		 wstart_int <= 1'b0;

		 if(core_request == CORE_READING) begin
			$display("sd_card.v: Core SD read done");
			core_request <= CORE_REQ_IDLE;
		 end

		 else if(core_request == CORE_WRITING) begin
			$display("sd_card.v: Core SD write done");
			core_request <= CORE_REQ_IDLE;
		 end
			
		 else if(mcu_request == MCU_READING) begin
			$display("sd_card.v: MCU read done, waiting for MCU transfer");
			mcu_request <= MCU_READY2TRANSFER;
		 end
		 
		 else if(mcu_request == MCU_WRITING) begin
			$display("sd_card.v: MCU SD write done");
			mcu_request <= MCU_REQ_IDLE;
		 end
`ifndef YOSYS  // yosys does not like $error's
		 else
		   $error("sd_card.v: Error, spurious done_int");
`endif
	  end
	  
	  // buffer writing on MCU write is triggered via dinb_we
	  dinb_we <=1'b0;
	  if(mcu_request == MCU_REQ_WRITE) begin
		 if(dinb_we) begin
			if(mcu_tx_cnt < 9'd511)
			  mcu_tx_cnt <= mcu_tx_cnt + 9'd1;
			else begin
			   // buffer has been filled by MCU -> can start writing
			   mcu_request <= MCU_READY2WRITE;			   
			end
		 end
	  end

	  if(!data_strobe) begin
		 // If the core requests IO and direct access is enabled, then
		 // don't wait for the MCU. Instead the sector to be read from SD card
		 // is a direct offset of the requested sector relative from the
		 // start of the image on card.
		 if(start && direct_enable && core_request == CORE_REQ_IDLE) begin
			$display("sd_card.v: Direct request sector %0d", rsector);
			
			core_sector <= direct_start_rdata + rsector;
			if(rstart) core_request <= CORE_REQ_READ;
			if(wstart) core_request <= CORE_REQ_WRITE;
		 end
	  end // if (!data_strobe)
	  
      else begin // data_strobe active		 
         if(data_start) begin
			command <= data_in;
			// $display("sd_card.v: MCU start byte received: %0d", data_in);
			
			byte_cnt <= 4'd0;	    
			data_out <= { card_stat, card_type, 2'b0 };
		 end else begin
			// SDC CMD 1: STATUS
			if(command == 8'd1) begin
               // request status byte, for the MCU it doesn't matter whether
			   // the core wants to write or to read

			   // only forward request if direct_enable has not been enabled by MCU
			   if(byte_cnt == 4'd0) data_out <= direct_enable?8'h00:(rstart | wstart);
			   if(byte_cnt == 4'd1) data_out <= rsector[31:24];
			   if(byte_cnt == 4'd2) data_out <= rsector[23:16];
			   if(byte_cnt == 4'd3) data_out <= rsector[15: 8];
			   if(byte_cnt == 4'd4) begin
				  data_out <= rsector[ 7: 0];
				  $display("sd_card.v: MCU status request");
			   end  

               // this command can optionally send additional (debug) data
               if(byte_cnt == 4'd5) data_out <= { ~rsector[7], 7'd0 };   // indicate that more data is valid
               if(byte_cnt == 4'd6) data_out <= { 7'b0000000, |wstart};  // optional data to indicate writes
			end

			// SDC CMD 2: CORE_RW
			if(command == 8'd2) begin
               if(byte_cnt <= 4'd3) data_out <= 8'hff;
               else	                data_out <= 8'h00;
			   
               if(byte_cnt == 4'd0) core_sector[31:24] <= data_in;
               if(byte_cnt == 4'd1) core_sector[23:16] <= data_in;
               if(byte_cnt == 4'd2) core_sector[15: 8] <= data_in;
               if(byte_cnt == 4'd3) begin 
                  core_sector[ 7: 0] <= data_in;
				  $display("sd_card.v: Core request %0d/%0d sector %0d/%8x", rstart, wstart, {core_sector[31:8], data_in}, {core_sector[31:8], data_in});
				  
				  // distinguish between read and write
				  if(rstart) core_request <= CORE_REQ_READ;	  
				  if(wstart) core_request <= CORE_REQ_WRITE;
               end
			end
				 
			// SDC CMD 3: MCU_READ
			if(command == 8'd3) begin
			   // Store the entire MCU request separately and handle
			   // it once the SD card is idle
			   
               if(byte_cnt == 4'd0) mcu_sector[31:24] <= data_in;
               if(byte_cnt == 4'd1) mcu_sector[23:16] <= data_in;
               if(byte_cnt == 4'd2) mcu_sector[15: 8] <= data_in;
               if(byte_cnt == 4'd3) begin 
                  mcu_sector[ 7: 0] <= data_in;				  
				  $display("sd_card.v: MCU read request sector %0d/%8x", {mcu_sector[31:8], data_in}, {mcu_sector[31:8], data_in});  
				  mcu_request <= MCU_REQ_READ;	  
               end

			   // return data once in reading state
               if(byte_cnt <= 4'd3) 
				 data_out <= 8'hff;            // return 0xff during command transfer
			   else begin
				  if(mcu_request == MCU_READY2TRANSFER) begin
					 data_out <= 8'h00;		   // return 0x00 when data ready to be transferred/read by MCU
					 mcu_tx_cnt <= 9'd0;
					 mcu_request <= MCU_TRANSFERRING;
				  end else if(mcu_request == MCU_TRANSFERRING) begin
					 data_out <= doutb;					 
					 if(byte_cnt > 4'd4) begin
						mcu_tx_cnt <= mcu_tx_cnt + 9'd1;
						if(mcu_tx_cnt == 9'd511)
						  mcu_request <= MCU_REQ_IDLE;
					 end
				  end else
					data_out <= 8'h01;         // return 0x01 while waiting for data
			   end					
			end
			
			// SDC CMD 4: INSERTED
			if(command == 8'd4) begin
			   // MCU reports that some image has been inserted. If
			   // the image size is 0, then no image is inserted
			   // if(byte_cnt == 4'd0) image_target <= data_in;
			   // byte_cnt == 4'd1: bits 31:24 are ignored
			   if(byte_cnt == 4'd2) image_size[23:16] <= data_in;
			   if(byte_cnt == 4'd3) image_size[15:8]  <= data_in;
			   if(byte_cnt == 4'd4) begin 
				  image_size[7:0] <= data_in;
				  image_mounted <= 1'b1;
				  direct_start_wdata <= 32'b0;
				  direct_start_we <= 1'b1;
				  $display("sd_card.v: MCU inserted image with %0d bytes", { image_size[23:8], data_in } );
			   end
			end
			
			// SDC CMD 5: MCU WRITE
			if(command == 8'd5) begin
			   // MCU requests to write a sector
               if(byte_cnt == 4'd0) mcu_sector[31:24] <= data_in;
               if(byte_cnt == 4'd1) mcu_sector[23:16] <= data_in;
               if(byte_cnt == 4'd2) mcu_sector[15: 8] <= data_in;
               if(byte_cnt == 4'd3) begin 
                  mcu_sector[ 7: 0] <= data_in;
				  $display("sd_card.v: MCU write request sector %0d/%8x", {mcu_sector[31:8], data_in}, {mcu_sector[31:8], data_in});
				  mcu_request <= MCU_REQ_WRITE;				  
				  mcu_tx_cnt <= 9'd0;
               end
			   
			   // send "busy" while transfer is still in progress
			   data_out <= (mcu_request != MCU_REQ_IDLE)?8'h01:8'h00; 

			   // data transfer into local buffer
			   if(mcu_request == MCU_REQ_WRITE) begin
				  // Trigger write to buffer. Writing the buffer is now delayed by
				  // one cycle. Thus the address update is triggered by dinb_we
				  // above.
				  dinb_we <= 1'b1;
			   end 
			end
			
			// SDC CMD 6: ENABLE DIRECT ACCESS
			if(command == 8'd6) begin
			   // MCU reports that the core may access the image
			   // directy without sector translation
			   // if(byte_cnt == 4'd0) image_target <= data_in;
			   if(byte_cnt == 4'd1) direct_start_wdata[31:24] <= data_in;
			   if(byte_cnt == 4'd2) direct_start_wdata[23:16] <= data_in;
			   if(byte_cnt == 4'd3) direct_start_wdata[15: 8] <= data_in;
			   if(byte_cnt == 4'd4) begin
				   direct_start_wdata[ 7: 0] <= data_in;
				   direct_start_we <= 1'b1;
				   $display("sd_card.v: MCU direct start with offset %0d(%8x)", { direct_start_wdata[31:8], data_in }, { direct_start_wdata[31:8], data_in });
			   end
			end

			if(byte_cnt != 4'd15) byte_cnt <= byte_cnt + 4'd1;    
         end
      end // else: !if(!data_strobe)
   end
end
   
sd_rw #(.CLK_DIV(CLK_DIV), .SIMULATE(SIMULATE)) sd_rw (
   // rstn active-low, 1:working, 0:reset
   .rstn(rstn),
   .clk(clk),

   .sdclk(sdclk),
   .sdcmd(sdcmd),
   .sddat(sddat),
							       
   .card_stat(card_stat),
   .card_type(card_type),

   // lsector is the translated rsector into the file on the FAT fs
   .rstart( rstart_int ), 
   .wstart( wstart_int ), 
   .sector( lsector ),
   .rbusy( busy_int ),
   .rdone( done_int ),

   // data to be written to SD card either comes from local MCU buffer or from core
   .inbyte((core_request == CORE_WRITING)?inbyte:inbyte_int),
   .outen(louten),
   .outaddr(outaddr),
   .outbyte(outbyte)
);

endmodule // sd_card

`ifdef INFER_DPRAM
module sector_dpram #(parameter DATAWIDTH=8, ADDRWIDTH=8)
(
 input 						clock,

 input [ADDRWIDTH-1:0] 		address_a,
 input [DATAWIDTH-1:0] 		data_a,
 input 						wren_a,
 output reg [DATAWIDTH-1:0] q_a,

 input [ADDRWIDTH-1:0] 		address_b,
 input [DATAWIDTH-1:0] 		data_b,
 input 						wren_b,
 output reg [DATAWIDTH-1:0] q_b
);

reg [DATAWIDTH-1:0] ram[0:(1<<ADDRWIDTH)-1];

always @(posedge clock) begin
	if(wren_a) begin
		ram[address_a] <= data_a;
		q_a <= data_a;
	end else begin
		q_a <= ram[address_a];
	end
end

always @(posedge clock) begin
	if(wren_b) begin
		ram[address_b] <= data_b;
		q_b <= data_b;
	end else begin
		q_b <= ram[address_b];
	end
end
   
endmodule
`endif //  `ifdef INFER_DPRAM

// To match emacs with gw_ide default
// Local Variables:
// tab-width: 4
// End:
