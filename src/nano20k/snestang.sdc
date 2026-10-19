// Tang Nano 20K: 27 MHz oscillator; PLL ratios match gowin_pll_*.v.
create_clock -name sys_clk -period 37.037037 -waveform {0 18.518519} [get_ports {sys_clk}]

// SNES PLL: 27 * 16 / 5 = 86.4 MHz; CLKOUTD divides by four.
create_generated_clock -name fclk -source [get_ports {sys_clk}] -master_clock sys_clk -multiply_by 16 -divide_by 5 [get_nets {fclk}]
create_generated_clock -name mclk -source [get_nets {fclk}] -master_clock fclk -divide_by 4 [get_nets {mclk}]

// HDMI PLL: 27 * 55 / 4 = 371.25 MHz; CLKDIV divides by five.
create_generated_clock -name hclk5 -source [get_ports {sys_clk}] -master_clock sys_clk -multiply_by 55 -divide_by 4 [get_nets {hclk5}]
create_generated_clock -name hclk -source [get_nets {hclk5}] -master_clock hclk5 -divide_by 5 [get_nets {hclk}]

// Fractional audio divider: the shortest full period is 1546 pixel clocks.
// Treat this as a base clock because the accumulator has no fixed divide ratio.
create_clock -name clk_audio -period 20821.548822 -waveform {0 10410.774411} [get_nets {s2h/clk_audio}]

set_clock_groups -asynchronous -group [get_clocks {sys_clk mclk fclk}] -group [get_clocks {hclk hclk5}] -group [get_clocks {clk_audio}]

// Cycle-3 alignment: payloads have three fast clocks to reach SDRAM.
set_multicycle_path 3 -setup -end -from [get_clocks {mclk}] -to [get_clocks {fclk}]
set_multicycle_path 2 -hold -end -from [get_clocks {mclk}] -to [get_clocks {fclk}]

// Refresh checks these registered request toggles one fast clock after capture.
// Override BOTH setup and hold for those paths, not the payload/address paths.
set_multicycle_path 1 -setup -end -from [get_nets {vram?_req}] -to [get_clocks {fclk}]
set_multicycle_path 0 -hold -end -from [get_nets {vram?_req}] -to [get_clocks {fclk}]

// SDRAM read results settle three fast clocks before the SNES samples them.
set_multicycle_path 3 -setup -start -from [get_clocks {fclk}] -to [get_clocks {mclk}]
set_multicycle_path 2 -hold -start -from [get_clocks {fclk}] -to [get_clocks {mclk}]

// Header metadata is established while the SNES is held in reset.
set_false_path -from [get_nets {smc_*}]

// Keep the existing audio CDC exceptions: sample words remain stable while
// the synchronized toggle crosses from the audio domain into the pixel domain.
set_false_path -to [get_regs {*packet_picker*audio_clock_regeneration_packet*clk_audio_counter_wrap_synchronizer_chain*}]
set_false_path -from [get_regs {*packet_picker*audio_sample_word_transfer*}] -to [get_regs {*packet_picker*audio_sample_word_buffer*}]
