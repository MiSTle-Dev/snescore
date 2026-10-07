// `define LATTICE
`define GOWIN
`define NANO

`define SDRAM_3CH
// `define BSRAM_BRAM
`define CHIP_DSPn
// `define CHIP_GSU

// enable the individual controller interfaces
// `define CONTROLLER_SNES
// `define CONTROLLER_DS2
// `define CONTROLLER_USB_HID  // requires a board-specific 60 MHz uclk connection

// enable the mistle framework (incl. its controller ports)
`define MISTLE

`define SDRAM_DATA_WIDTH 32
`define SDRAM_ROW_WIDTH 11
// `define SDRAM_16M

`define SNES_FREQ 21_484_400
`define PIXEL_FREQ 74_250_000

// `define S0_N
// `define S1_N
`define LED_N
