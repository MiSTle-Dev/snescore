# Repository Guidelines

## Project Structure & Module Organization

SnesTang ports an FPGA SNES core to MiSTle boards. `src/` contains Verilog, SystemVerilog, and VHDL gateware; `src/chip/` holds cartridge coprocessors, `src/iosys/` the soft-CPU I/O system, and board directories such as `src/icepi-zero/` contain configuration, constraints, and projects. `src/iosys/serv/` and `src/usb_hid_host/` are Git submodules. Follow any nested `AGENTS.md` when editing them.

`verilator/` contains the C++ simulation harness; `src/verilator/` supplies simulation models and focused regressions. Additional benches live in `tests/`, and firmware sources and host tests live in `firmware/`. Architecture and installation notes are in `doc/`; ROM tables and display assets reside alongside their consuming modules.

## Build, Test, and Development Commands

Run these from the repository root:

- `git submodule update --init --recursive`: initialize required dependencies.
- `gw_sh build.tcl nano20k`: synthesize and place/route a Nano 20K build with Gowin tools. Other targets can require controller and MCU arguments; see `build.tcl`.
- `cd src/icepi-zero && diamondc build.tcl`: build the ECP5 bitstream with Lattice Diamond. The adjacent `build.sh` also invokes hardware programming.
- `make -C verilator build`: build the simulator using GHDL, Verilator, SDL2, and a C++ toolchain; `make -C verilator sim` launches it.
- `make -C src/verilator -f Makefile.bsram_cache test`: run Icarus Verilog cache regressions.
- `make -C src/verilator -f Makefile.sdram_3ch test`: test SDRAM configurations and handshakes.
- `make -C firmware test`: run host fault-injection tests with Python 3 and GCC.

## Coding Style & Naming Conventions

Match surrounding code; prefer four-space indentation in new HDL/C code and tabs for Make recipes. Use descriptive snake_case for new signals and modules, uppercase constants, and existing VHDL entity/package conventions. Preserve imported naming and avoid unrelated reformatting. No repository-wide formatter or linter configuration is provided.

## Testing Guidelines

Add focused regressions for behavior changes. Follow existing `tb_*.sv`, `*_tb.v`, and `test_*.c` naming. Exercise reset, boundary addresses, handshake delays, and failure paths where relevant. No numeric coverage threshold is defined. For board changes, report synthesis/timing results and hardware checks separately from simulation.

## Commit & Pull Request Guidelines

History favors short, imperative subjects such as `fix constraints` or `build: restore primer25k build`; optional subsystem prefixes are common. Keep commits focused. PRs should explain behavior changes, affected boards, validation commands/results, and related issues. Include screenshots or waveforms when they clarify visual or timing changes. Exclude generated build outputs.
