module smc_parser(
    input	      clk,
    input	      resetn,

    input [7:0]	      rom_d,	// feed in snes header and 32 bytes after header
    input	      rom_strb,

    // ROM meta-data output
    output reg [7:0]  rom_type,	// map_ctrl after further detection like DSP
    output reg [23:0] rom_mask,
    output reg [23:0] ram_mask,
    output reg [3:0]  rom_size,
    output reg [3:0]  ram_size,

    output reg	      header_finished
`ifdef MISTLE		  
    , output reg      header_ok
`endif
);

// 64-byte rom header parsing. The following values are useful:
// [$15]: map_ctrl
// [$16]: rom_type_header
// [$17]: rom_size
// [$18]: ram_size
// [$1A]: company_header
// [$3C-$3D]: reset vector (not currently used)
reg [5:0] cnt;
reg [7:0] mapper_header;            // raw map_ctrl from the ROM
reg [7:0] company_header;
reg [7:0] rom_type_header;
reg [1:0] rom_header_old;

always @(posedge clk) begin
    if (~resetn) begin
        cnt <= 0;
        header_finished <= 0;
`ifdef MISTLE		  
        header_ok <= 1'b1;
`endif
    end else if (rom_strb && ~header_finished) begin
        cnt <= cnt + 1;

`ifdef MISTLE
       if(cnt == 0)
	 header_ok <= 1'b1;
       
       // bytes 0 .. 20 are the ASCII cartridge name
       // each character mus be zero or in ASCII range. First char must not be zero
       if(cnt <= 6'd20 && (!cnt || rom_d) && (rom_d < 8'd32 || rom_d > 8'd127 ))
	 header_ok <= 1'b0;       	 

`endif
       
        case (cnt)
          6'h00: $display("smc_parser.v: start");
	  
          6'h15: begin 
	     mapper_header <= rom_d;
             $display("smc_parser.v: mapper=%0d", rom_d);
	  end
	  
          6'h16: begin
	     rom_type_header <= rom_d;
             $display("smc_parser.v: rom type=%0d", rom_d);
	  end

          6'h17: begin
	     rom_size <= rom_d[3:0];
             $display("smc_parser.v: rom size=%0d", 1024<<rom_d[3:0]);

`ifdef MISTLE
	     // max rom size = 1024 * 2^15 = 32MB
	     // actually biggest commercial cartridge is 6MB
	     if(rom_d[7:4]) header_ok <= 1'b0;	     
`endif
	  end
	  
          6'h18: begin
	     ram_size <= rom_d[3:0];
             $display("smc_parser.v: ram size=%0d", 1024<<rom_d[3:0]);

`ifdef MISTLE
	     // max ram size is 128k
	     if(rom_d[7:3]) header_ok <= 1'b0;	     
`endif
	  end
	     
          6'h19: begin
             $display("smc_parser.v: country=%0d", rom_d);
`ifdef MISTLE
	     // max country code is $14
	     if(rom_d > 8'h14) header_ok <= 1'b0;	     
`endif
	  end

          6'h1A: begin
	     company_header <= rom_d;
             $display("smc_parser.v: company=%0d", rom_d);
	  end
	  
          6'h3F:
`ifdef MISTLE
	    // the companion may try different headers. So reset the parser if
	    // a header wasn't valid. Also don't signal "finished" on failure	    
	    if(!header_ok) begin
               cnt <= 0;
               header_finished <= 0;
	    end else
`endif
	    begin
             header_finished <= 1;
             rom_mask <= (24'd1024 << ((rom_size < 4'd7) ? 4'hC : rom_size)) - 1'd1;
             ram_mask <= ram_size != 0 ? (24'd1024 << ram_size) - 1'd1 : 24'd0;
          end
          default: ;
        endcase
    end

    // further processing of headers into rom_type
    if (cnt == 6'h20) begin        
        // inital rom_type value
        rom_type <= {6'b0, mapper_header[1:0]};
        //DSP3
        if (mapper_header == 8'h30 && rom_type_header == 8'd5 && company_header == 8'hB2) 
            rom_type[7:4] <= 4'hA;
        //DSP1
        else if (((mapper_header == 8'h20 || mapper_header == 8'h21) && rom_type_header == 8'd3) ||
                (mapper_header == 8'h30 && rom_type_header == 8'd5) || 
                (mapper_header == 8'h31 && (rom_type_header == 8'd3 || rom_type_header == 8'd5))) 
            rom_type[7] <= 1'b1;
        //DSP2
        else if (mapper_header == 8'h20 && rom_type_header == 8'd5) 
            rom_type[7:4] <= 4'h9;
        //DSP4
        else if (mapper_header == 8'h30 && rom_type_header == 8'd3) 
            rom_type[7:4] <= 4'hB;
        //OBC1
        else if (mapper_header == 8'h30 && rom_type_header == 8'h25) 
            rom_type[7:4] <= 4'hC;
        //SDD1
        else if (mapper_header == 8'h32 && (rom_type_header == 8'h43 || rom_type_header == 8'h45)) 
            rom_type[7:4] <= 4'h5;
        //ST0XX
        else if (mapper_header == 8'h30 && rom_type_header == 8'hf6) begin
            rom_type[7:3] <= { 4'h8, 1'b1 };
            if (rom_size < 4'd10) rom_type[5] <= 1'b1; // Hayazashi Nidan Morita Shougi
        end
        //GSU
        else if (mapper_header == 8'h20 &&
            (rom_type_header == 8'h13 || rom_type_header == 8'h14 || rom_type_header == 8'h15 || rom_type_header == 8'h1a))
        begin
            rom_type[7:4] <= 4'h7;
            ram_mask <= (24'd1024 << 4'd6) - 1'd1;
        end
        //SA1
        else if (mapper_header == 8'h23 && (rom_type_header == 8'h32 || rom_type_header == 8'h34 || rom_type_header == 8'h35)) begin
            rom_type[7:4] <= 4'h6;
        // SPC7110
        end else if (mapper_header == 8'h3a && (rom_type_header == 8'hf5 || rom_type_header == 8'hf9)) begin
            rom_type[7:4] <= 4'hD;
            rom_type[3] <= rom_type_header[3]; // with RTC
        //CX4
        end else if (mapper_header == 8'h20 && rom_type_header == 8'hf3) begin
            rom_type[7:4] <= 4'h4;
        end
    end
end


endmodule
