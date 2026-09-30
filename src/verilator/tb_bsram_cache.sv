`timescale 1ns/1ps
module tb_bsram_cache;
    reg clk = 0;
    always #5 clk = ~clk;
    reg resetn = 0;
    reg [19:0] front_addr = 0;
    reg [7:0] front_din = 0;
    reg front_we = 0, front_req = 0, front_inhibit = 0;
    wire front_ack, front_done, busy;
    wire [7:0] front_dout;
    wire [19:0] sd_addr;
    wire [15:0] sd_din, sd_dout;
    wire [1:0] sd_ds;
    wire sd_we, sd_req, sd_ack, sd_done;
    wire [3:0] dbg_state;
    integer ack_delay = 0, done_delay = 0;
    reg early_data = 0, initial_ack = 0, initial_done = 0;

    bsram_cache dut (.*);
    bsram_sdram_model controller (
        .clk(clk), .resetn(resetn), .addr(sd_addr), .din(sd_din),
        .ds(sd_ds), .we(sd_we), .req(sd_req), .ack(sd_ack),
        .done(sd_done), .dout(sd_dout), .ack_delay(ack_delay),
        .done_delay(done_delay), .early_data(early_data),
        .initial_ack(initial_ack), .initial_done(initial_done)
    );

    // Discover geometry only; transaction/data prediction remains independent.
    localparam MAX_CACHE_WORDS = 16384;
    localparam MAX_TRANSFERS = 262144;
    integer cache_words, cache_sets, cache_bytes, index_bits, tag_count;
    reg lru [0:MAX_CACHE_WORDS/2-1];

    // Architectural memory and independent two-way LRU policy predictor.
    // No DUT internals are used to predict data or SDRAM transactions.
    reg [7:0] golden [0:1048575];
    integer tags [0:MAX_CACHE_WORDS-1];
    reg [1:0] valid_bytes [0:MAX_CACHE_WORDS-1], dirty_bytes [0:MAX_CACHE_WORDS-1];
    reg [19:0] expected_addr [0:MAX_TRANSFERS-1];
    reg [15:0] expected_data [0:MAX_TRANSFERS-1];
    reg [1:0] expected_ds [0:MAX_TRANSFERS-1];
    reg expected_we [0:MAX_TRANSFERS-1];
    reg expected_deferred [0:MAX_TRANSFERS-1];
    integer head = 0, tail = 0;
    integer operations = 0, reads = 0, writes = 0;
    integer mask_count [0:3];
    reg [11:0] states_seen = 0;
    reg [3:0] previous_state = 0;
    reg last_sd_req = 0;
    reg last_front_ack = 0, last_front_done = 0;
    reg last_sd_ack = 0, last_sd_done = 0;
    reg front_inflight = 0, sd_inflight = 0, sd_accepted = 0;
    reg sd_inflight_we = 0, front_was_write = 0;
    integer simultaneous_completions = 0, separate_completions = 0;
    integer sd_phase_count [0:1];
    integer deferred_mask_count [0:3];
    integer deferred_write_mask_count [0:3];
    integer responses_during_write = 0, guarded_sdram_cycles = 0;
    integer inhibited_read_masks [0:3];
    integer inhibited_write_masks [0:3];
    integer lookup_fills = 0;
    integer seed = 1, rng, random_ops = 4000;
    integer i, j, index, tag_number, value;
    reg [19:0] random_addr;
    reg [7:0] expected_byte;
    reg before_reset_read_done;
    integer reset_cycles;

    task tick;
        @(posedge clk); #2;
    endtask

    task enqueue(input bit wr, input [19:0] address,
                 input [1:0] mask, input [15:0] data_value, input bit deferred = 0);
        if (tail == MAX_TRANSFERS) $fatal(1, "Expected transaction queue overflow");
        expected_we[tail] = wr;
        expected_addr[tail] = address;
        expected_ds[tail] = mask;
        expected_data[tail] = data_value;
        expected_deferred[tail] = deferred;
        tail = tail + 1;
    endtask

    task predict(input bit wr, input [19:0] address,
                 input [7:0] data_value, output reg [7:0] result, input bit inhibit = 0);
        integer slot, set_index, new_tag, victim, way;
        reg [1:0] mask;
        reg [1:0] victim_dirty;
        reg [15:0] victim_data;
        reg tag_hit;
        begin
            set_index = (int'(address) >> 1) % cache_sets;
            new_tag = int'(address) / cache_bytes;
            if (valid_bytes[2*set_index] != 0 && tags[2*set_index] == new_tag)
                way = 0;
            else if (valid_bytes[2*set_index+1] != 0 && tags[2*set_index+1] == new_tag)
                way = 1;
            else if (valid_bytes[2*set_index] == 0) way = 0;
            else if (valid_bytes[2*set_index+1] == 0) way = 1;
            else way = int'(lru[set_index]);
            slot = 2*set_index + way;
            tag_hit = valid_bytes[slot] != 0 && tags[slot] == new_tag;
            mask = address[0] ? 2'b10 : 2'b01;
            victim_dirty = 0;
            victim = 0;
            victim_data = 0;
            // Inhibited read conflicts fetch the requested word without
            // replacing a dirty resident word or writing its bytes back.
            if (!wr && inhibit && !tag_hit && dirty_bytes[slot] != 0) begin
                enqueue(0, {address[19:1], 1'b0}, 2'b11, 0);
                result = golden[address];
                inhibited_read_masks[dirty_bytes[slot]] = inhibited_read_masks[dirty_bytes[slot]] + 1;
            end else begin
                lru[set_index] = !way;
                if (!tag_hit) begin
                    if (dirty_bytes[slot] != 0) begin
                        victim = tags[slot] * cache_bytes + set_index * 2;
                        victim_dirty = dirty_bytes[slot];
                        victim_data = {golden[victim+1], golden[victim]};
                    end
                    tags[slot] = new_tag;
                    valid_bytes[slot] = 0;
                    dirty_bytes[slot] = 0;
                end
                if (wr) begin
                    golden[address] = data_value;
                    valid_bytes[slot] = valid_bytes[slot] | mask;
                    dirty_bytes[slot] = dirty_bytes[slot] | mask;
                    result = data_value;
                end else begin
                    if ((valid_bytes[slot] & mask) == 0) begin
                        enqueue(0, {address[19:1], 1'b0}, 2'b11, 0);
                        valid_bytes[slot] = 2'b11;
                    end
                    result = golden[address];
                end
                if (victim_dirty != 0) begin
                    enqueue(1, 20'(victim), victim_dirty, victim_data, 1);
                    if (wr && inhibit)
                        inhibited_write_masks[victim_dirty] = inhibited_write_masks[victim_dirty] + 1;
                end
            end
        end
    endtask

    // Compare every issued transfer, including ordering, byte masks and victim tag.
    always @(posedge clk) begin
        #1;
        if (!resetn) begin
            last_sd_req = sd_req;
            last_sd_ack = sd_ack; last_sd_done = sd_done;
            last_front_ack = front_ack; last_front_done = front_done;
            front_inflight = 0; sd_inflight = 0; sd_accepted = 0;
            previous_state = dbg_state;
        end
        else begin
            if (dbg_state > 11) $fatal(1, "Illegal state %0d", dbg_state);
            states_seen[dbg_state] = 1;
            if (sd_inflight && sd_inflight_we && (dbg_state == 3 || dbg_state == 2))
                guarded_sdram_cycles = guarded_sdram_cycles + 1;
            if (busy !== ((dbg_state != 1) || (front_req != front_ack)))
                $fatal(1, "Incorrect busy output");
            if (sd_req !== last_sd_req) begin
                if (sd_inflight || sd_ack !== last_sd_req)
                    $fatal(1, "SDRAM request issued before previous ack/done");
                sd_inflight = 1;
                sd_inflight_we = sd_we;
                sd_accepted = 0;
                sd_phase_count[sd_req] = sd_phase_count[sd_req] + 1;
                if (head == tail) $fatal(1, "Unexpected SDRAM transaction at %h", sd_addr);
                if (expected_deferred[head] && front_inflight)
                    $fatal(1, "Eviction writeback issued before front_done");
                if ({sd_we, sd_addr, sd_ds} !==
                    {expected_we[head], expected_addr[head], expected_ds[head]})
                    $fatal(1, "Transfer %0d got we/addr/ds=%b/%h/%b expected %b/%h/%b",
                           head, sd_we, sd_addr, sd_ds, expected_we[head],
                           expected_addr[head], expected_ds[head]);
                if (sd_we) begin
                    if ((sd_ds[0] && sd_din[7:0] !== expected_data[head][7:0]) ||
                        (sd_ds[1] && sd_din[15:8] !== expected_data[head][15:8]))
                        $fatal(1, "Incorrect writeback data: got %h expected %h mask %b",
                               sd_din, expected_data[head], sd_ds);
                    writes = writes + 1;
                    mask_count[sd_ds] = mask_count[sd_ds] + 1;
                end else begin
                    if (previous_state !== 4'd2 || dbg_state !== 4'd6)
                        $fatal(1, "Read miss must launch from LOOKUP directly into WAIT_FILL");
                    lookup_fills = lookup_fills + 1;
                    reads = reads + 1;
                end
                head = head + 1;
                last_sd_req = sd_req;
            end
            if (sd_ack !== last_sd_ack) begin
                if (!sd_inflight || sd_accepted || sd_ack !== sd_req)
                    $fatal(1, "Unsolicited or duplicate SDRAM ack");
                sd_accepted = 1;
            end
            if (sd_done !== last_sd_done) begin
                if (!sd_inflight || !sd_accepted)
                    $fatal(1, "SDRAM done without accepted request");
                if (sd_ack !== last_sd_ack) simultaneous_completions = simultaneous_completions + 1;
                else separate_completions = separate_completions + 1;
                sd_inflight = 0;
            end
            if (front_ack !== last_front_ack) begin
//                if (dbg_state !== 4'd2 || previous_state !== 4'd1)
//                    $fatal(1, "Accepted request must enter LOOKUP from IDLE");
                if (front_inflight || front_ack !== front_req)
                    $fatal(1, "Front accepted a second request before completion");
                front_inflight = 1;
                front_was_write = front_we;
                if (front_done !== last_front_done)
                    $fatal(1, "Front ack and done occurred on the same cycle");
            end
            if (front_done !== last_front_done) begin
                if (!front_inflight || (sd_inflight && !sd_inflight_we))
                    $fatal(1, "Front done without acceptance or before read fill completion");
                if (sd_inflight && sd_inflight_we)
                    responses_during_write = responses_during_write + 1;
                if (head != tail) begin
                    if (tail-head != 1 || !expected_deferred[head] || !busy)
                        $fatal(1, "Only deferred victim writeback may remain at front_done");
                    if (front_was_write)
                        deferred_write_mask_count[expected_ds[head]] = deferred_write_mask_count[expected_ds[head]] + 1;
                    else
                        deferred_mask_count[expected_ds[head]] = deferred_mask_count[expected_ds[head]] + 1;
                end
                front_inflight = 0;
            end
            last_sd_ack = sd_ack; last_sd_done = sd_done;
            last_front_ack = front_ack; last_front_done = front_done;
            previous_state = dbg_state;
        end
    end

    task wait_complete(input bit previous_done, input [7:0] result);
        integer cycles;
        begin
            cycles = 0;
            while (front_done === previous_done && cycles < 200) begin
                tick();
                cycles = cycles + 1;
            end
            if (front_done === previous_done) $fatal(1, "Front completion timeout state=%0d", dbg_state);
            if (front_dout !== result)
                $fatal(1, "Front data got %h expected %h, operation %0d", front_dout, result, operations);
            if (controller.active && !controller.saved_we)
                $fatal(1, "Front completed before read fill done");
            cycles = 0;
            while ((busy || sd_inflight || controller.active || sd_req != sd_ack) && cycles < 200) begin
                tick();
                cycles = cycles + 1;
                if (front_done !== ~previous_done || front_dout !== result)
                    $fatal(1, "Front response changed during deferred writeback");
            end
            if (busy || sd_inflight || controller.active || sd_req != sd_ack)
                $fatal(1, "Deferred writeback drain timeout");
            if (head != tail || controller.active)
                $fatal(1, "Cache became idle before expected SDRAM transfers finished");
            operations = operations + 1;
        end
    endtask

    task transact(input bit wr, input [19:0] address, input [7:0] data_value, input bit inhibit = 0);
        reg [7:0] result;
        reg previous_done, requested_phase;
        integer cycles;
        begin
            if (busy) $fatal(1, "Driver issued ordinary request while busy");
            predict(wr, address, data_value, result, inhibit);
            previous_done = front_done;
            @(negedge clk); #1;
            front_addr = address;
            front_we = wr;
            front_din = data_value;
            front_inhibit = inhibit;
            front_req = ~front_req;
            requested_phase = front_req;
            #1; // allow continuous busy assignment to settle
            cycles = 0;
            while (front_ack !== requested_phase && cycles < 5) begin
                tick();
                cycles = cycles + 1;
            end
            if (front_ack !== requested_phase) $fatal(1, "Front acceptance timeout");
            if (front_done !== previous_done) $fatal(1, "done changed at acceptance");
            if (wr && front_dout !== data_value)
                $fatal(1, "Write must output accepted byte at ack");
            if (!busy) $fatal(1, "busy dropped at acceptance");
            // Inputs may change immediately after ack; accepted payload must be latched.
            @(negedge clk); #1;
            front_addr = ~address;
            front_din = ~data_value;
            front_we = ~wr;
            front_inhibit = ~inhibit;
            wait_complete(previous_done, result);
            if (front_ack !== requested_phase || busy)
                $fatal(1, "Incorrect ack/busy after completion");
        end
    endtask

    task idle_check;
        reg saved_ack, saved_done, saved_req;
        begin
            saved_ack = front_ack; saved_done = front_done; saved_req = sd_req;
            repeat (8) begin
                tick();
                if (busy || front_ack !== saved_ack || front_done !== saved_done || sd_req !== saved_req)
                    $fatal(1, "Idle request replay or unexpected handshake transition");
            end
        end
    endtask

    task reset_cache(input bit ack_phase, input bit done_phase, input bit queued);
        integer slot, word_index;
        begin
            @(negedge clk); #1;
            resetn = 0;
            initial_ack = ack_phase;
            initial_done = done_phase;
            front_req = 0; front_inhibit = 0;
            repeat (3) tick();
            if ({front_ack, front_done, front_dout} !== 10'b0 || sd_req !== ack_phase)
                $fatal(1, "Incorrect reset output/SDRAM phase synchronization");
            // Reset invalidates dirty cache state without flushing it.
            for (word_index = 0; word_index < 524288; word_index = word_index + 1) begin
                golden[2*word_index] = controller.mem[word_index][7:0];
                golden[2*word_index+1] = controller.mem[word_index][15:8];
            end
            for (slot = 0; slot < cache_words; slot = slot + 1) begin
                tags[slot] = 0; valid_bytes[slot] = 0; dirty_bytes[slot] = 0;
            end
            for (slot = 0; slot < cache_sets; slot = slot + 1) lru[slot] = 0;
            head = 0; tail = 0;
            @(negedge clk); #1; resetn = 1;
            if (queued) begin
                predict(0, 20'hff801, 0, expected_byte);
                front_addr = 20'hff801; front_we = 0; front_req = 1;
            end
            // One clear clock per cache word, then PRIME, then IDLE.
            repeat (cache_sets) begin
                tick();
                if (!busy || front_ack !== 0 || front_done !== 0 || sd_req !== ack_phase)
                    $fatal(1, "Cache accepted/completed a request during metadata clear");
            end
            tick();
            if (dbg_state !== 4'd1) $fatal(1, "Cache did not leave PRIME after clear");
            if (queued) begin
                tick();
                if (front_ack !== 1) $fatal(1, "Request held during reset was lost");
                wait_complete(0, expected_byte);
            end else if (busy) $fatal(1, "Cache not idle after clear");
        end
    endtask

    // Returns at front_done so the next access can overlap an accepted write.
    task rapid_request(input bit wr, input [19:0] address, input [7:0] value);
        reg [7:0] result;
        reg old_done, phase;
        integer cycles;
        begin
            cycles = 0;
            while (busy && cycles < 200) begin tick(); cycles++; end
            if (busy) $fatal(1, "Rapid request acceptance timeout");
            predict(wr, address, value, result);
            old_done = front_done;
            @(negedge clk); #1;
            front_addr = address; front_we = wr; front_din = value; front_inhibit = 0;
            front_req = ~front_req; phase = front_req;
            cycles = 0;
            while (front_done === old_done && cycles < 8) begin tick(); cycles++; end
            if (front_done === old_done || front_ack !== phase || front_dout !== result)
                $fatal(1, "Hit/allocation stalled behind outstanding write");
            operations++;
        end
    endtask

    task queued_pair;
        reg [7:0] first_result, second_result;
        reg first_done, first_phase, second_phase;
        begin
            $display("Queued request while first request waits for SDRAM");
            ack_delay = 12; done_delay = 20;
            predict(0, 20'habc12, 0, first_result);
            first_done = front_done;
            @(negedge clk); #1;
            front_addr = 20'habc12; front_we = 0; front_inhibit = 0; front_req = ~front_req;
            first_phase = front_req;
            tick(); tick();
            if (front_ack !== first_phase) $fatal(1, "First queued request not accepted");
            @(negedge clk); #1;
            front_addr = 20'hfedc3; front_din = 8'hc7; front_we = 1;
            front_req = ~front_req; second_phase = front_req;
            while (front_done === first_done) begin
                tick();
                if (front_ack !== first_phase) $fatal(1, "Second request accepted before first completed");
            end
            if (front_dout !== first_result || !busy) $fatal(1, "First queued response incorrect");
            operations = operations + 1;
            predict(1, 20'hfedc3, 8'hc7, second_result);
            tick(); tick();
            if (front_ack !== second_phase) $fatal(1, "Second queued request lost");
            wait_complete(~first_done, second_result);
            transact(0, 20'hfedc3, 0);
        end
    endtask

    task replacement_cases;
        reg [19:0] a, b, c, d;
        integer before_reads, before_writes, m;
        begin
            $display("Invalid ways first; hits update exact LRU; dirty victims from both ways");
            reset_cache(0, 0, 0);
            a = 20'h120; b = a + 20'(cache_bytes);
            c = b + 20'(cache_bytes); d = c + 20'(cache_bytes);
            transact(0, a, 0); transact(0, b, 0);
            before_reads = reads;
            repeat (4) begin transact(0, a, 0); transact(0, b, 0); end
            if (reads != before_reads) $fatal(1, "Two conflicting tags did not coexist");
            transact(0, a, 0); transact(0, c, 0); // evict B, retain A
            before_reads = reads;
            transact(0, a, 0); transact(0, c, 0);
            if (reads != before_reads) $fatal(1, "LRU selected the recently used way");
            transact(0, b, 0);
            if (reads != before_reads+1) $fatal(1, "LRU victim unexpectedly hit");
            for (m = 1; m <= 3; m++) begin
                reset_cache(1'(m), 1'(~m), 0);
                // A occupies way 0; B occupies previously unused way 1.
                if (m & 1) transact(1, a, 8'hb6);
                if (m & 2) transact(1, a+1, 8'hd9);
                before_writes = writes;
                transact(0, b, 0);
                if (writes != before_writes) $fatal(1, "Invalid way was not preferred");
                transact(0, c, 0); // evict dirty A from way 0
                if (writes != before_writes+1) $fatal(1, "Dirty way0 victim not written back");
                // B is now LRU. Dirty it, then hit C to make B LRU again.
                if (m & 1) transact(1, b, 8'h81);
                if (m & 2) transact(1, b+1, 8'h92);
                transact(0, c, 0);
                before_writes = writes;
                transact(1, d, 8'h73); // evict dirty B from way 1
                if (writes != before_writes+1) $fatal(1, "Dirty way1 victim not written back");
                transact(0, a, 0); transact(0, a+1, 0);
                transact(0, b, 0); transact(0, b+1, 0);
            end
        end
    endtask

    task inhibited_case(input [1:0] mask);
        reg [19:0] a, b, c;
        integer before_reads, before_writes;
        begin
            reset_cache(0, 0, 0);
            a = 20'h210; b = a + 20'(cache_bytes); c = b + 20'(cache_bytes);
            ack_delay = 4; done_delay = 9;
            if (mask[0]) transact(1, a, 8'hb6);
            if (mask[1]) transact(1, a+1, 8'hd9);
            if (mask[0]) transact(1, b, 8'h81);
            if (mask[1]) transact(1, b+1, 8'h92);
            before_reads = reads; before_writes = writes;
            // A is LRU. Bypass must preserve both words and the LRU decision.
            transact(0, c, 0, 1); transact(0, c+1, 0, 1);
            if (reads != before_reads+2 || writes != before_writes)
                $fatal(1, "Inhibited miss did not bypass dirty victim");
            // Writing C with inhibit still evicts the unchanged LRU victim A.
            transact(1, c, 8'h73, 1);
            if (writes != before_writes+1) $fatal(1, "Inhibited write did not evict");
            before_reads = reads;
            transact(0, b + (mask[0] ? 20'd0 : 20'd1), 0, 1);
            if (reads != before_reads) $fatal(1, "Inhibited bypass damaged other way");
            if (mask != 3) begin
                transact(0, b + (mask[0] ? 20'd1 : 20'd0), 0, 1);
                transact(0, b + (mask[0] ? 20'd1 : 20'd0), 0, 1);
                if (reads != before_reads+1) $fatal(1, "Inhibited partial fill was not cached");
            end
            transact(0, a, 0); transact(0, a+1, 0);
            before_reads = reads;
            // B is clean only after replacement/refill; force two clean residents.
            transact(0, c + 20'(cache_bytes), 0);
            transact(0, c + 20'(2*cache_bytes), 0);
            before_reads = reads; before_writes = writes;
            transact(0, a, 0, 1); transact(0, a+1, 0, 1);
            if (reads != before_reads+1 || writes != before_writes)
                $fatal(1, "Inhibited clean miss did not allocate");
        end
    endtask

    task overlap_case;
        reg [19:0] a,b,c,d;
        reg phase;
        integer cycles;
        begin
            reset_cache(0, 0, 0);
            a=20'h340; b=a+20'(cache_bytes); c=b+20'(cache_bytes); d=c+20'(cache_bytes);
            ack_delay=0; done_delay=0;
            transact(1,a,8'hb6); transact(1,b,8'h81); transact(0,a,0);
            done_delay=70;
            rapid_request(1,c,8'h9a); // B evicted, A retained
            cycles=0;
            while ((!controller.active || !controller.accepted) && cycles<20) begin tick();cycles++;end
            if (!controller.active || !controller.accepted || busy || sd_req!==sd_ack)
                $fatal(1,"Missing accepted outstanding write");
            phase=sd_req;
            rapid_request(0,c,0); rapid_request(1,c+1,8'hd9); rapid_request(0,c+1,0);
            rapid_request(1,d,8'h73); // A eviction waits for B completion
            if (!controller.active || sd_req!==phase || !busy)
                $fatal(1,"Second eviction bypassed outstanding write guard");
            cycles=0;
            while (busy && cycles<200) begin tick();cycles++;end
            if(busy || sd_req===phase) $fatal(1,"Queued eviction did not resume");
            // B was evicted; its fill must wait for the second write completion.
            transact(0,b,0); transact(0,a,0); transact(0,c,0); transact(0,c+1,0);
            done_delay=0;
        end
    endtask

    task reset_inflight_cases;
        reg [19:0] a, b, c;
        integer mode, cycles;
        reg old_done;
        begin
            $display("Reset during unaccepted/accepted fills and deferred read/write evictions");
            for (mode=0; mode<6; mode++) begin
                ack_delay=0; done_delay=0;
                reset_cache(0,0,0);
                a=20'h12300+20'(2*mode); b=a+20'(cache_bytes); c=b+20'(cache_bytes);
                if (mode>=2) begin
                    transact(1,a,8'hda); transact(1,b,8'hbc);
                end
                ack_delay=mode>=4 ? 0 : ((mode&1)==0 ? 50 : 0);
                done_delay=mode>=4 ? 0 : 50;
                predict(mode>=2 && mode<4,c,8'h45,expected_byte);
                old_done=front_done;
                @(negedge clk); #1;
                front_addr=c; front_we=mode>=2 && mode<4;
                front_din=8'h45;front_inhibit=0;front_req=~front_req;
                if(mode>=4) begin
                    cycles=0;
                    while(front_done===old_done && cycles<100) begin tick();cycles++;end
                    if(front_done===old_done || front_dout!==expected_byte || !busy)
                        $fatal(1,"Reset test did not reach deferred read eviction");
                    operations++;
                    ack_delay=(mode&1)==0 ? 50 : 0;done_delay=50;
                end
                repeat(8) tick();
                if(!controller.active || controller.accepted!==1'(mode) || controller.saved_we!==(mode>=2))
                    $fatal(1,"Reset case %0d failed to reach intended backend phase",mode);
                reset_cache(1'(mode),1'(~mode),0);
                ack_delay=0;done_delay=0;
                transact(0,a,0);transact(0,b,0);transact(0,c,0);
            end
        end
    endtask

    initial begin
        cache_sets = $size(dut.meta);
        cache_words = 2 * cache_sets;
        if (cache_words > MAX_CACHE_WORDS || cache_sets < 2 ||
            (cache_sets & (cache_sets-1)) != 0 ||
            $size(dut.data0) != cache_sets || $size(dut.data1) != cache_sets)
            $fatal(1,"Unsupported two-way cache geometry");
        cache_bytes = 2 * cache_sets;
        index_bits = $clog2(cache_sets);
        tag_count = 1048576 / cache_bytes;
        if ($value$plusargs("SEED=%d", seed)) begin end
        if ($value$plusargs("OPS=%d", random_ops)) begin end
        rng=seed;
        for(i=0;i<4;i++) begin
            mask_count[i]=0;deferred_mask_count[i]=0;deferred_write_mask_count[i]=0;
            inhibited_read_masks[i]=0;inhibited_write_masks[i]=0;
        end
        sd_phase_count[0]=0;sd_phase_count[1]=0;
        for(i=0;i<524288;i++)
            controller.mem[i]={8'((i*29)^(i>>9)^8'ha7),8'((i*17)^(i>>7)^8'h39)};
        $display("Two-way cache: %0d sets, %0d words; seed=%0d random ops=%0d",cache_sets,cache_words,seed,random_ops);
        reset_cache(0,0,1);idle_check();
        transact(0,0,0);transact(0,1,0);transact(0,20'hffffe,0);transact(0,20'hfffff,0);
        replacement_cases();
        inhibited_case(1);inhibited_case(2);inhibited_case(3);
        overlap_case();
        queued_pair();
        reset_inflight_cases();
        $display("Every set in both ways: masked writes, fills, dirty evictions, reset invalidation");
        reset_cache(1,1,0);ack_delay=0;done_delay=0;
        for(i=0;i<cache_sets;i++) begin
            transact(1,20'h80000+20'(2*i),8'(i));
            transact(1,20'h80001+20'(2*i),8'(~i));
            transact(1,20'h80000+20'(cache_bytes+2*i),8'(i^8'h5a));
        end
        for(i=0;i<cache_sets;i++) begin
            transact(0,20'h80000+20'(2*cache_bytes+2*i),0);
            transact(0,20'h80000+20'(3*cache_bytes+2*i),0);
            transact(0,20'h80000+20'(2*i),0);transact(0,20'h80001+20'(2*i),0);
            transact(0,20'h80000+20'(cache_bytes+2*i),0);
        end
        for(i=0;i<cache_sets;i++) begin
            transact(1,20'h80000+20'(2*i),8'h45);
            transact(1,20'h80000+20'(cache_bytes+2*i),8'h67);
        end
        reset_cache(1,0,0);
        for(i=0;i<cache_sets;i++) begin
            transact(0,20'h80000+20'(2*i),0);
            transact(0,20'h80000+20'(cache_bytes+2*i),0);
        end
        reset_cache(0,1,0);
        $display("Every tag at the final set, alternating byte allocations and fills");
        ack_delay=2;done_delay=3;
        for(i=0;i<tag_count;i++) begin
            random_addr=20'(i*cache_bytes+cache_bytes-2+(i&1));
            transact(1,random_addr,8'(i^8'hbc));
            transact(0,random_addr^20'h1,0);transact(0,random_addr,0);
        end
        $display("Random hotspots, conflicting tags, full addresses, inhibit and latency variation");
        for(i=0;i<random_ops;i++) begin
            value=$random(rng)&32'h7fffffff;
            index=value%cache_sets;tag_number=(value>>index_bits)%tag_count;
            case(i%4)
                0: random_addr=20'(tag_number*cache_bytes+2*(index%8)+(value&1));
                1: random_addr=20'h60000+20'(value%32);
                2: random_addr=front_addr^20'hfffff;
                3: random_addr=20'(value);
            endcase
            ack_delay=value%11;done_delay=(value>>5)%17;early_data=1'(value>>9);
            transact(1'(value>>3),random_addr,8'(value>>13),1'(value>>12));
        end
        // Two new tags absent from either way evict both old residents.
        ack_delay=1;done_delay=0;
        for(i=0;i<cache_sets;i++) begin
            tag_number=0;
            while(tag_number==tags[2*i] || tag_number==tags[2*i+1]) tag_number++;
            transact(0,20'(tag_number*cache_bytes+2*i),0);
            tag_number++;
            while(tag_number==tags[2*i] || tag_number==tags[2*i+1]) tag_number++;
            transact(0,20'(tag_number*cache_bytes+2*i),0);
        end
        for(i=0;i<524288;i++)
            if(controller.mem[i]!=={golden[2*i+1],golden[2*i]})
                $fatal(1,"Backing memory mismatch at word %h",i);
        idle_check();
        if(states_seen!==12'h6cf || responses_during_write==0 || guarded_sdram_cycles==0 ||
           lookup_fills==0 || controller.payload_changes_after_ack==0 ||
           simultaneous_completions==0 || separate_completions==0 || sd_phase_count[0]==0 || sd_phase_count[1]==0)
            $fatal(1,"Missing state/handshake/overlap coverage: states=%h",states_seen);
        for(i=1;i<4;i++)
            if(mask_count[i]==0 || deferred_mask_count[i]==0 || deferred_write_mask_count[i]==0 ||
               inhibited_read_masks[i]==0 || inhibited_write_masks[i]==0)
                $fatal(1,"Missing dirty/inhibit/early-response coverage for mask %b",2'(i));
        $display("PASS: %0d operations, %0d fills, %0d writebacks; dirty masks=%0d/%0d/%0d",operations,reads,writes,mask_count[1],mask_count[2],mask_count[3]);
        $display("Overlap responses=%0d guard cycles=%0d post-ack payload changes=%0d",responses_during_write,guarded_sdram_cycles,controller.payload_changes_after_ack);
        $finish;
    end
    initial begin #100000000;$fatal(1,"Global watchdog timeout");end
endmodule
