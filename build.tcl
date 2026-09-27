if {$argc == 0} {
    puts "Usage: $argv0 <device> [<controller>] [<mcu>]"
    puts "          device: nano20k, primer25k, mega60k, mega138k, console60k"
    puts "      controller: snes, ds2"
    puts "             mcu: bl616, picorv32, serv"
    puts "Note: nano20k supports both controllers simultaneously, so build with just: gw_sh build.tcl nano20k"
    exit 1
}

set dev [lindex $argv 0]
if {$argc >= 2} {
    set controller [lindex $argv 1]
} else {
    set controller ""
}

if {$argc >= 3} {
    set mcu [lindex $argv 2]
} else {
    set mcu "serv"
}

# process $dev and $controller
if {$dev eq "nano20k"} {
    set_device GW2AR-LV18QN88C8/I7 -device_version C
    add_file "src/nano20k/config.vh"
    add_file "src/nano20k/config.vhd"
    add_file -type verilog "src/snestang_top.v"
    add_file -type verilog "src/snes2hdmi_nano.v"
    add_file -type cst "src/nano20k/snestang.cst"
    add_file -type verilog "src/nano20k/gowin_pll_hdmi.v"
    add_file -type verilog "src/nano20k/gowin_pll_snes.v"
    add_file -type verilog "src/nano20k/sdram_nano.v"
    # nano20k supports both controllers simultaneously
    set_option -output_base_name snestang_${dev}
} elseif {$dev eq "primer25k"} {
    set_device GW5A-LV25MG121NC1/I0 -device_version A
    if {$controller eq "snes"} {
        add_file src/primer25k/config_snescontroller.v
        add_file -type cst "src/primer25k/snestang_snescontroller.cst"
    } elseif {$controller eq "ds2"} {
        add_file src/primer25k/config.v
        add_file -type cst "src/primer25k/snestang.cst"
    } else {
        error "Unknown controller $controller"
    }
    add_file -type verilog "src/snes2hdmi.v"
    add_file -type verilog "src/primer25k/gowin_pll_27.v"
    add_file -type verilog "src/primer25k/gowin_pll_hdmi.v"
    add_file -type verilog "src/primer25k/gowin_pll_snes.v"
    add_file -type verilog "src/sdram_cl2_3ch.v"
    set_option -output_base_name snestang_${dev}_${controller}
} elseif {$dev eq "mistle_gw5a_25"} {
    set_device GW5A-LV25LQ144C1/I0 -device_version A
    add_file "src/mistle_gw5a_25/config.vh"
    add_file "src/mistle_gw5a_25/config.vhd"
    add_file -type verilog "src/snestang_top.v"
    add_file -type cst "src/mistle_gw5a_25/snestang.cst"
    add_file -type verilog "src/snes2hdmi.v"
    add_file -type verilog "src/mistle_gw5a_25/gowin_pll_27.v"
    add_file -type verilog "src/mistle_gw5a_25/gowin_pll_hdmi.v"
    add_file -type verilog "src/mistle_gw5a_25/gowin_pll_snes.v"
    add_file -type verilog "src/sdram_cl2_3ch.v"
    add_file -type verilog "src/mistle/mcu_spi.v"
    add_file -type verilog "src/mistle/hid.v"
    set_option -output_base_name snestang_${dev}
} elseif {$dev eq "mega60k"} {
    set_device GW5AT-LV60PG484AC1/I0 -device_version B
    if {$controller eq "snes"} {
        add_file src/mega60k/config_snescontroller.v
        add_file -type cst "src/mega60k/snestang_snescontroller.cst"
    } elseif {$controller eq "ds2"} {
        add_file src/mega60k/config.v
        add_file -type cst "src/mega60k/snestang.cst"
    } else {
        error "Unknown controller $controller"
    }
    add_file -type verilog "src/snes2hdmi.v"
    add_file -type verilog "src/primer25k/gowin_pll_27.v"
    add_file -type verilog "src/primer25k/gowin_pll_hdmi.v"
    add_file -type verilog "src/primer25k/gowin_pll_snes.v"
    add_file -type verilog "src/sdram_cl2_3ch.v"
    set_option -output_base_name snestang_${dev}_${controller}
} elseif {$dev eq "mega138k"} {
    set_device GW5AST-LV138FPG676AES -device_version B
    if {$controller eq "snes"} {
        add_file src/mega138k/config_snescontroller.v
        add_file -type cst "src/mega138k/snestang_snescontroller.cst"
    } elseif {$controller eq "ds2"} {
        add_file src/mega138k/config.v
        add_file -type cst "src/mega138k/snestang.cst"
    } else {
        error "Unknown controller $controller"
    }
    add_file -type verilog "src/snes2hdmi.v"
    add_file -type verilog "src/mega138k/gowin_pll_27.v"
    add_file -type verilog "src/mega138k/gowin_pll_hdmi.v"
    add_file -type verilog "src/mega138k/gowin_pll_snes.v"
    add_file -type verilog "src/mega138k/sdram_cl2_2ch.v"
    add_file -type verilog "src/mega138k/vram.v"
    add_file -type verilog "src/mega138k/vram_spb.v"
    set_option -output_base_name snestang_${dev}_${controller}
} elseif {$dev eq "console60k"} {
    set_device GW5AT-LV60PG484AC1/I0 -device_version B
    if {$controller eq "snes"} {
        add_file src/console60k/config_snescontroller.v
        add_file -type cst "src/console60k/snestang_snescontroller.cst"
    } elseif {$controller eq "ds2"} {
        add_file src/console60k/config.v
        add_file -type cst "src/console60k/snestang.cst"
    } else {
        error "Unknown controller $controller"
    }
    add_file -type verilog "src/snes2hdmi.v"
    add_file -type verilog "src/primer25k/gowin_pll_27.v"
    add_file -type verilog "src/primer25k/gowin_pll_hdmi.v"
    add_file -type verilog "src/primer25k/gowin_pll_snes.v"
    add_file -type verilog "src/sdram_cl2_3ch.v"
    set_option -output_base_name snestang_${dev}_${controller}
} else {
    error "Unknown device $dev"
}

if {$mcu eq "bl616"} {
    add_file -type verilog "src/iosys/iosys_bl616.v"
    add_file -type verilog "src/iosys/uart_fractional.v"
    add_file -type verilog "src/iosys/textdisp.v"
    add_file -type verilog "src/iosys/textdisp_ram.v"
    add_file -type verilog "src/iosys/uart_fixed.v"
} elseif {$mcu eq "picorv32"} {
    add_file -type verilog "src/iosys/iosys_picorv32.v"
    add_file -type verilog "src/iosys/picorv32.v"
    add_file -type verilog "src/iosys/simplespimaster.v"
    add_file -type verilog "src/iosys/simpleuart.v"
    add_file -type verilog "src/iosys/spi_master.v"
    add_file -type verilog "src/iosys/spiflash.v"
    add_file -type verilog "src/iosys/textdisp.v"
    add_file -type verilog "src/iosys/textdisp_ram.v"
} elseif {$mcu eq "serv"} {
    add_file -type verilog "src/iosys/iosys_serv.v"
    add_file -type verilog "src/iosys/simplespimaster.v"
    add_file -type verilog "src/iosys/simpleuart.v"
    add_file -type verilog "src/iosys/spi_master.v"
    add_file -type verilog "src/iosys/spiflash.v"
    add_file -type verilog "src/iosys/textdisp.v"
    add_file -type verilog "src/iosys/textdisp_ram.v"
    add_file -type verilog "src/iosys/serv/servile/servile.v"
    add_file -type verilog "src/iosys/serv/servile/servile_mux.v"
    add_file -type verilog "src/iosys/serv/servile/servile_arbiter.v"
    add_file -type verilog "src/iosys/serv/rtl/serv_aligner.v"
    add_file -type verilog "src/iosys/serv/rtl/serv_alu.v"
    add_file -type verilog "src/iosys/serv/rtl/serv_bufreg.v"
    add_file -type verilog "src/iosys/serv/rtl/serv_bufreg2.v"
    add_file -type verilog "src/iosys/serv/rtl/serv_compdec.v"
    add_file -type verilog "src/iosys/serv/rtl/serv_csr.v"
    add_file -type verilog "src/iosys/serv/rtl/serv_ctrl.v"
    add_file -type verilog "src/iosys/serv/rtl/serv_debug.v"
    add_file -type verilog "src/iosys/serv/rtl/serv_decode.v"
    add_file -type verilog "src/iosys/serv/rtl/serv_immdec.v"
    add_file -type verilog "src/iosys/serv/rtl/serv_mem_if.v"
    add_file -type verilog "src/iosys/serv/rtl/serv_rf_if.v"
    add_file -type verilog "src/iosys/serv/rtl/serv_rf_ram.v"
    add_file -type verilog "src/iosys/serv/rtl/serv_rf_ram_if.v"
    add_file -type verilog "src/iosys/serv/rtl/serv_rf_top.v"
    add_file -type verilog "src/iosys/serv/rtl/serv_state.v"
    add_file -type verilog "src/iosys/serv/rtl/serv_synth_wrapper.v"
    add_file -type verilog "src/iosys/serv/rtl/serv_top.v"
} else {
    error "Unknown MCU $mcu"
}

add_file -type vhdl "src/dpram.vhd"
add_file -type vhdl "src/spram.vhd"
add_file -type vhdl "src/65C816/ALU.vhd"
add_file -type vhdl "src/65C816/AddSubBCD.vhd"
add_file -type vhdl "src/65C816/AddrGen.vhd"
add_file -type vhdl "src/65C816/BCDAdder.vhd"
add_file -type vhdl "src/65C816/MCode.vhd"
add_file -type vhdl "src/65C816/P65816_pkg.vhd"
add_file -type vhdl "src/65C816/P65C816.vhd"
add_file -type verilog "src/CPU.v"
add_file -type verilog "src/dual_clk_fifo.v"
add_file -type verilog "src/dualshock_controller.v"
add_file -type verilog "src/gowin_dpb_cgram.v"
add_file -type verilog "src/gowin_sp_hoam.v"
add_file -type verilog "src/gowin_dpb_oam.v"
add_file -type verilog "src/hdmi2/audio_clock_regeneration_packet.sv"
add_file -type verilog "src/hdmi2/audio_info_frame.sv"
add_file -type verilog "src/hdmi2/audio_sample_packet.sv"
add_file -type verilog "src/hdmi2/auxiliary_video_information_info_frame.sv"
add_file -type verilog "src/hdmi2/hdmi.sv"
add_file -type verilog "src/hdmi2/packet_assembler.sv"
add_file -type verilog "src/hdmi2/packet_picker.sv"
add_file -type verilog "src/hdmi2/serializer.sv"
add_file -type verilog "src/hdmi2/source_product_description_info_frame.sv"
add_file -type verilog "src/hdmi2/tmds_channel.sv"
add_file -type verilog "src/main.v"
add_file -type verilog "src/ppucgram.v"
add_file -type verilog "src/ppuoam.v"
add_file -type verilog "src/ppuhoam.v"
add_file -type verilog "src/ppusprbuf.v"
add_file -type vhdl "src/PPU_PKG.vhd"
add_file -type vhdl "src/PPU.vhd"
add_file -type verilog "src/smc_parser.v"
add_file -type vhdl "src/SNES.vhd"
add_file -type verilog "src/controller_adapter.sv"
add_file -type verilog "src/controller_ds2.sv"
add_file -type verilog "src/controller_snes.v"
add_file -type verilog "src/usb_hid_host/rtl/usb_hid_host.v"
add_file -type verilog "src/usb_hid_host/rtl/usb_hid_host_dual_rom.v"
add_file -type vhdl "src/SMP.vhd"
add_file -type vhdl "src/SPC700/ALU.vhd"
add_file -type vhdl "src/SPC700/AddSub.vhd"
add_file -type vhdl "src/SPC700/AddrGen.vhd"
add_file -type vhdl "src/SPC700/BCDAdj.vhd"
add_file -type vhdl "src/SPC700/MCode.vhd"
add_file -type vhdl "src/SPC700/MulDiv.vhd"
add_file -type vhdl "src/SPC700/SPC700.vhd"
add_file -type vhdl "src/SPC700/SPC700_pkg.vhd"
add_file -type vhdl "src/CEGen.vhd"
add_file -type vhdl "src/DSP.vhd"
add_file -type vhdl "src/DSP_PKG.vhd"
add_file -type vhdl "src/chip/DSP/DSP_LHRomMap.vhd"
add_file -type vhdl "src/chip/DSP/DSPn.vhd"
add_file -type vhdl "src/chip/DSP/OBC1.vhd"
add_file -type vhdl "src/chip/SRTC.vhd"
add_file -type vhdl "src/SWRAM.vhd"
add_file -type verilog "src/uart_tx_V2.v"
add_file -type sdc "src/snestang.sdc"
add_file -type gao -disable "src/mega138k/snestang.gao"

set_option -synthesis_tool gowinsynthesis
set_option -top_module snestang_top
set_option -verilog_std sysv2017
set_option -rw_check_on_ram 1
set_option -place_option 2
set_option -use_mspi_as_gpio 1
set_option -use_sspi_as_gpio 1
set_option -use_ready_as_gpio 1
set_option -use_done_as_gpio 1
set_option -use_i2c_as_gpio 1
set_option -use_cpu_as_gpio 1
set_option -multi_boot 1

run all
