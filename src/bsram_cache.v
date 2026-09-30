// Two-way BSRAM cache: 1024 sets, two 16-bit words per set by default.
// Packed metadata holds both tags, byte valid/dirty masks and one exact LRU bit.
module bsram_cache #(parameter SET_BITS = 10) (
    input  wire        clk,
    input  wire        resetn,
    input  wire [19:0] front_addr,
    input  wire [7:0]  front_din,
    input  wire        front_we,
    input  wire        front_req,
    input  wire        front_inhibit,
    output reg         front_ack,
    output reg         front_done,
    output wire [7:0]  front_dout,
    output wire        busy,
    output reg  [19:0] sd_addr,
    output reg  [15:0] sd_din,
    output reg  [1:0]  sd_ds,
    output reg         sd_we,
    output reg         sd_req,
    input  wire        sd_ack,
    input  wire        sd_done,
    input  wire [15:0] sd_dout,
    output wire [3:0]  dbg_state
);
    localparam SETS = 1 << SET_BITS;
    localparam TAG_BITS = 19 - SET_BITS;
    localparam WAY_META_BITS = TAG_BITS + 4;
    localparam META_BITS = 2 * WAY_META_BITS + 1;

    // {LRU victim way, way1 {tag, dirty, valid}, way0 {tag, dirty, valid}}.
    reg [META_BITS-1:0] meta [0:SETS-1];
    reg [15:0] data0 [0:SETS-1];
    reg [15:0] data1 [0:SETS-1];
    reg [META_BITS-1:0] meta_q;
    reg [15:0] data0_q, data1_q;
    reg [SET_BITS-1:0] clear_index;

    reg [19:0] pending_addr;
    reg [7:0]  pending_din;
    reg        pending_we;
    reg        pending_inhibit;
    reg        sd_done_seen;
    reg        write_waiting;

    wire [1:0] byte_mask = pending_addr[0] ? 2'b10 : 2'b01;

    wire [TAG_BITS-1:0] pending_tag = pending_addr[19:SET_BITS+1];
    wire block = pending_addr[0];
    wire [WAY_META_BITS-1:0] way0_meta = meta_q[WAY_META_BITS-1:0];
    wire [WAY_META_BITS-1:0] way1_meta = meta_q[2*WAY_META_BITS-1:WAY_META_BITS];

    // A partial word owns its tag even when the requested byte is invalid.
    wire hit0 = (|way0_meta[1:0]) && way0_meta[WAY_META_BITS-1:4] == pending_tag;
    wire hit1 = (|way1_meta[1:0]) && way1_meta[WAY_META_BITS-1:4] == pending_tag;

    wire selected_way = hit0 ? 1'b0 : hit1 ? 1'b1 :
                        !(|way0_meta[1:0]) ? 1'b0 :
                        !(|way1_meta[1:0]) ? 1'b1 : meta_q[META_BITS-1];

    wire [WAY_META_BITS-1:0] selected_meta = selected_way ? way1_meta : way0_meta;
    wire [15:0] data_q = selected_way ? data1_q : data0_q;
    wire [TAG_BITS-1:0] tag = selected_meta[WAY_META_BITS-1:4];
    wire [1:0] dirty = selected_meta[3:2];
    wire [1:0] valid = selected_meta[1:0];
    wire tag_match = hit0 || hit1;

    reg [SET_BITS-1:0] index;
    reg [7:0] front_dout_reg;

    wire [15:0] merged = {
        tag_match && valid[1] ? data_q[15:8] : sd_dout[15:8],
        tag_match && valid[0] ? data_q[ 7:0] : sd_dout[ 7:0]
    };

    localparam [3:0] CLEAR = 0, IDLE = 1, LOOKUP = 2, WRITEBACK = 3,
                     WAIT_FILL = 6,
                     ALLOCATE = 7, RESPOND = 9, PRIME = 10;
    reg [3:0] state;

    assign dbg_state = state;

    assign busy = (state != IDLE) || (front_req != front_ack);

    assign front_dout = state == WAIT_FILL ?
        (block ? sd_dout[15:8] : sd_dout[7:0]) : front_dout_reg;

    reg        data_we;
    reg [15:0] data_din;
    reg        meta_we;
    reg [META_BITS-1:0] meta_din;
    reg [WAY_META_BITS-1:0] way_meta_din;

    // One full-word write port per RAM. Byte writes preserve the other byte
    // from the word read after latching the request, avoiding partial RAM writes.
    always @* begin
        data_we = 0;
        data_din = 0;
        meta_we = 0;
        index = pending_addr[SET_BITS:1];
        meta_din = meta_q;
        way_meta_din = selected_meta;
        if (resetn) begin
            case (state)
                CLEAR: begin
                    meta_we = 1;
                    index = clear_index;
                    meta_din = 0;
                end
                IDLE: ;
                LOOKUP: if (tag_match && (pending_we || (block ? valid[1] : valid[0]))) begin
                    meta_we = 1;
                    if (pending_we) begin
                        data_we = 1;
                        data_din = block ? {pending_din, data_q[7:0]} : {data_q[15:8], pending_din};
                        way_meta_din = {tag, (dirty | byte_mask), (valid | byte_mask)};
                    end
                end
                WAIT_FILL: if (sd_done != sd_done_seen) begin
                    data_we = !pending_inhibit || tag_match || ~|dirty;
                    data_din = merged;
                    meta_we = !pending_inhibit || tag_match || ~|dirty;
                    way_meta_din = {pending_tag, tag_match ? dirty : 2'b00, 2'b11};
                end
                ALLOCATE: if (pending_we) begin
                    data_we = 1;
                    data_din = block ? {pending_din, 8'b0} : {8'b0, pending_din};
                    meta_we = 1;
                    way_meta_din = {pending_tag, byte_mask, byte_mask};
                end
                default: begin end
            endcase
            if (meta_we && state != CLEAR) begin
                if (selected_way)
                    meta_din[2*WAY_META_BITS-1:WAY_META_BITS] = way_meta_din;
                else
                    meta_din[WAY_META_BITS-1:0] = way_meta_din;
                // The accessed/installed way is MRU; the other is next victim.
                meta_din[META_BITS-1] = !selected_way;
            end
        end
    end

    // Dedicated synchronous read outputs have no reset or alternate drivers.
    // IDLE samples the address and RAMs on the acceptance edge. The outputs
    // hold the accepted request's word throughout lookup and SDRAM waits.
    // These outputs retain a dirty victim after fill/allocation replaces the RAM
    // entry, until WRITEBACK copies the victim into the SDRAM request registers.
    always @(posedge clk) begin
        if (state == IDLE) begin
            meta_q <= meta[front_addr[SET_BITS:1]];
            data0_q <= data0[front_addr[SET_BITS:1]];
            data1_q <= data1[front_addr[SET_BITS:1]];
        end else begin
            if (meta_we)
                meta[index] <= meta_din;
            if (data_we) begin
                if (selected_way) data1[index] <= data_din;
                else data0[index] <= data_din;
            end
        end
    end

    always @(posedge clk) begin
        if (!resetn) begin
            front_ack <= 0;
            front_done <= 0;
            front_dout_reg <= 0;
            sd_addr <= 0;
            sd_din <= 0;
            sd_ds <= 0;
            sd_we <= 0;
            sd_req <= sd_ack;
            sd_done_seen <= sd_done;
            write_waiting <= 0;
            pending_addr <= 0;
            pending_din <= 0;
            pending_we <= 0;
            pending_inhibit <= 0;
            clear_index <= 0;
            state <= CLEAR;
        end else begin
            // Acceptance does not imply completion. Cache hits may proceed while
            // a writeback is outstanding. Payload may change after ack, but a new
            // SDRAM request must wait until its done toggle has been observed.
            if (write_waiting && sd_done != sd_done_seen)
                write_waiting <= 0;
            case (state)
                CLEAR: begin
                    if (clear_index == SETS-1)
                        state <= PRIME;
                    else
                        clear_index <= clear_index + 1'b1;
                end

                PRIME: state <= IDLE;

                IDLE: if (front_req != front_ack) begin
                    front_ack <= front_req;
                    front_dout_reg <= front_din;
                    pending_addr <= front_addr;
                    pending_din <= front_din;
                    pending_we <= front_we;
                    pending_inhibit <= front_inhibit;
                    state <= LOOKUP;
                end

                LOOKUP: begin
                    if (tag_match && (pending_we || (block ? valid[1] : valid[0]))) begin
                        if (!pending_we) begin
                            front_dout_reg <= block ? data_q[15:8] : data_q[7:0];
                        end
                        state <= RESPOND;
                    end else if (pending_we) begin
                        state <= ALLOCATE;
                    end else if (sd_req == sd_ack && !write_waiting) begin
                        sd_done_seen <= sd_done;
                        sd_req <= ~sd_req;
                        state <= WAIT_FILL;
                    end
                    // it's always safe to set SDRAM transaction
                    // data when the previous was accepted
                    if (sd_req == sd_ack) begin
                        sd_addr <= {pending_addr[19:1], 1'b0};
                        sd_ds <= 2'b11;
                        sd_we <= 0;
                    end
                end

                WRITEBACK: if (sd_req == sd_ack && !write_waiting) begin
                    sd_addr <= {tag, index, 1'b0};
                    sd_din <= data_q;
                    sd_ds <= dirty;
                    sd_we <= 1;
                    sd_done_seen <= sd_done;
                    write_waiting <= 1;
                    sd_req <= ~sd_req;
                    state <= IDLE;
                end

                WAIT_FILL: if (sd_done != sd_done_seen) begin
                    front_dout_reg <= block ? sd_dout[15:8] : sd_dout[7:0];
                    state <= (!tag_match && |dirty && !pending_inhibit) ? ALLOCATE : RESPOND;
                end

                ALLOCATE: begin
                    front_done <= ~front_done;
                    state <= (!tag_match && |dirty) ? WRITEBACK : IDLE;
                end

                RESPOND: begin
                    front_done <= ~front_done;
                    state <= IDLE;
                end

                default: state <= CLEAR;
            endcase
        end
    end
endmodule
