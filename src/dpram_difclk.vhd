library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
library work;
use work.board_config.all;

entity dpram_difclk is
    generic (
        ADDR_WIDTH : integer := 7;
        DATA_WIDTH : integer := 8
    );
    port (
        clock0    : in  std_logic;
        clock1    : in  std_logic;
        data_a    : in  std_logic_vector(DATA_WIDTH - 1 downto 0);
        data_b    : in  std_logic_vector(DATA_WIDTH - 1 downto 0);
        address_a : in  std_logic_vector(ADDR_WIDTH - 1 downto 0);
        address_b : in  std_logic_vector(ADDR_WIDTH - 1 downto 0);
        wren_b    : in  std_logic;
        wren_a    : in  std_logic;
        q_a       : out std_logic_vector(DATA_WIDTH - 1 downto 0);
        q_b       : out std_logic_vector(DATA_WIDTH - 1 downto 0)
    );
end entity dpram_difclk;

architecture rtl of dpram_difclk is
    type ram_t is array (0 to (2 ** ADDR_WIDTH) - 1)
        of std_logic_vector(DATA_WIDTH - 1 downto 0);

    shared variable mem : ram_t;
begin

    gen_gowin : if VENDOR = VENDOR_GOWIN generate

        process (clock0)
        begin
            if rising_edge(clock0) then
                if wren_a = '1' then
                    mem(to_integer(unsigned(address_a))) := data_a;
                else
                    q_a <= mem(to_integer(unsigned(address_a)));
                end if;
            end if;
        end process;

        process (clock1)
        begin
            if rising_edge(clock1) then
                if wren_b = '1' then
                    mem(to_integer(unsigned(address_b))) := data_b;
                else
                    q_b <= mem(to_integer(unsigned(address_b)));
                end if;
            end if;
        end process;

    end generate;


    gen_other : if VENDOR /= VENDOR_GOWIN generate

        process (clock0)
        begin
            if rising_edge(clock0) then
                if wren_a = '1' then
                    mem(to_integer(unsigned(address_a))) := data_a;
                end if;

                q_a <= mem(to_integer(unsigned(address_a)));
            end if;
        end process;

        process (clock1)
        begin
            if rising_edge(clock1) then
                if wren_b = '1' then
                    mem(to_integer(unsigned(address_b))) := data_b;
                end if;

                q_b <= mem(to_integer(unsigned(address_b)));
            end if;
        end process;

    end generate;

end architecture rtl;
