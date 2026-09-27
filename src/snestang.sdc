// Primer25K: 21.4844, 85.9375

// set_multicycle_path: https://docs.xilinx.com/r/en-US/ug903-vivado-using-constraints/set_multicycle_path-Syntax

create_clock -name sys_clk -period 20 -waveform {0 10} [get_ports {sys_clk}]
create_clock -name fclk -period 11.636 -waveform {0 5.818} [get_nets {fclk}]
create_generated_clock -name mclk -source [get_nets {fclk}] -divide_by 4 [get_nets {mclk}]

create_clock -name hclk5 -period 2.694 -waveform {0 1.347} [get_nets {hclk5}]
create_generated_clock -name hclk -source [get_nets {hclk5}] -master_clock hclk5 -divide_by 5 [get_nets {hclk}]
//create_clock -name uclk -period 16.667 -waveform {0 8.3335} [get_nets {uclk}]

create_clock -name clk_audio -period 20833 -waveform {0 10416} [get_nets {s2h/clk_audio}]

create_clock -name mcu_clk -period 50 -waveform {0 25} [get_ports {mcu_clk}] -add

// see start of sdram_snes.v for detailed timing of sdram
// SNES to sdram, 3*fclk
set_multicycle_path 3 -setup -end -from [get_clocks {mclk}] -to [get_clocks {fclk}]
set_multicycle_path 2 -hold -end -from [get_clocks {mclk}] -to [get_clocks {fclk}]
// Except vram?_req for refresh
set_multicycle_path 1 -setup -end -from [get_nets {vram?_req}] -to [get_clocks {fclk}]

// sdram to SNES
set_multicycle_path 3 -setup -start -from [get_clocks {fclk}] -to [get_clocks {mclk}]
set_multicycle_path 2 -hold -start -from [get_clocks {fclk}] -to [get_clocks {mclk}]

// Last constraint takes precedence: PPU to sdram is even longer at 6 fclk cycles
//set_multicycle_path 6 -setup -end -from [get_nets {main/SNES/PPU/BG*}] -to [get_clocks {fclk}]
//set_multicycle_path 5 -hold -end -from [get_nets {main/SNES/PPU/BG*}] -to [get_clocks {fclk}]

// false paths
set_false_path -from [get_clocks {fclk}] -to [get_clocks {hclk}]
set_false_path -from [get_clocks {mclk}] -to [get_clocks {hclk}]
//set_false_path -from [get_clocks {uclk}] -to [get_clocks {mclk}]
//set_false_path -from [get_regs {main/SNES/smp/CPUO*}] -to [get_regs {sdram/dq_out*}]

// The hdmi audio sample words cross from the 48kHz audio clock into the pixel
// clock domain through a toggle handshake: the data is written a full audio
// period (~10us) before the synchronized toggle releases the capture, so the
// single cycle relationship the analyzer assumes here is meaningless. Left
// unconstrained the path is only met by lucky placement, and when it is not
// the captured sample words pick up wrong bits - audible as noisy samples.
set_false_path -from [get_regs {*packet_picker/audio_sample_word_transfer*}] -to [get_regs {*packet_picker/audio_sample_word_buffer*}]
