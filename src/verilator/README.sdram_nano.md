# Nano20K SDRAM regression

Run from the repository root:

```sh
make -C src/verilator -f Makefile.sdram_nano test
```

The test uses the production `src/nano20k/sdram_nano.v` and a sparse CL2
32-bit SDRAM pin model. It covers all four initial phases of the divide-by-four
core clock and all combinations of `ROM_DONE_DELAY` / `BSRAM_DONE_DELAY`.

The controller aligns an idle frame to cycle 3 after the `clkref` rising edge.
Its cycle-2 refresh decision therefore follows the core-clock capture of a new
VRAM request by one fast clock. Refresh uses the registered request/acknowledge
toggles; it does not depend on the live PPU tile-address calculation. The
Nano-specific SDC constrains those toggles to one fast cycle, while addresses
and payloads retain their three-cycle constraints. Busy transfers retain their
frame schedule instead of being interrupted by a reference edge.

Coverage includes reference alignment, requests on either/both VRAM ports at
the refresh boundary, refresh-to-ACTIVATE recovery, refresh progress, reset,
ROM halfword masks and 4 MiB mirroring, BSRAM byte masks and 128 KiB mirroring,
WRAM byte lanes, ARAM/RV arbitration, and VRAM reads/writes. Outputs and physical
memory words are checked independently of the request/acknowledge toggles.

The model does not validate electrical timing, PLL phase on hardware, video
sampling deadlines inside the PPU, or timing closure. Check the Nano20K Gowin
build and timing report separately after changing the frame or its constraints.
