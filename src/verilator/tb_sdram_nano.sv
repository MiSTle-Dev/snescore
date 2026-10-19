`timescale 1ns/1ps

// Nano geometry: four banks, 2048 rows, 256 32-bit columns, CL2.
module nano_sdram_model (
    input clk, input [10:0] addr, input [1:0] ba, input [3:0] dqm,
    input cs_n, ras_n, cas_n, we_n, inout [31:0] dq
);
    reg [10:0] row [0:3];
    reg [20:0] addresses [0:63];
    reg [31:0] words [0:63];
    integer used=0;
    reg [2:0] read_valid=0;
    reg [31:0] rd0, rd1, rd2;
    wire [20:0] word_address={ba,row[ba],addr[7:0]};
    function integer find(input [20:0] address);
        integer i;
        begin
            find=-1;
            for(i=0;i<used;i=i+1) if(addresses[i]==address) find=i;
        end
    endfunction
    task put(input [20:0] address, input [31:0] value);
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
    function [31:0] get(input [20:0] address);
        integer i;
        begin
            i=find(address);
            if(i<0) $fatal(1,"Unexpected physical word %h",address);
            get=words[i];
        end
    endfunction
    integer slot,lane;
    always @(posedge clk) begin
        read_valid <= {read_valid[1:0],1'b0};
        rd1<=rd0; rd2<=rd1;
        if(!cs_n) case({ras_n,cas_n,we_n})
            3'b011: row[ba]<=addr;
            3'b101: begin rd0<=get(word_address); read_valid[0]<=1; end
            3'b100: begin
                slot=find(word_address);
                if(slot<0) $fatal(1,"Unexpected physical write %h",word_address);
                for(lane=0;lane<4;lane=lane+1)
                    if(!dqm[lane]) words[slot][lane*8+:8]=dq[lane*8+:8];
            end
            default: ;
        endcase
    end
    assign dq=read_valid[2] ? rd2 : 32'bz;
endmodule

module tb_sdram_nano;
    parameter ROM_DELAY=1, DONE_DELAY=0, CLOCK_PHASE=0;
    reg clk=0;
    always #5 clk=~clk;
    reg [1:0] divider=CLOCK_PHASE;
    always @(posedge clk) divider<=divider+1'b1;
    wire mclk=divider[1];
    reg resetn=0, clkref=0;
    reg [1:0] dot_count=0;
    always @(posedge mclk) begin
        dot_count<=dot_count+1'b1;
        clkref<=resetn && dot_count==2;
    end
    tri [31:0] SDRAM_DQ;
    wire [10:0] SDRAM_A;
    wire [3:0] SDRAM_DQM;
    wire [1:0] SDRAM_BA;
    wire SDRAM_nCS,SDRAM_nRAS,SDRAM_nCAS,SDRAM_nWE,SDRAM_CKE;
    // Must not inhibit Nano refresh: this shared-interface input is unused.
    wire vram_pending=1'b1;
    wire refreshing,ready;
    wire [23:0] total_refresh;
    reg [22:1] rom_addr=0;
    reg [15:0] rom_din=0;
    reg [1:0] rom_ds=3;
    reg rom_req=0,rom_we=0,rom_gsu=0;
    wire [15:0] rom_dout;
    wire rom_req_ack,rom_done;
    reg [16:0] wram_addr=0;
    reg [7:0] wram_din=0;
    reg wram_req=0,wram_we=0;
    wire [15:0] wram_dout;
    wire wram_req_ack;
    reg [19:0] bsram_addr=0;
    reg [15:0] bsram_din=0;
    reg [1:0] bsram_ds=3;
    reg bsram_req=0,bsram_we=0,bsram_gsu=0;
    wire [15:0] bsram_dout;
    wire bsram_req_ack,bsram_done;
    reg [15:0] aram_addr=0;
    reg [7:0] aram_din=0;
    reg aram_req=0,aram_we=0;
    wire [15:0] aram_dout;
    wire aram_req_ack;
    reg [14:0] vram1_addr=0,vram2_addr=0;
    reg [7:0] vram1_din=0,vram2_din=0;
    reg vram1_req=0,vram2_req=0,vram1_we=0,vram2_we=0;
    wire [7:0] vram1_dout,vram2_dout;
    wire vram1_ack,vram2_ack;
    reg [22:1] rv_addr=0;
    reg [15:0] rv_din=0;
    reg [1:0] rv_ds=3;
    reg rv_req=0,rv_we=0;
    wire [15:0] rv_dout;
    wire rv_req_ack;
    sdram_snes #(.ROM_DONE_DELAY(ROM_DELAY),.BSRAM_DONE_DELAY(DONE_DELAY)) dut(.*);
    nano_sdram_model chip(.clk(~clk),.addr(SDRAM_A),.ba(SDRAM_BA),.dqm(SDRAM_DQM),
        .cs_n(SDRAM_nCS),.ras_n(SDRAM_nRAS),.cas_n(SDRAM_nCAS),.we_n(SDRAM_nWE),.dq(SDRAM_DQ));

    integer fast_edge=0,last_refresh=-100,refreshes=0,activations=0;
    reg [7:0] command_cycle;
    always @(posedge clk) begin fast_edge=fast_edge+1; command_cycle=dut.cycle; end
    always @(negedge clk) begin
        #1;
        if(ready && !SDRAM_nCS) case({SDRAM_nRAS,SDRAM_nCAS,SDRAM_nWE})
            3'b001: begin
                if(command_cycle!==8'h04) $fatal(1,"Refresh outside cycle 2");
                last_refresh=fast_edge; refreshes=refreshes+1;
            end
            3'b011: begin
                if(fast_edge-last_refresh<6) $fatal(1,"ACTIVATE violates refresh recovery");
                activations=activations+1;
            end
            default: ;
        endcase
    end
    task tick; @(posedge clk); #2; endtask
    task settle; repeat(24) tick(); endtask
    task align_idle;
        integer n;
        begin
            n=0;
            while((dut.oe_latch || dut.we_latch || refreshing) && n<80) begin tick(); n=n+1; end
            if(n==80) $fatal(1,"Controller did not become idle");
            @(posedge clkref); tick();
            if(dut.cycle!==8'h08) $fatal(1,"Expected cycle-3 reference alignment, got %h",dut.cycle);
        end
    endtask
    task rom_transfer(input bit wr,input [22:0] address,input [1:0] mask,input [15:0] value,input [15:0] expected);
        reg old_done;
        integer n;
        begin
            @(negedge mclk); old_done=rom_done;
            rom_addr=address>>1;rom_ds=mask;rom_din=value;rom_we=wr;rom_req=~rom_req;
            n=0;
            while((rom_req_ack!==rom_req || (!wr && rom_done===old_done)) && n<100) begin tick();n=n+1;end
            if(n==100 || (!wr && rom_dout!==expected)) $fatal(1,"ROM transfer failed at %h",address);
            settle();
        end
    endtask
    task bs_transfer(input bit wr,input [19:0] address,input [1:0] mask,input [15:0] value,input [15:0] expected);
        reg old_done;
        integer n;
        begin
            @(negedge mclk);old_done=bsram_done;
            bsram_addr=address;bsram_ds=mask;bsram_din=value;bsram_we=wr;bsram_req=~bsram_req;
            n=0;while(bsram_done===old_done && n<100) begin tick();n=n+1;end
            if(n==100 || bsram_req_ack!==bsram_req || (!wr && bsram_dout!==expected))
                $fatal(1,"BSRAM transfer failed at %h",address);
            settle();
        end
    endtask
    // Inject a real registered request on the mclk edge immediately preceding
    // cycle-2 refresh selection. Cycle-4 alignment incorrectly samples the old
    // toggle on that same edge; the restored cycle-3 alignment sees the new one.
    task refresh_boundary(input [1:0] ports);
        integer before_refresh,n;
        begin
            align_idle();before_refresh=refreshes;
            @(posedge mclk);
            force dut.do_refresh=1'b1;
            @(posedge mclk);
            if(ports[0]) vram1_req<=~vram1_req;
            if(ports[1]) vram2_req<=~vram2_req;
            repeat(2) tick();
            if(refreshes!=before_refresh) $fatal(1,"Refresh overtook newly registered VRAM request");
            release dut.do_refresh;
            n=0;
            while(((ports[0] && vram1_ack!==vram1_req) || (ports[1] && vram2_ack!==vram2_req)) && n<80)
                begin tick();n=n+1;end
            if(n==80) $fatal(1,"VRAM request lost at refresh boundary");
            repeat(4) tick();
            if((ports[0] && vram1_dout!==8'h34) || (ports[1] && vram2_dout!==8'h12))
                $fatal(1,"VRAM read data late or wrong after refresh boundary");
            settle();
        end
    endtask
    integer n,old_count;
    initial begin
        chip.put(21'h000040,0); // ROM 0x100, both halfwords
        chip.put(21'h0f0000,0); // BSRAM 0x3c0000
        chip.put(21'h0f8000,0); // WRAM 0x3e0000
        chip.put(21'h100000,32'h87654321); // ARAM 0x400000
        chip.put(21'h140000,32'h76544321); // RV 0x500000
        chip.put(21'h1fc000,32'habcd1234); // VRAM 0x7f0000
        repeat(4) tick();resetn=1;
        n=0;while(!ready && n<100) begin tick();n=n+1;end
        if(!ready) $fatal(1,"Initialization timeout");
        align_idle();
        rom_transfer(1,23'h000100,3,16'ha55a,0);
        rom_transfer(1,23'h000102,3,16'hc33c,0);
        rom_transfer(0,23'h400100,3,0,16'ha55a); // 4 MiB mirror
        rom_transfer(0,23'h000102,3,0,16'hc33c);
        if(chip.get(21'h40)!==32'hc33ca55a) $fatal(1,"ROM halfword lanes failed");
        bs_transfer(1,0,3,16'h5aa5,0);
        bs_transfer(1,2,1,16'h0069,0);
        bs_transfer(0,20'h20000,3,0,16'h5aa5); // 128 KiB mirror
        bs_transfer(0,2,3,0,16'h0069);
        if(chip.get(21'hf0000)!==32'h00695aa5) $fatal(1,"BSRAM mapping/masks failed");
        @(negedge mclk);wram_we=1;wram_addr=3;wram_din=8'h96;wram_req=~wram_req;
        settle();
        if(wram_req_ack!==wram_req || chip.get(21'hf8000)!==32'h96000000) $fatal(1,"WRAM high byte failed");
        @(negedge mclk);wram_we=0;wram_addr=2;wram_req=~wram_req;
        settle();if(wram_dout!==16'h9600) $fatal(1,"WRAM read failed");
        @(negedge mclk);aram_req=~aram_req;rv_req=~rv_req;
        settle();
        if(aram_req_ack!==aram_req || aram_dout!==16'h4321 || rv_req_ack!==rv_req || rv_dout!==16'h4321)
            $fatal(1,"ARAM/RV arbitration or read failed");
        refresh_boundary(1);refresh_boundary(2);refresh_boundary(3);
        // Writes through both VRAM ports must preserve the untouched halfword.
        @(negedge mclk);vram1_we=1;vram2_we=1;vram1_addr=1;vram2_addr=1;
        vram1_din=8'h5a;vram2_din=8'ha5;vram1_req=~vram1_req;vram2_req=~vram2_req;
        settle();if(chip.get(21'h1fc000)!==32'ha55a1234) $fatal(1,"VRAM write masks failed");
        // Busy transfers must not be abandoned by an arriving reference edge.
        @(negedge mclk);rom_we=0;rom_addr=22'h80;rom_req=~rom_req;
        n=0;while(!dut.oe_latch[0] && n<80) begin tick();n=n+1;end
        if(n==80) $fatal(1,"ROM request not reserved");
        @(negedge clk);force dut.clkref=1;force dut.clkref_r=0;
        begin: busy_sync_check
            reg [7:0] expected_cycle;
            expected_cycle={dut.cycle[6:0],dut.cycle[7]};tick();
            if(dut.cycle!==expected_cycle) $fatal(1,"Busy reference edge changed the schedule");
        end
        release dut.clkref;release dut.clkref_r;settle();
        old_count=refreshes;n=0;
        while(refreshes==old_count && n<800) begin tick();n=n+1;end
        if(n==800 || activations==0) $fatal(1,"Refresh did not make progress");
        // Reset must discard reservations and reestablish the reference phase.
        resetn=0;repeat(4) tick();
        rom_req=0;wram_req=0;bsram_req=0;aram_req=0;rv_req=0;vram1_req=0;vram2_req=0;
        resetn=1;repeat(30) tick();align_idle();
        $display("PASS: Nano phase=%0d ROM delay=%0d BSRAM delay=%0d: maps, masks, data, refresh boundary/recovery, busy alignment, reset",CLOCK_PHASE,ROM_DELAY,DONE_DELAY);
        $finish;
    end
    initial begin #200000; $fatal(1,"Nano SDRAM watchdog");end
endmodule
