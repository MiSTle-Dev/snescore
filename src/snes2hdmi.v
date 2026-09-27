// NES video and sound to HDMI converter
// nand2mario, 2022.9

`timescale 1ns / 1ps

module snes2hdmi #(
    parameter SNES_FREQ  = 21_484_400,
    parameter PIXEL_FREQ = 74_250_000
) (
	input clk,      // snes clock
	input resetn,
	input pixel_resetn,

    // snes video and audio signals
    input dotclk,
    input hblank,
    input vblank,
    input [14:0] rgb5,
    input [8:0] xs, // {x,dotclk}
    input [8:0] ys, // {field,y}

    input overlay,
    output [7:0] overlay_x,
    output [7:0] overlay_y,
    input [14:0] overlay_color,

    input [15:0] audio_l,
    input [15:0] audio_r,
    input audio_ready,

    // frame-sync pause happens during snes_refresh
    input snes_refresh,

	// video clocks
	input clk_pixel,
	input clk_5x_pixel,

    output reg pause_snes_for_frame_sync,

    // output [7:0] led,

	// output signals
	output       tmds_clk_n,
	output       tmds_clk_p,
	output [2:0] tmds_d_n,
	output [2:0] tmds_d_p
);

    localparam FRAMEWIDTH = 1280;       // 720P
    localparam FRAMEHEIGHT = 720;
    localparam TOTALWIDTH = 1650;
    localparam TOTALHEIGHT = 750;
    localparam SCALE = 5;
    localparam VIDEOID = 4;
    localparam VIDEO_REFRESH = 60.0;

    localparam IDIV_SEL_X5 = 3;
    localparam FBDIV_SEL_X5 = 54;
    localparam ODIV_SEL_X5 = 2;
    localparam DUTYDA_SEL_X5 = "1000";
    localparam DYN_SDIV_SEL_X5 = 2;

    localparam CLKFRQ = 74250;

    localparam AUDIO_BIT_WIDTH = 16;

    // video stuff
    wire [9:0] cy, frameHeight;
    wire [10:0] cx, frameWidth;
    reg active, r_active;
    wire [7:0] x, y;                    // SNES pixel position

    //
    // BRAM line buffer for 16 lines. Each pixel is 5:5:5 RGB
    // Each BRAM block holds 4 lines. So 16 lines needs 4 blocks.
    //
    localparam BUF_WIDTH = 5;        // 2 ^ BUF_WIDTH lines
    localparam BUF_SIZE = 1 << BUF_WIDTH;
    reg [14:0] mem [0:BUF_SIZE*256-1];
    reg [BUF_WIDTH+8-1:0] mem_portA_addr;
    reg [14:0] mem_portA_wdata;
    reg mem_portA_we;
    wire [BUF_WIDTH+8-1:0] mem_portB_addr;
    reg [14:0] mem_portB_rdata;
    reg mem_writeto = 1'b0;     // current line we are writing to. we read from the other line

    // We need to do a bit of synchronization as the SNES and HDMI run on separate clocks and they
    // do not align perfectly.
    // - Let SNES execute a bit faster (0.5%) than the HDMI stack. This way we always have enough pixels.
    // - For each frame, we let the SNES run until the first line is rendered, and written to line buffer.
    //   Then we pause the SNES and wait (through pause_snes_for_frame_sync) for HDMI to catch up.
    // - Once HDMI started the frame, start SNES again.
    reg sync_done = 1'b0;
    reg hdmi_first_line;
    reg pause_sync;     // pause for even number of cycles for PPU sdram access to stay in sync
    reg hdmi_first_line_r, hdmi_first_line_rr;
    always @(posedge clk) begin
        hdmi_first_line_r <= hdmi_first_line;
        hdmi_first_line_rr <= hdmi_first_line_r;
        if (pause_snes_for_frame_sync) pause_sync <= ~pause_sync;
        if (~sync_done) begin
            if (~pause_snes_for_frame_sync) begin
                if (ys[7:0] == 8'd1 && snes_refresh) begin      // halt SNES after first line is buffered
                    pause_snes_for_frame_sync <= 1'b1;
                    pause_sync <= 0;
                end
            end else if (hdmi_first_line_rr && pause_sync) begin                 // HDMI frame start, now resume SNES
                pause_snes_for_frame_sync <= 1'b0;
                sync_done <= 1'b1;
            end
        end else
            pause_snes_for_frame_sync <= 1'b0;
        if (ys[7:0] == 8'd200) sync_done <= 1'b0;               // reset sync_done for next frame
    end
    always @(posedge clk_pixel) begin
        if (cy == 0 && cx >= 11'd160)
            hdmi_first_line <= 1;
        else
            hdmi_first_line <= 0;
    end

    // BRAM port A read/write
	always_ff @(posedge clk) begin
		if (mem_portA_we) begin
			mem[mem_portA_addr] <= mem_portA_wdata;
		end
	end

    // BRAM port B read
    always_ff @(posedge clk_pixel) begin
        mem_portB_rdata <= mem[mem_portB_addr];
    end

    integer j;
    initial begin
        // On power-up, fill line buffer with a gradient
        for (j = 0; j < 512; j=j+1) begin
            mem[j][14:10] = j[4:0];
            mem[j][ 9: 5] = j[4:0];
            mem[j][ 4: 0] = j[4:0];
        end
    end

    //
    // Data input
    //
    reg r_dotclk, r_vblank, r_hblank;
    always @(posedge clk) begin
        r_dotclk <= dotclk;
        r_vblank <= vblank;
        mem_portA_we <= 1'b0;
        if (dotclk && ~r_dotclk && ~hblank && ~vblank && ys[7:0] < 224) begin       // on posedge of dotclk, read a pixel
            mem_portA_addr <= {ys[BUF_WIDTH-1:0], xs[8:1]};
            mem_portA_wdata <= rgb5;
            mem_portA_we <= 1'b1;
        end
    end

    always @(posedge clk) begin
        r_hblank <= hblank;
        if (hblank & ~r_hblank) begin       // flip active line on hblank
            mem_writeto <= ~mem_writeto;
        end
    end

    reg [31:0] audio_sample;
    reg [15:0] audio_sample_word [1:0];
    reg        audio_sample_ack;
    reg  [1:0] audio_sample_ack_d;

    // An integer divider cannot hit 48kHz: 74250000 / 48000 / 2 = 773.4375, and the
    // truncation leaves the stream running fast, which makes sinks drop a chunk of
    // audio every few seconds. A phase accumulator keeps the fractional part.
    localparam integer AUDIO_RATE = 48000;
    localparam integer AUDIO_ACC_WIDTH = $clog2(PIXEL_FREQ + AUDIO_RATE);

    localparam [AUDIO_ACC_WIDTH-1:0] AUDIO_INC = ((AUDIO_ACC_WIDTH*2)'(AUDIO_RATE) <<< AUDIO_ACC_WIDTH) / PIXEL_FREQ;

    reg [AUDIO_ACC_WIDTH-1:0] aclk_acc;
    reg                       clk_audio /* synthesis syn_keep=1 */;
    reg                       aclk_tick;

    always @(posedge clk_pixel) begin
        aclk_acc  <= aclk_acc + AUDIO_INC;
        clk_audio <= aclk_acc[AUDIO_ACC_WIDTH-1];                 // msb of the accumulator = 48kHz
        aclk_tick <= (clk_audio != aclk_acc[AUDIO_ACC_WIDTH-1]);  // high the cycle after each edge

        // The sample word must not change on the same clk_pixel edge that toggles
        // clk_audio: the hdmi module latches it on that very edge, so data and
        // clock would race and the captured word could pick up wrong bits, which
        // is audible as noisy samples. Updating one cycle later leaves the word
        // stable for a full audio half period before it is sampled.
        if (aclk_tick) begin
            {audio_sample_word[1], audio_sample_word[0]} <= audio_sample;
            audio_sample_ack <= ~audio_sample_ack;
        end
    end

    always @(posedge clk) begin
        audio_sample_ack_d <= {audio_sample_ack_d[0], audio_sample_ack};

        if (audio_sample_ack_d[0] != audio_sample_ack_d[1])
            audio_sample <= {audio_r, audio_l};
    end

    //
    // Video
    //
    reg [23:0] rgb;             // actual RGB output
    reg [7:0] xx;               // scaled-down pixel position
    reg [7:0] yy;
    reg [10:0] xcnt;
    reg [10:0] ycnt;            // fractional scaling counters
    reg [9:0] cy_r;
    assign mem_portB_addr = {yy[BUF_WIDTH-1:0], xx};
    assign overlay_x = xx;
    assign overlay_y = yy;
    localparam XSTART = (1280 - 960) / 2;   // 960:720 = 4:3
    localparam XSTOP = (1280 + 960) / 2;

    // address calculation
    // Assume the video occupies fully on the Y direction, we are upscaling the video by `720/height`.
    // xcnt and ycnt are fractional scaling counters.
    always @(posedge clk_pixel) begin
        reg active_t;
        reg [10:0] xcnt_next;
        reg [10:0] ycnt_next;
        xcnt_next = xcnt + 256;
        ycnt_next = ycnt + 224;

        active_t = 0;
        if (cx == XSTART - 1) begin
            active_t = 1;
            active <= 1;
        end else if (cx == XSTOP - 1) begin
            active_t = 0;
            active <= 0;
        end

        if (active_t | active) begin        // increment xx
            xcnt <= xcnt_next;
            if (xcnt_next >= 960) begin
                xcnt <= xcnt_next - 960;
                xx <= xx + 1;
            end
        end

        cy_r <= cy;
        if (cy[0] != cy_r[0]) begin         // increment yy at new lines
            ycnt <= ycnt_next;
            if (ycnt_next >= 720) begin
                ycnt <= ycnt_next - 720;
                yy <= yy + 1;
            end
        end

        if (cx == 0) begin
            xx <= 0;
            xcnt <= 0;
        end

        if (cy == 0) begin
            yy <= 0;
            ycnt <= 0;
        end

    end

    // calc rgb value to hdmi
    always @(posedge clk_pixel) begin
        if (active) begin
            if (overlay)
                rgb <= {overlay_color[4:0],3'b0,overlay_color[9:5],3'b0,overlay_color[14:10],3'b0};       // BGR5 to RGB8
            else
                rgb <= {mem_portB_rdata[4:0], 3'b0, mem_portB_rdata[9:5], 3'b0, mem_portB_rdata[14:10], 3'b0};
        end else
            rgb <= 24'h000000;
    end

    // HDMI output.
    logic [2:0] tmds;
    logic       tmds_clk;

    hdmi #( .VIDEO_ID_CODE(VIDEOID),
            .DVI_OUTPUT(0),
            .VIDEO_REFRESH_RATE(VIDEO_REFRESH),
            .IT_CONTENT(1),
            .AUDIO_RATE(AUDIO_RATE),
            .AUDIO_BIT_WIDTH(AUDIO_BIT_WIDTH),
            .START_X(0),
            .START_Y(0) )

    hdmi( .clk_pixel_x5(clk_5x_pixel),
          .clk_pixel(clk_pixel),
          .clk_audio(clk_audio),
          .rgb(rgb),
          .reset( ~pixel_resetn ),
          .audio_sample_word(audio_sample_word),
          .tmds(tmds),
          .tmds_clock(tmds_clk),
          .cx(cx),
          .cy(cy),
          .frame_width( frameWidth ),
          .frame_height( frameHeight ) );

`ifdef GOWIN
    // Gowin LVDS output buffer
    ELVDS_OBUF tmds_bufds [3:0] (
        .I({clk_pixel, tmds}),
        .O({tmds_clk_p, tmds_d_p}),
        .OB({tmds_clk_n, tmds_d_n})
    );
`else
    assign tmds_clk_p = tmds_clk;
    assign tmds_clk_n = 1'b0;
    assign tmds_d_p   = tmds;
    assign tmds_d_n   = 3'b0;
`endif

endmodule
