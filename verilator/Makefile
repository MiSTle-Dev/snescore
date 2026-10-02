N=snestang_top
D=../src

GHDL ?= ghdl
GHDL_FLAGS = --std=08 --latches --out=verilog -fsynopsys
GHDL_DIR = obj_dir/ghdl
GHDL_CONFIG = $D/verilator/config.vhd
PROJECT_ROOT := $(abspath ..)
VERILATOR_FLAGS = -Wno-fatal

DSP_VHDL = $D/CEGen.vhd $D/dpram.vhd $D/DSP_PKG.vhd $D/DSP.vhd
SMP_VHDL = $D/SPC700/SPC700_pkg.vhd $D/SPC700/AddrGen.vhd \
	$D/SPC700/AddSub.vhd $D/SPC700/ALU.vhd $D/SPC700/BCDAdj.vhd \
	$D/SPC700/MCode.vhd $D/SPC700/MulDiv.vhd $D/SPC700/SPC700.vhd $D/SMP.vhd
PPU_VHDL = $D/PPU_PKG.vhd $D/PPU.vhd
CPU_VHDL = $D/CPU.vhd $D/65C816/P65816_pkg.vhd $D/65C816/BCDAdder.vhd \
	$D/65C816/AddSubBCD.vhd $D/65C816/AddrGen.vhd $D/65C816/ALU.vhd \
	$D/65C816/MCode.vhd $D/65C816/P65C816.vhd
SWRAM_VHDL = $D/SWRAM.vhd
SNES_VHDL = $(CPU_VHDL) $(SWRAM_VHDL) $(PPU_VHDL) $(SMP_VHDL) \
	$(DSP_VHDL) $D/SNES.vhd
DSPN_VHDL = $D/spram.vhd $D/dpram.vhd $D/chip/DSP/DSPn.vhd
DSP_MAP_VHDL = $D/CEGen.vhd $(DSPN_VHDL) $D/chip/DSP/OBC1.vhd \
	$D/chip/SRTC.vhd $D/chip/DSP/DSP_LHRomMap.vhd
GSU_VHDL = $D/chip/GSU/GSU_PKG.vhd $D/dpram_difclk.vhd \
	$D/chip/GSU/GSU.vhd $D/chip/GSU/GSUMap.vhd

GHDL_SRCS = $(GHDL_DIR)/DSP.v $(GHDL_DIR)/SMP.v $(GHDL_DIR)/SPPU.v \
	$(GHDL_DIR)/CEGen.v $(GHDL_DIR)/CPU.v $(GHDL_DIR)/SWRAM.v $(GHDL_DIR)/SNES.v \
	$(GHDL_DIR)/DSPn.v $(GHDL_DIR)/DSP_LHRomMap.v \
	$(GHDL_DIR)/GSU.v $(GHDL_DIR)/GSUMap.v
SRCS = $D/verilator/test_loader.v $D/verilator/sdram_sim.v \
	$D/verilator/dpram.v $D/verilator/dpram_difclk.v $D/verilator/bsram_bram.v \
	$D/verilator/spram.v \
	$D/snestang_top.v $D/rst_sync.v $D/main.v \
	$D/ppuhoam.v $D/ppuoam.v $D/ppusprbuf.v $D/ppucgram.v \
	$D/chip/DSP/OBC1.v $D/chip/DSP/SRTC.v \
	$D/smc_parser.v $D/mega138k/vram.v $(GHDL_SRCS)

# Optional compile-time default; at runtime use: ./Vsnestang_top -r roms/game.hex
ifneq ($(ROM_FILE),)
VERILATOR_FLAGS += -DSIM_ROM_FILE=\"$(ROM_FILE)\"
endif

INCLUDES=-I$D/verilator -I$D -I$D/spc700 -I$D/65C816

CFLAGS_SDL=$(shell sdl2-config --cflags) -O2
LIBS_SDL=$(shell sdl2-config --libs)

.PHONY: build sim verilate clean gtkwave audio

build: ./obj_dir/V$N

verilate: ./obj_dir/V$N.cpp

$(GHDL_DIR):
	mkdir -p $@

$(GHDL_DIR)/DSP.v: $(GHDL_CONFIG) $(DSP_VHDL) | $(GHDL_DIR)
	$(GHDL) synth $(GHDL_FLAGS) --vendor-library=work $(GHDL_CONFIG) $(DSP_VHDL) -e DSP > $@.tmp
	mv $@.tmp $@

$(GHDL_DIR)/SMP.v: $(GHDL_CONFIG) $(SMP_VHDL) | $(GHDL_DIR)
	$(GHDL) synth $(GHDL_FLAGS) $(GHDL_CONFIG) $(SMP_VHDL) -e SMP > $@.tmp
	mv $@.tmp $@

$(GHDL_DIR)/SPPU.v: $(GHDL_CONFIG) $(PPU_VHDL) | $(GHDL_DIR)
	$(GHDL) synth $(GHDL_FLAGS) $(GHDL_CONFIG) $(PPU_VHDL) -e SPPU > $@.tmp
	mv $@.tmp $@

$(GHDL_DIR)/CEGen.v: $(GHDL_CONFIG) $D/CEGen.vhd | $(GHDL_DIR)
	$(GHDL) synth $(GHDL_FLAGS) $(GHDL_CONFIG) $D/CEGen.vhd -e CEGen > $@.tmp
	mv $@.tmp $@

$(GHDL_DIR)/CPU.v: $(GHDL_CONFIG) $(CPU_VHDL) | $(GHDL_DIR)
	$(GHDL) synth $(GHDL_FLAGS) $(GHDL_CONFIG) $(CPU_VHDL) -e SCPU > $@.tmp
	mv $@.tmp $@

$(GHDL_DIR)/SWRAM.v: $(GHDL_CONFIG) $(SWRAM_VHDL) | $(GHDL_DIR)
	$(GHDL) synth $(GHDL_FLAGS) $(GHDL_CONFIG) $(SWRAM_VHDL) -e SWRAM > $@.tmp
	mv $@.tmp $@

$(GHDL_DIR)/SNES.v: $(GHDL_CONFIG) $(SNES_VHDL) | $(GHDL_DIR)
	$(GHDL) synth $(GHDL_FLAGS) --vendor-library=work $(GHDL_CONFIG) $(SNES_VHDL) -e SNES > $@.tmp
	mv $@.tmp $@

$(GHDL_DIR)/DSPn.v: $(GHDL_CONFIG) $(DSPN_VHDL) | $(GHDL_DIR)
	cd $(PROJECT_ROOT) && $(GHDL) synth $(GHDL_FLAGS) --vendor-library=work $(abspath $(GHDL_CONFIG)) $(abspath $(DSPN_VHDL)) -e DSPn > $(abspath $@.tmp)
	mv $@.tmp $@

$(GHDL_DIR)/DSP_LHRomMap.v: $(GHDL_CONFIG) $(DSP_MAP_VHDL) | $(GHDL_DIR)
	cd $(PROJECT_ROOT) && $(GHDL) synth $(GHDL_FLAGS) --vendor-library=work $(abspath $(GHDL_CONFIG)) $(abspath $(DSP_MAP_VHDL)) -e DSP_LHRomMap > $(abspath $@.tmp)
	mv $@.tmp $@

$(GHDL_DIR)/GSU.v: $(GHDL_CONFIG) $(GSU_VHDL) | $(GHDL_DIR)
	$(GHDL) synth $(GHDL_FLAGS) -frelaxed --vendor-library=work $(GHDL_CONFIG) $(GSU_VHDL) -e GSU > $@.tmp
	mv $@.tmp $@

$(GHDL_DIR)/GSUMap.v: $(GHDL_CONFIG) $(GSU_VHDL) | $(GHDL_DIR)
	$(GHDL) synth $(GHDL_FLAGS) -frelaxed --vendor-library=work $(GHDL_CONFIG) $(GSU_VHDL) -e GSUMap > $@.tmp
	mv $@.tmp $@

./obj_dir:
	mkdir -p obj_dir

./obj_dir/V$N.cpp: Makefile sim_main.cpp $(SRCS) ./obj_dir
	@echo
	@echo "### VERILATE ####"
	verilator $(VERILATOR_FLAGS) --top-module $N --trace-fst -cc -O3 --exe -CFLAGS "$(CFLAGS_SDL)" -LDFLAGS "$(LIBS_SDL)" $(INCLUDES) $(SRCS) sim_main.cpp

./obj_dir/V$N: verilate
	@echo
	@echo "### BUILDING SIM ###"
	$(MAKE) -C obj_dir -f V$N.mk V$N
	cp -a $D/roms obj_dir
	cp -a $D/chip/DSP/*.hex obj_dir
	test -s obj_dir/random_4m_words.hex || hexdump -vn8388608 -e '8/2 "%04x ""\n"' /dev/random > obj_dir/random_4m_words.hex

sim: ./obj_dir/V$N
	@echo
	@echo "### SIMULATION (GUI) ###"
	@cd obj_dir && ./V$N -c 400000000

trace: ./obj_dir/V$N
	@echo
	@echo "### SIMULATION (trace) ###"
	@cd obj_dir && ./V$N -t -c 100000000 2> stderr.log

trace2: ./obj_dir/V$N
	@echo
	@echo "### SIMULATION (trace) ###"
	@cd obj_dir && ./V$N -t -c 3000000000 -s 300000000

gtkwave:
	gtkwave obj_dir/waveform.vcd

audio:
	ffmpeg -y -f s16le -ar 32k -ac 2 -i obj_dir/snes.aud snes.wav

clean:
	rm -rf obj_dir
