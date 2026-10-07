library ieee;
use ieee.std_logic_1164.all;

package board_config is

    type vendor_t is (
        VENDOR_LATTICE,
        VENDOR_GOWIN
    );

    constant VENDOR : vendor_t := VENDOR_LATTICE;

    constant MCU_SERV : boolean := true;

    constant SDRAM_3CH : boolean := true;
    constant BSRAM_BRAM : boolean := false;
    constant CHIP_DSPn : boolean := true;
    constant CHIP_GSU  : boolean := false;
    constant DSP1_ROM_LIMIT : boolean := false;

    constant CONTROLLER_SNES   : boolean := false;
    constant CONTROLLER_DS2    : boolean := false;
    constant CONTROLLER_MISTLE : boolean := true;

    constant SDRAM_DATA_WIDTH : integer := 16;
    constant SDRAM_ROW_WIDTH  : integer := 13;
    constant SDRAM_16M        : boolean := false;

    constant SNES_FREQ  : integer := 21_428_600;
    constant PIXEL_FREQ : integer := 74_174_400;

    constant S0_N : boolean := true;
    constant LED_N : boolean := false;

end package board_config;

package body board_config is
end package body board_config;
