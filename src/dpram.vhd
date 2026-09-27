library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
library work;
use work.board_config.all;

entity dpram is
	generic (
		ADDR_WIDTH : integer := 7;
		DATA_WIDTH : integer := 8
	);
	port (
		clock     : in  std_logic;
		data_a    : in  std_logic_vector(DATA_WIDTH - 1 downto 0);
		data_b    : in  std_logic_vector(DATA_WIDTH - 1 downto 0);
		address_a : in  std_logic_vector(ADDR_WIDTH - 1 downto 0);
		address_b : in  std_logic_vector(ADDR_WIDTH - 1 downto 0);
		wren_b    : in  std_logic;
		wren_a    : in  std_logic;
		q_a       : out std_logic_vector(DATA_WIDTH - 1 downto 0);
		q_b       : out std_logic_vector(DATA_WIDTH - 1 downto 0)
	);
end entity dpram;

architecture rtl of dpram is
	type ram_t is array (0 to (2 ** ADDR_WIDTH) - 1) of std_logic_vector(DATA_WIDTH - 1 downto 0);
	signal mem : ram_t;

	attribute syn_ramstyle : string;
	attribute syn_ramstyle of mem : signal is "block_ram";
begin
	process (clock)
	begin
		if rising_edge(clock) then
			if wren_a = '1' then
				mem(to_integer(unsigned(address_a))) <= data_a;
			end if;
			if wren_a = '0' or VENDOR /= VENDOR_GOWIN then
				q_a <= mem(to_integer(unsigned(address_a)));
			end if;
		end if;
	end process;

	process (clock)
	begin
		if rising_edge(clock) then
			if wren_b = '1' then
				mem(to_integer(unsigned(address_b))) <= data_b;
			end if;
			if wren_b = '0' or VENDOR /= VENDOR_GOWIN then
				q_b <= mem(to_integer(unsigned(address_b)));
			end if;
		end if;
	end process;
end architecture rtl;
