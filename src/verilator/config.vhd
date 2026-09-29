library ieee;
use ieee.std_logic_1164.all;

package board_config is
    type vendor_t is (VENDOR_LATTICE, VENDOR_GOWIN);
    constant VENDOR : vendor_t := VENDOR_LATTICE;  -- Lattice is more generic
    constant BSRAM_BRAM : boolean := true;
    constant CHIP_GSU : boolean := true;
    constant SNES_FREQ : integer := 21_484_400;
end package board_config;

package body board_config is
end package body board_config;
