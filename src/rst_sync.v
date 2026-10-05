// Assert reset asynchronously on PLL lock loss. Sample SDRAM readiness
// synchronously in each client clock domain. SDRAM itself only waits for its PLL.
module rst_sync (
    input wire clk_mclk,
    input wire clk_fclk,
    input wire clk_hclk,
    input wire clk_uclk,
    input wire pll_snes_lock,
    input wire pll_hdmi_lock,
    input wire sdram_ready,
    output wire rst_mclk_n,
    output wire rst_fclk_n,
    output wire rst_hclk_n,
    output wire rst_uclk_n,
    output wire rst_sdram_n
);

reg [2:0] mclk_sync /* synthesis syn_preserve=1 */;
reg [2:0] fclk_sync /* synthesis syn_preserve=1 */;
reg [2:0] hclk_sync /* synthesis syn_preserve=1 */;
reg [2:0] uclk_sync /* synthesis syn_preserve=1 */;
reg [2:0] sdram_sync /* synthesis syn_preserve=1 */;

always @(posedge clk_mclk or negedge pll_snes_lock)
    if (!pll_snes_lock)   mclk_sync <= 3'b000;
    else if (!sdram_ready) mclk_sync <= 3'b000;
    else                   mclk_sync <= {mclk_sync[1:0], 1'b1};

always @(posedge clk_fclk or negedge pll_snes_lock)
    if (!pll_snes_lock)   fclk_sync <= 3'b000;
    else if (!sdram_ready) fclk_sync <= 3'b000;
    else                   fclk_sync <= {fclk_sync[1:0], 1'b1};

always @(posedge clk_hclk or negedge pll_hdmi_lock)
    if (!pll_hdmi_lock)  hclk_sync <= 3'b000;
    else if (!sdram_ready) hclk_sync <= 3'b000;
    else                   hclk_sync <= {hclk_sync[1:0], 1'b1};

always @(posedge clk_uclk or negedge pll_snes_lock)
    if (!pll_snes_lock)   uclk_sync <= 3'b000;
    else if (!sdram_ready) uclk_sync <= 3'b000;
    else                   uclk_sync <= {uclk_sync[1:0], 1'b1};

always @(posedge clk_fclk or negedge pll_snes_lock)
    if (!pll_snes_lock) sdram_sync <= 3'b000;
    else                sdram_sync <= {sdram_sync[1:0], 1'b1};

assign rst_mclk_n  = mclk_sync[2];
assign rst_fclk_n  = mclk_sync[2];
assign rst_hclk_n  = hclk_sync[2];
assign rst_uclk_n  = uclk_sync[2];
assign rst_sdram_n = sdram_sync[2];

endmodule
