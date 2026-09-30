# 3ch SDRAM regression

Run from `src` with Icarus Verilog installed:

```sh
make -C verilator -f Makefile.sdram_3ch test
```

The runner tests the production `sdram_cl2_3ch.v` controller with a sparse
SDRAM pin model in eight configurations: 16 MiB / 32 MiB SDRAM, with every
combination of `ROM_DONE_DELAY` and `BSRAM_DONE_DELAY` disabled/enabled.
Executables go into `/tmp/snestang-sdram-gsu` by default (`BUILD_DIR` overrides it).

WRAM, ROM, BSRAM, and RV share channel 0, in that priority order. Each has an independent request/ack handshake. ARAM runs
independently in channel 1 and bank 2; VRAM uses channel 2 and bank 3.
Channel 0 reserves at cycle 0, ACKs at cycle 2, and captures read data at cycle 5.
ROM/BSRAM read done toggles at cycle 5 or cycle 7 according to its delay parameter.
BSRAM write done toggles at cycle 2; ROM loader writes use ACK without done.
ARAM writes move from cycle 3 to cycle 6 when channel 0 reserves a read.

With 16 MiB SDRAM, ROM maps across bank 0 and the first 2 MiB of bank 1, with
WRAM occupying bank 1 offsets `0x1E0000–0x1FFFFF`. With 32 MiB SDRAM, ROM and
WRAM use bank 0; WRAM occupies offsets `0x7E0000–0x7FFFFF`.
BSRAM starts at bank 1 offset `0x300000` in both configurations. ARAM starts at
bank 2 offset `0x380000` / `0x780000` for 16 MiB / 32 MiB SDRAM respectively.

Coverage includes BSRAM address boundaries and masked writes, ROM bank mapping
and loader writes, WRAM boundaries and byte masks, simultaneous ROM/WRAM/BSRAM
requests with independent ARAM reads, normal/delayed ARAM writes, a late BSRAM
request, isolated done toggles and their exact cycles, refresh progress while
GSU requests wait, and RV service under sustained GSU ROM traffic.
The test starts GSU traffic after the first periodic refresh, following the
board's sequence where cartridge loading precedes coprocessor execution.

The pin model checks SDRAM commands, physical word addresses, data, masks, and
host handshakes. It covers CL2 single-word transfers at the controller's expected
clock phase; it does not validate electrical timing, synthesis, the GSU core,
its CE generation, or board behavior.
