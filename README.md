# SnesTang for MiSTle

This project is based on [nand2mario's SNESTang](https://github.com/nand2mario/snestang) and is a work in progress to bring it to the [MiSTle framework](https://github.com/MiSTle-Dev). It retains the improvements from nand2mario's project while adapting the core and its I/O system for MiSTle boards.

Supported boards include [IcePi Zero](src/icepi-zero), [IcePi Zero XL](src/icepi-zero-xl), [MiSTle GW5A-25K (`mistle_gw5a_25`)](src/mistle_gw5a_25), and Tang Nano 20k. Both IcePi devices have USB HID support. IcePi Zero also works with the [MiSTle IcePi carrier board](https://github.com/MiSTle-Dev/Boards/tree/main/icepi_carrier), which offers broader USB compatibility.

## MiSTle GW5A-25 and Nano20k

This core can be built to support the MiSTle framework and its FPGA Companion MCU when run on the MiSTle GW5A-25K or the Tang Nano 20k. In this case the
SNESTangs own On-Screen-Display is being disabled and the MiSTle OSD is being used instead. This can be invoked as usual via F12 if a keyboard is connected
or by pressing **Select + Start** on the first gamepad.

The MiSTle GW5A-25K (`mistle_gw5a_25`) supports all DSP variants and the GSU (Super FX) chip. Its larger 25K FPGA provides the resources needed for GSU support, together with a two-way BSRAM cache. This allows games such as Super Mario World 2: Yoshi's Island and Star Fox to run.

The Tang Nano 20k supports only DSP1 due to FPGA space constraints, covering most DSP-based games, including Super Mario Kart. It does not support GSU (Super FX) games.

## IcePi

Both IcePi Zero and IcePi Zero XL support DSP cartridge add-on chips. IcePi Zero XL also supports the GSU (Super FX) chip, allowing games such as Super Mario World 2: Yoshi's Island and Star Fox to run.

The USB HID controllers run in FPGA gateware; IcePi-Zero has no dedicated USB controller chip for them. Some USB HID devices may therefore be incompatible. Each port supports one device, so USB hubs and composite devices such as combined keyboard/mouse units may not work. Low-speed and full-speed USB 2.0 HID devices are the intended devices. This limitation is also described in the [IcePi-Zero Minimig USB support notes](https://github.com/m1nl/icepi-zero-minimig/blob/main/README.md#usb-support).

On IcePi-Zero, the first player uses the second USB port, the one closer to the PCB edge, for easier physical access. The other USB port is for the second player.

### Controller buttons

Controllers without dedicated Start and Select buttons can use these chords:

| Hold | Press | SNES button |
| --- | --- | --- |
| X + Y | A | Start |
| X + Y | B | Select |

The mapping applies to both players and all controller inputs. Dedicated Start and Select buttons still work. While either chord is held, its face buttons are not sent to the game; directions and shoulder buttons still work.

Press **Select + Right** to open the on-screen display (OSD).

## Changes from the original core

At a high level, the work since [`fbd8217`](https://github.com/m1nl/snestang/compare/fbd8217a7ca9d3c620bd548c8d19c91c71009c3e...mistle) includes:

1. Changed the I/O soft CPU to SERV in its 4-bit QERV mode to reduce FPGA resource use. The I/O system was also refactored and gained streamed ROM loading.
2. Updated the SNES core modules from the upstream [MiSTer SNES core](https://github.com/MiSTer-devel/SNES_MiSTer), keeping the migrated VHDL sources where practical. The 65C816 CPU uses its Verilog implementation because the VHDL version used too many LUTs.
3. Migrated all of nand2mario's improvements, including the existing SNESTang integration and features.
4. Added MiSTle board support and adapted the build, memory, HDMI, and audio paths for Gowin and Lattice ECP5 targets. Simulation was restored for the mixed Verilog/VHDL design.
5. Added an IcePi-Zero project and connected the USB HID host to its USB ports.

## Flashing IcePi-Zero

First, get `firmware.bin` from the [SnesTang firmware repository](https://github.com/m1nl/snestang-firmware) and flash it at offset `0x500000`:

```sh
openFPGALoader -b icepi-zero --write-flash --offset 0x500000 firmware.bin
```

Then flash the IcePi-Zero core bitstream:

```sh
openFPGALoader -b icepi-zero --write-flash path/to/core.bit
```

Replace `path/to/core.bit` with the path to the built bitstream. Flash the firmware before using the core.

## Flashing MiSTle GW5A-25k and MiSTle Tang Nano 20k

Since these use the MiSTle framework and don't use an FPGA embedded MCU, no firmware needs to be flashed. Just the core
bitstream itself has to be installed:

```sh
openFPGALoader path/to/core.fs
```

## Development and credits

The [design notes](doc/design.md) describe the original SNESTang architecture. The [Verilator harness](verilator) provides simulation support.

SNESTang was created by [nand2mario](https://github.com/nand2mario/snestang) as part of [TangCore](https://github.com/nand2mario/tangcore). Its SNES core derives from [SNES_FPGA](https://github.com/gyurco/SNES_FPGA) by Sergiy Dvodnenko (srg320) and gyurco and the [MiSTer SNES core](https://github.com/MiSTer-devel/SNES_MiSTer). HDMI support uses [hdl-util/hdmi](https://github.com/hdl-util/hdmi) by Sameer Puri.
