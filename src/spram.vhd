library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.std_logic_textio.all;
library std;
use std.textio.all;
library work;
use work.board_config.all;

entity spram_sz is
	generic (
		ADDR_WIDTH    : integer := 8;
		DATA_WIDTH    : integer := 8;
		NUMWORDS      : integer := 2 ** 8;
		MEM_INIT_FILE : string := "";
		MEM_NAME      : string := "MEM"
	);
	port (
		clock   : in  std_logic;
		address : in  std_logic_vector(ADDR_WIDTH - 1 downto 0);
		data    : in  std_logic_vector(DATA_WIDTH - 1 downto 0) := (others => '0');
		enable  : in  std_logic := '1';
		wren    : in  std_logic := '0';
		q       : out std_logic_vector(DATA_WIDTH - 1 downto 0);
		cs      : in  std_logic := '1'
	);
end entity spram_sz;

architecture rtl of spram_sz is
	type ram_t is array (0 to NUMWORDS - 1) of
		std_logic_vector(DATA_WIDTH - 1 downto 0);

	impure function init_ram_hex(file_name : string) return ram_t is
		file init_file       : text;
		variable open_status : file_open_status;
		variable input_line  : line;
		variable word        : std_logic_vector(DATA_WIDTH - 1 downto 0);
		variable good        : boolean;
		variable init_addr   : natural := 0;
		variable result      : ram_t := (others => (others => '0'));
	begin
		if file_name'length > 0 then
			file_open(open_status, init_file, file_name, read_mode);
			assert open_status = open_ok
				report "Unable to open RAM initialization file " & file_name
				severity failure;

			for addr in 0 to NUMWORDS-1 loop
				exit when endfile(init_file);

				readline(init_file, input_line);
				hread(input_line, word, good);
				exit when not good;

				result(init_addr) := word;
				init_addr := init_addr + 1;
			end loop;

			file_close(init_file);
		end if;
		return result;
	end function;

	signal mem : ram_t := init_ram_hex(MEM_INIT_FILE);

	attribute syn_ramstyle : string;
	attribute syn_ramstyle of mem : signal is "block_ram";
begin
	process (clock)
	begin
		if rising_edge(clock) then
			if enable = '1' then
				if cs = '1' and wren = '1' then
					mem(to_integer(unsigned(address))) <= data;
				end if;
				if cs = '0' or wren = '0' or VENDOR /= VENDOR_GOWIN then
					q <= mem(to_integer(unsigned(address)));
				end if;
			end if;
		end if;
	end process;
end architecture rtl;

library ieee;
use ieee.std_logic_1164.all;

entity spram is
	generic (
		ADDR_WIDTH    : integer := 8;
		DATA_WIDTH    : integer := 8;
		MEM_INIT_FILE : string := "";
		MEM_NAME      : string := "MEM"
	);
	port (
		clock   : in  std_logic;
		address : in  std_logic_vector(ADDR_WIDTH - 1 downto 0);
		data    : in  std_logic_vector(DATA_WIDTH - 1 downto 0) := (others => '0');
		enable  : in  std_logic := '1';
		wren    : in  std_logic := '0';
		q       : out std_logic_vector(DATA_WIDTH - 1 downto 0);
		cs      : in  std_logic := '1'
	);
end entity spram;

architecture rtl of spram is
begin
	ram : entity work.spram_sz
		generic map (ADDR_WIDTH, DATA_WIDTH, 2 ** ADDR_WIDTH, MEM_INIT_FILE, MEM_NAME)
		port map (clock, address, data, enable, wren, q, cs);
end architecture rtl;
