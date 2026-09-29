library STD;
use STD.TEXTIO.ALL;
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;
use IEEE.STD_LOGIC_TEXTIO.all;

entity GSUMap is
	port(
		MCLK			: in std_logic;
		RST_N			: in std_logic;
		ENABLE		: in std_logic := '1';
		
		CA   			: in std_logic_vector(23 downto 0);
		DI				: in std_logic_vector(7 downto 0);
		DO				: out std_logic_vector(7 downto 0);
		CPURD_N		: in std_logic;
		CPUWR_N		: in std_logic;
		
		PA				: in std_logic_vector(7 downto 0);
		PARD_N		: in std_logic;
		PAWR_N		: in std_logic;
		
		ROMSEL_N		: in std_logic;
		RAMSEL_N		: in std_logic;
		
		SYSCLKF_CE	: in std_logic;
		SYSCLKR_CE	: in std_logic;
		REFRESH		: in std_logic;
		
		IRQ_N			: out std_logic;

		ROM_ADDR		: out std_logic_vector(22 downto 0);
		ROM_Q			: in  std_logic_vector(15 downto 0);
		GSU_ROM_Q	: in  std_logic_vector(7 downto 0);
		ROM_CE_N		: out std_logic;
		ROM_OE_N		: out std_logic;
		ROM_WORD		: out std_logic;
		
		BSRAM_ADDR	: out std_logic_vector(19 downto 0);
		BSRAM_D		: out std_logic_vector(7 downto 0);
		BSRAM_Q		: in  std_logic_vector(7 downto 0);
		BSRAM_CE_N	: out std_logic;
		BSRAM_OE_N	: out std_logic;
		BSRAM_WE_N	: out std_logic;

		MAP_ACTIVE  : out std_logic;
		MAP_CTRL		: in std_logic_vector(7 downto 0);
		ROM_MASK		: in std_logic_vector(23 downto 0);
		BSRAM_MASK	: in std_logic_vector(23 downto 0);

		TURBO		   : in std_logic;
		ROM_REQ     : out std_logic;
		ROM_OWNED   : out std_logic;
		ROM_ACCEPT  : in std_logic;
		ROM_DONE    : in std_logic
	);
end GSUMap;

architecture rtl of GSUMap is

	signal ROM_A 		: std_logic_vector(20 downto 0);
	signal ROM_DI_MUX : std_logic_vector(7 downto 0);
	signal ROM_REQ_I : std_logic;
	signal ROM_OWNED_I : std_logic;
	signal RAM_A 		: std_logic_vector(16 downto 0);
	signal RAM_WE_N 	: std_logic;
	signal MAP_SEL	  	: std_logic;
	
begin

	MAP_SEL <= '1' when MAP_CTRL(7 downto 4) = X"7" else '0';
	MAP_ACTIVE <= MAP_SEL;
	
	GSU : entity work.GSU
	port map(
		CLK			=> MCLK,
		RST_N			=> RST_N,
		ENABLE		=> ENABLE,

		ADDR			=> CA,
		DO				=> DO,
		DI				=> DI,
		RD_N			=> CPURD_N,
		WR_N			=> CPUWR_N,
		
		SYSCLKF_CE	=> SYSCLKF_CE,
		SYSCLKR_CE	=> SYSCLKR_CE,
		
		IRQ_N			=> IRQ_N,
		
		ROM_A			=> ROM_A,
		ROM_DI		=> ROM_DI_MUX,
		ROM_RD_N		=> ROM_OE_N,
		
		RAM_A			=> RAM_A,
		RAM_DI		=> BSRAM_Q,
		RAM_DO		=> BSRAM_D,
		RAM_WE_N		=> RAM_WE_N,
		RAM_CE_N		=> BSRAM_CE_N,
				
		TURBO			=> TURBO,
		ROM_REQ     => ROM_REQ_I,
		ROM_OWNED   => ROM_OWNED_I,
		ROM_ACCEPT  => ROM_ACCEPT,
		ROM_DONE    => ROM_DONE
	);
	ROM_REQ <= ROM_REQ_I and MAP_SEL;
	ROM_OWNED <= ROM_OWNED_I and MAP_SEL;
	ROM_DI_MUX <= GSU_ROM_Q when ROM_OWNED_I = '1' else ROM_Q(7 downto 0);
	
	ROM_ADDR 	<= ("00" & ROM_A) and ROM_MASK(22 downto 0);
	-- GSU-owned fetches use the dedicated SDRAM request channel.
	ROM_CE_N 	<= ROM_OWNED_I;
	ROM_WORD		<= '0';
	
	BSRAM_ADDR 	<= "0000" & RAM_A(15 downto 0);
	BSRAM_OE_N 	<= not RAM_WE_N;
	BSRAM_WE_N 	<= RAM_WE_N;
	
end rtl;
