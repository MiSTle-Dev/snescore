// Spi flash module with two functions,
// 1. Inital program loading from flash
// 2. MMIO interface for R/W accesses to the flash
// 
// MMIO Registers:
// 0x200_0070: Byte reg. Write to initiate a byte transfer.
//             The lowest byte is transfered over SPI.
//             Then a read will return the received byte.
// 0x200_0074: Word transfer. Writes and reads 4 bytes.
// 0x200_0078: Control register (write-only). [0]=CS_N
//
// Chip is Winbond W25Q64
module spiflash #(
    parameter CLK_DIV = 2,
    parameter [23:0] ADDR = 1024*1024,
    parameter LEN = 1024
) (
    input clk,
    input resetn,

    output ncs,         // chip select
    input miso,         // master in slave out
    output mosi,        // mster out slave in
    output sck,         // spi clock

    // program loading at ADDR for LEN bytes
    input start,        // pulse to start loading from flash 
    output reg busy,
    output reg [7:0] dout,
    output reg dout_strb,

    // RV MMIO interface
    input             reg_byte_we,  // 1: write-read a byte 
    input	      	  reg_word_we,	// 1: write-read a word
    input             reg_ctrl_we,  // 1: write control register
    input      [31:0] reg_di,
    output reg [31:0] reg_do,
    output            reg_wait
);

localparam [3:0] INIT_SELECT = 4'd0,
                 INIT_FIRST  = 4'd1,
                 INIT_SECOND = 4'd2,
                 INIT_FINISH = 4'd3,
                 INIT_GAP    = 4'd4,
                 IDLE        = 4'd5,
                 READ_CMD    = 4'd6,
                 READ_DATA   = 4'd7,
                 MMIO        = 4'd8;

reg [3:0] state;
reg load_pending;

reg ncs_buf = 1'b1;
assign ncs = ncs_buf;
reg [7:0] data_in;
wire [7:0] data_out;
reg spi_start;
wire spi_ready;

reg [20:0] cnt;         // transfer byte count, max 2MB

assign reg_wait = wait_buf & (reg_byte_we | reg_word_we);
reg wait_buf = 1;
reg reg_byte_we_r, reg_word_we_r;
reg active, new_request;
wire new_request_t = (reg_byte_we && ~reg_byte_we_r) || (reg_word_we && ~reg_word_we_r);

SPI_Master #(.CLKS_PER_HALF_BIT(CLK_DIV)) spi (
  .i_Clk(clk), .i_Rst_L(resetn),
  .i_TX_Byte(data_in), .i_TX_DV(spi_start), .o_TX_Ready(spi_ready),
  .o_RX_DV(), .o_RX_Byte(data_out),
  .o_SPI_Clk(sck), .i_SPI_MISO(miso), .o_SPI_MOSI(mosi)
);

always @(posedge clk) begin
    if (~resetn) begin
        state <= INIT_SELECT;
        ncs_buf <= 1'b1;
        load_pending <= 1'b0;
        spi_start <= 1'b0;
        busy <= 1'b0;
        dout_strb <= 1'b0;
        wait_buf <= 1'b1;
        reg_byte_we_r <= 1'b0;
        reg_word_we_r <= 1'b0;
        new_request <= 1'b0;
        active <= 1'b0;
        cnt <= 0;
    end else begin
        reg_byte_we_r <= reg_byte_we;
        reg_word_we_r <= reg_word_we;
        if (start)
            load_pending <= 1'b1;
        if (state == MMIO && new_request_t)
            new_request <= 1;

        if (state == MMIO && reg_ctrl_we)
            ncs_buf <= reg_di[0];

        spi_start <= 0;
        wait_buf <= 1;
        dout_strb <= 0;
        case (state) 
        INIT_SELECT: begin
            // A previous FPGA configuration read may have left the flash in
            // dual-I/O continuous read mode. Clock 16 ones on IO0 with /CS low.
            ncs_buf <= 0;
            state <= INIT_FIRST;
        end
        INIT_FIRST: if (~spi_start && spi_ready) begin
            data_in <= 8'hff;
            spi_start <= 1;
            state <= INIT_SECOND;
        end
        INIT_SECOND: if (~spi_start && spi_ready) begin
            data_in <= 8'hff;
            spi_start <= 1;
            state <= INIT_FINISH;
        end
        INIT_FINISH: if (~spi_start && spi_ready) begin
            ncs_buf <= 1;
            state <= INIT_GAP;
        end
        INIT_GAP: state <= IDLE;
        IDLE:
            if (load_pending || start) begin
                ncs_buf <= 0;
                state <= READ_CMD;
                cnt <= 0;
                busy <= 1;
                load_pending <= 0;
            end
        READ_CMD: if (~spi_start && spi_ready) begin // send READ (03h) command
            cnt <= cnt + 1;
            spi_start <= 1;
            case (cnt[2:0])
            3'd0: data_in <= 8'h03;
            3'd1: data_in <= ADDR[23:16];
            3'd2: data_in <= ADDR[15:8];
            3'd3: data_in <= ADDR[7:0];
            3'd4: begin
                // start receiving first byte
                state <= READ_DATA;
                cnt <= 1;
                data_in <= 0;
            end
            default: ;
            endcase
        end
        READ_DATA: if (~spi_start && spi_ready) begin // read back LEN bytes
            dout <= data_out;
            dout_strb <= 1'b1;
            if (cnt == LEN) begin
                state <= MMIO;
                busy <= 0;
                ncs_buf <= 1'b1;
                cnt <= 0;
            end else begin
                cnt <= cnt + 21'd1;
                spi_start <= 1;
            end
        end
        MMIO: begin
            if (spi_ready && ~spi_start && (new_request_t || new_request || active)) begin
                // send
                if (new_request || new_request_t) begin
                    data_in <= reg_di[7:0];
                    spi_start <= 1;
                    active <= 1;
                    new_request <= 0;
                end else if (reg_word_we && cnt != 21'd3) begin
                    data_in <= reg_di[(cnt+1)*8 +: 8];
                    spi_start <= 1;
                    cnt <= cnt + 21'd1;
                end else begin      // last byte is transmitted, let CPU continue
                    wait_buf <= 0;
                    cnt <= 0;
                    active <= 0;
                end

                // receive
                if (~new_request)
                    reg_do[cnt*8 +: 8] <= data_out;
            end
        end
        default: state <= INIT_SELECT;
        endcase
    end
end

endmodule
