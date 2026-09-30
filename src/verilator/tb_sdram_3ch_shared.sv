`timescale 1ns/1ps
// Sparse SDR SDRAM pin model: CL=2, one-word bursts, per-bank active rows.
// Only words used by this directed test are stored.
module test_sdram #(parameter ROW_BITS=13) (
    input clk, input [12:0] addr, input [1:0] ba, dqm,
    input cs_n, ras_n, cas_n, we_n, inout [15:0] dq
);
    reg [ROW_BITS-1:0] row [0:3];
    reg [23:0] addresses [0:63];
    reg [15:0] words [0:63];
    integer used=0;
    reg [2:0] read_valid=0;
    reg [15:0] rd0, rd1, rd2;
    wire [23:0] word_address = (24'(ba) << (ROW_BITS+9)) |
                               (24'(row[ba]) << 9) | 24'(addr[8:0]);
    function integer find(input [23:0] address);
        integer i;
        begin
            find=-1;
            for(i=0;i<used;i=i+1) if(addresses[i]==address) find=i;
        end
    endfunction
    task put(input [23:0] address, input [15:0] value);
        integer i;
        begin
            i=find(address);
            if(i<0) begin
                if(used==64) $fatal(1,"Sparse memory full");
                i=used; used=used+1; addresses[i]=address;
            end
            words[i]=value;
        end
    endtask
    function [15:0] get(input [23:0] address);
        integer i;
        begin
            i=find(address);
            if(i<0) $fatal(1,"Read from unexpected physical word %h",address);
            get=words[i];
        end
    endfunction
    integer slot;
    always @(posedge clk) begin
        read_valid <= {read_valid[1:0],1'b0};
        rd1 <= rd0; rd2 <= rd1;
        if(!cs_n) case({ras_n,cas_n,we_n})
            3'b011: row[ba] <= addr[ROW_BITS-1:0];
            3'b101: begin rd0 <= get(word_address); read_valid[0] <= 1; end
            3'b100: begin
                slot=find(word_address);
                if(slot<0) $fatal(1,"Write to unexpected physical word %h",word_address);
                if(!dqm[0]) words[slot][7:0]=dq[7:0];
                if(!dqm[1]) words[slot][15:8]=dq[15:8];
            end
            default: ;
        endcase
    end
    assign dq=read_valid[2] ? rd2 : 16'bz;
endmodule

module tb_sdram_3ch_shared;
    parameter DONE_DELAY=0;
    parameter ROM_DELAY=1;
`ifdef SDRAM_16M
    localparam ROW_BITS=12;
`else
    localparam ROW_BITS=13;
`endif
    localparam [23:0] BANK_WORDS=24'(1 << (ROW_BITS+9));
    function [23:0] bs_index(input [19:0] address);
        bs_index=BANK_WORDS + 24'(23'h300000>>1) + 24'(address>>1);
    endfunction
    function [23:0] ar_index(input [15:0] address);
        // A12 is unused on 16 MiB SDRAM, wrapping 0x780000 to 0x380000.
        ar_index=2*BANK_WORDS + (24'(23'h780000>>1) % BANK_WORDS) + 24'(address>>1);
    endfunction
    function [23:0] rom_index(input [22:0] address);
`ifdef SDRAM_16M
        rom_index=address[22]*BANK_WORDS + 24'(address[21:1]);
`else
        rom_index=24'(address>>1);
`endif
    endfunction
    function [23:0] wr_index(input [16:0] address);
`ifdef SDRAM_16M
        wr_index=BANK_WORDS + 24'(23'h1e0000>>1) + 24'(address>>1);
`else
        wr_index=24'(23'h7e0000>>1) + 24'(address>>1);
`endif
    endfunction
    reg clk=0;
    always #5 clk=~clk;
    wire mclk=clk;
    wire clkref=1'b0;
    reg resetn=0;
    tri [15:0] SDRAM_DQ;
    wire [12:0] SDRAM_A;
    wire [1:0] SDRAM_DQM, SDRAM_BA;
    wire SDRAM_nCS, SDRAM_nWE, SDRAM_nRAS, SDRAM_nCAS, SDRAM_CKE;
    reg [22:1] rom_addr=0;
    reg [15:0] rom_din=0;
    reg [1:0] rom_ds=3;
    reg rom_req=0,rom_we=0,rom_gsu=0;
    wire rom_req_ack,rom_done;
    wire [15:0] rom_dout;
    reg [16:0] wram_addr=0;
    reg [7:0] wram_din=0;
    reg wram_req=0,wram_we=0;
    wire wram_req_ack;
    wire [15:0] wram_dout;
    reg [19:0] bsram_addr=0;
    reg [15:0] bsram_din=0;
    reg [1:0] bsram_ds=3;
    reg bsram_req=0,bsram_we=0,bsram_gsu=1;
    wire [15:0] bsram_dout;
    wire bsram_req_ack,bsram_done;
    reg [15:0] aram_addr=0;
    reg [7:0] aram_din=0;
    reg aram_req=0,aram_we=0;
    wire aram_req_ack;
    wire [15:0] aram_dout;
    reg [14:0] vram1_addr=0,vram2_addr=0;
    reg [7:0] vram1_din=0,vram2_din=0;
    reg vram1_req=0,vram2_req=0,vram1_we=0,vram2_we=0;
    wire vram1_ack,vram2_ack;
    wire [7:0] vram1_dout,vram2_dout;
    reg vram_pending=0;
    reg [22:1] rv_addr=0;
    reg [15:0] rv_din=0;
    reg [1:0] rv_ds=3;
    reg rv_req=0,rv_we=0;
    wire rv_req_ack;
    wire [15:0] rv_dout;
    wire refreshing,ready;
    wire [23:0] total_refresh;
    sdram_snes_gsu #(.BSRAM_DONE_DELAY(DONE_DELAY),.ROM_DONE_DELAY(ROM_DELAY)) dut(.*);
    test_sdram #(.ROW_BITS(ROW_BITS)) chip(
        .clk(~clk), .addr(SDRAM_A), .ba(SDRAM_BA), .dqm(SDRAM_DQM),
        .cs_n(SDRAM_nCS), .ras_n(SDRAM_nRAS), .cas_n(SDRAM_nCAS),
        .we_n(SDRAM_nWE), .dq(SDRAM_DQ));

    integer bs_reads=0,bs_writes=0,normal_aram_writes=0,delayed_aram_writes=0,refreshes=0;
    reg [7:0] command_cycle;
    always @(posedge clk) command_cycle=dut.cycle;
    // Verify pin commands and done timing independently of transfer tasks.
    always @(negedge clk) begin
        #1;
        if(ready && !SDRAM_nCS) begin
            case({SDRAM_nRAS,SDRAM_nCAS,SDRAM_nWE})
            3'b001: refreshes=refreshes+1;
            3'b100: begin
                if(dut.port[0]==dut.PORT_BSRAM && SDRAM_BA==1) begin
                    if(command_cycle!==8'h04 || SDRAM_DQM!==~dut.ds[0])
                        $fatal(1,"BSRAM write slot/masks failed");
                    bs_writes=bs_writes+1;
                end
                if(SDRAM_BA==2) begin
                    if(command_cycle==8'h08) normal_aram_writes=normal_aram_writes+1;
                    else if(command_cycle==8'h40) delayed_aram_writes=delayed_aram_writes+1;
                    else $fatal(1,"ARAM write in wrong slot");
                    if(SDRAM_DQM!==~dut.ds[1]) $fatal(1,"ARAM byte masks failed");
                end
            end
            3'b101: if(dut.port[0]==dut.PORT_BSRAM && SDRAM_BA==1) begin
                if(command_cycle!==8'h04) $fatal(1,"BSRAM read in wrong slot");
                bs_reads=bs_reads+1;
            end
            default: ;
            endcase
        end
    end
    reg checked_rom_done=0,checked_bs_done=0;
    always @(negedge clk) begin
        #2;
        if(resetn && ready) begin
            if(rom_done!==checked_rom_done) begin
                if(dut.port[0]!==dut.PORT_ROM || !dut.oe_latch[0] ||
                   command_cycle!==(ROM_DELAY ? 8'h80 : 8'h20))
                    $fatal(1,"ROM done toggled for wrong port/cycle");
            end
            if(bsram_done!==checked_bs_done) begin
                if(dut.port[0]!==dut.PORT_BSRAM ||
                   command_cycle!==(dut.we_latch[0] ? 8'h04 : (DONE_DELAY ? 8'h80 : 8'h20)))
                    $fatal(1,"BSRAM done toggled for wrong port/cycle");
            end
        end
        checked_rom_done=rom_done; checked_bs_done=bsram_done;
    end
    task tick; @(posedge clk); #3; endtask
    task frame_start;
        begin
            @(negedge clk); #3;
            while(dut.cycle!==8'h01) begin @(negedge clk); #3; end
        end
    endtask
    task settle; repeat(16) tick(); endtask
    task bs_finish(input bit previous_done,input [15:0] result);
        integer n;
        begin
            n=0;
            while(bsram_done===previous_done && n<200) begin tick(); n=n+1; end
            if(bsram_done===previous_done || bsram_req_ack!==bsram_req)
                $fatal(1,"BSRAM completion/ack timeout");
            if(!bsram_we && bsram_dout!==result)
                $fatal(1,"BSRAM read got %h expected %h",bsram_dout,result);
        end
    endtask
    task rom_finish(input bit previous_done,input [15:0] result);
        integer n;
        begin
            n=0;
            while(rom_done===previous_done && n<400) begin tick(); n=n+1; end
            if(rom_done===previous_done || rom_req_ack!==rom_req || rom_dout!==result)
                $fatal(1,"ROM completion/ack/data failed: got %h expected %h",rom_dout,result);
        end
    endtask
    task bs_transfer(input bit wr,input [19:0] address,input [1:0] mask,
                     input [15:0] value,input [15:0] result);
        reg previous_done;
        begin
            frame_start(); previous_done=bsram_done;
            bsram_addr=address; bsram_we=wr; bsram_ds=mask;
            bsram_din=value; bsram_req=~bsram_req;
            bs_finish(previous_done,result);
            @(negedge clk); #3;
            if(wr && chip.get(bs_index(address))!==result) $fatal(1,"BSRAM physical write failed");
        end
    endtask
    task rom_transfer(input bit wr,input [22:0] address,input [1:0] mask,
                      input [15:0] value,input [15:0] result);
        reg previous_done;
        begin
            frame_start(); previous_done=rom_done;
            rom_addr=address>>1; rom_we=wr; rom_ds=mask; rom_din=value; rom_req=~rom_req;
            if(wr) begin
                settle();
                if(rom_req_ack!==rom_req || rom_done!==previous_done || chip.get(rom_index(address))!==result)
                    $fatal(1,"ROM loader write/ack/mask failed");
            end else rom_finish(previous_done,result);
        end
    endtask
    task wr_transfer(input bit wr,input [16:0] address,input [7:0] value,input [15:0] result);
        reg previous_done;
        begin
            frame_start(); previous_done=rom_done;
            wram_addr=address; wram_we=wr; wram_din=value; wram_req=~wram_req;
            settle();
            if(wram_req_ack!==wram_req || rom_done!==previous_done)
                $fatal(1,"WRAM ACK or isolated ROM done failed");
            if(wr ? chip.get(wr_index(address))!==result : wram_dout!==result)
                $fatal(1,"WRAM mapping/data/mask failed");
        end
    endtask
    reg previous_done,previous_rom_done,old_ack,old_rom_ack;
    integer n,before_refresh;
    initial begin
        chip.put(bs_index(20'h01234),16'h1234);
        chip.put(bs_index(20'h00000),16'hdead);
        chip.put(bs_index(20'hffffe),16'hbabe);
        chip.put(ar_index(16'h1234),16'h4321);
        chip.put(ar_index(16'hfffe),16'habcd);
        chip.put(rom_index(23'h2220),16'h2468);
        chip.put(rom_index(23'h4440),16'h1357);
        chip.put(rom_index(23'h400000),16'hface);
        chip.put(rom_index(23'h5dfffe),16'hbeef);
        chip.put(wr_index(17'h00000),16'h1234);
        chip.put(wr_index(17'h1fffe),16'h5678);
        chip.put(BANK_WORDS+24'(23'h200100>>1),16'h9876);
        repeat(4) tick();
        @(negedge clk); #3; resetn=1;
        n=0; while(!ready && n<200) begin tick(); n=n+1; end
        if(!ready) $fatal(1,"Initialization timeout");
        // GSU traffic starts after the first periodic refresh, as on the board
        // where loading the ROM precedes enabling the coprocessor.
        n=0; while(refreshes==0 && n<1000) begin tick(); n=n+1; end
        if(refreshes==0) $fatal(1,"Initial periodic refresh timeout");
        settle();
        $display("GSU SDRAM: bank=%0d MiB BSRAM delay=%0d ROM delay=%0d",1<<(ROW_BITS-10),DONE_DELAY,ROM_DELAY);
        bs_transfer(1,20'h01234,3,16'h5aa5,16'h5aa5);
        bs_transfer(1,20'h01234,2,16'hc300,16'hc3a5);
        bs_transfer(1,20'h01234,1,16'h0066,16'hc366);
        bs_transfer(0,20'h01234,3,0,16'hc366);
        bs_transfer(0,20'h00000,3,0,16'hdead);
        bs_transfer(0,20'hffffe,3,0,16'hbabe);
        rom_transfer(0,23'h400000,3,0,16'hface);
        rom_transfer(0,23'h5dfffe,3,0,16'hbeef);
        rom_transfer(1,23'h2220,2,16'hc300,16'hc368);
        rom_transfer(1,23'h2220,1,16'h0096,16'hc396);
        rom_transfer(0,23'h2220,3,0,16'hc396);
        wr_transfer(1,17'h00000,8'ha5,16'h12a5);
        wr_transfer(1,17'h00001,8'h5a,16'h5aa5);
        wr_transfer(0,17'h00000,0,16'h5aa5);
        wr_transfer(1,17'h1ffff,8'h69,16'h6978);
        wr_transfer(0,17'h1fffe,0,16'h6978);

        // All hosts can queue requests together. WRAM wins channel 0;
        // ARAM proceeds independently, then ROM, then BSRAM.
        frame_start(); previous_done=bsram_done; previous_rom_done=rom_done;
        old_ack=bsram_req_ack; old_rom_ack=rom_req_ack;
        wram_addr=0; wram_we=0; wram_req=~wram_req;
        rom_addr=23'h4440>>1; rom_we=0; rom_req=~rom_req;
        bsram_addr=20'h01234; bsram_we=0; bsram_req=~bsram_req;
        aram_addr=16'h1234; aram_we=0; aram_req=~aram_req;
        tick();
        if(dut.port[0]!==dut.PORT_WRAM) $fatal(1,"WRAM priority reservation failed");
        tick();
        if(dut.port[1]!==dut.PORT_ARAM) $fatal(1,"Independent ARAM reservation failed");
        repeat(5) tick();
        if(wram_req_ack!==wram_req || wram_dout!==16'h5aa5 || aram_req_ack!==aram_req || aram_dout!==16'h4321 ||
           rom_req_ack!==old_rom_ack || bsram_req_ack!==old_ack || rom_done!==previous_rom_done)
            $fatal(1,"WRAM/ARAM data or pending ROM/BSRAM request lost");
        rom_finish(previous_rom_done,16'h1357);
        if(bsram_req_ack!==old_ack) $fatal(1,"BSRAM overtook ROM");
        bs_finish(previous_done,16'hc366);

        // ARAM WRITE is delayed by a channel-0 ROM READ. A request arriving
        // after reservation must keep its own payload and wait for next frame.
        frame_start(); previous_rom_done=rom_done;
        rom_addr=23'h2220>>1; rom_req=~rom_req;
        aram_addr=16'h1234; aram_we=1; aram_din=8'h69; aram_req=~aram_req;
        tick();
        if(!dut.write_delay) $fatal(1,"ARAM delayed write not selected");
        repeat(3) tick();
        if(dut.port[1]!==dut.PORT_ARAM) $fatal(1,"ARAM delayed write not reserved");
        @(negedge clk); #3;
        previous_done=bsram_done; bsram_we=1; bsram_ds=3; bsram_din=16'ha55a; bsram_req=~bsram_req;
        rom_finish(previous_rom_done,16'hc396);
        bs_finish(previous_done,0); settle();
        if(aram_req_ack!==aram_req || chip.get(ar_index(16'h1234))!==16'h4369 ||
           chip.get(bs_index(20'h01234))!==16'ha55a)
            $fatal(1,"Delayed ARAM or late BSRAM write failed");
        frame_start(); aram_addr=16'h1235; aram_din=8'h96; aram_req=~aram_req;
        settle();
        if(aram_req_ack!==aram_req || chip.get(ar_index(16'h1234))!==16'h9669)
            $fatal(1,"ARAM high-byte normal write failed");
        aram_we=0;

        // Required refresh stalls GSU ROM and BSRAM, while ARAM still runs.
        frame_start(); before_refresh=refreshes;
        force dut.need_refresh=1'b1;
        tick();
        @(negedge clk); #3;
        previous_done=bsram_done; previous_rom_done=rom_done;
        old_ack=bsram_req_ack; old_rom_ack=rom_req_ack;
        bsram_we=0; bsram_req=~bsram_req;
        rom_gsu=1; rom_req=~rom_req;
        aram_req=~aram_req;
        repeat(24) begin
            tick();
            if(bsram_req_ack!==old_ack || bsram_done!==previous_done ||
               rom_req_ack!==old_rom_ack || rom_done!==previous_rom_done)
                $fatal(1,"GSU request bypassed refresh gate");
        end
        if(aram_req_ack!==aram_req || aram_dout!==16'h9669 || refreshes==before_refresh)
            $fatal(1,"Independent ARAM/refresh progress failed");
        release dut.need_refresh;
        rom_finish(previous_rom_done,16'hc396);
        bs_finish(previous_done,16'ha55a);

        // Sustained GSU ROM reads must yield to a pending RV request.
        frame_start(); rv_addr=22'h80; rv_req=~rv_req;
        previous_rom_done=rom_done; rom_req=~rom_req;
        n=0;
        while(rv_req_ack!==rv_req && n<600) begin
            tick(); n=n+1;
            if(rom_done!==previous_rom_done && rom_req_ack===rom_req) begin
                @(negedge clk); #3;
                previous_rom_done=rom_done; rom_req=~rom_req;
            end
        end
        if(rv_req_ack!==rv_req) $fatal(1,"GSU traffic starved RV");
        settle();
        if(rv_dout!==16'h9876) $fatal(1,"RV mapping/read data failed");
        if(bs_reads==0 || bs_writes==0 || normal_aram_writes==0 || delayed_aram_writes==0)
            $fatal(1,"Missing command schedule coverage");
        $display("PASS: ROM/WRAM arbitration, maps, masks, ARAM schedules, done timing, refresh and RV fairness");
        $finish;
    end
    initial begin #100000; $fatal(1,"SDRAM regression watchdog"); end
endmodule
