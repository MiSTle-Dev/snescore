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
		ROM_CE_N		: out std_logic;
		ROM_OE_N		: out std_logic;
		ROM_WORD		: out std_logic;
		ROM_DONE		: in std_logic;
		
		BSRAM_ADDR	: out std_logic_vector(19 downto 0);
		BSRAM_D		: out std_logic_vector(7 downto 0);
		BSRAM_Q		: in  std_logic_vector(7 downto 0);
		BSRAM_CE_N	: out std_logic;
		BSRAM_OE_N	: out std_logic;
		BSRAM_WE_N	: out std_logic;
		BSRAM_RD_N	: out std_logic;
		BSRAM_DONE	: in std_logic;

		MAP_ACTIVE  : out std_logic;
		MAP_CTRL		: in std_logic_vector(7 downto 0);
		ROM_MASK		: in std_logic_vector(23 downto 0);
		BSRAM_MASK	: in std_logic_vector(23 downto 0);

		TURBO		   : in std_logic;

		CPURD_CYC_N	: in std_logic;
		PARD_CYC_N	: in std_logic;

		GSU_RAM_ACCESS	: out std_logic;
		GSU_ROM_ACCESS	: out std_logic
	);
end GSUMap;

architecture rtl of GSUMap is

	signal ROM_A 		: std_logic_vector(20 downto 0);
	signal RAM_A 		: std_logic_vector(16 downto 0);
	signal RAM_WE_N 	: std_logic;
	signal MAP_SEL	  	: std_logic;
	signal GSU_RAM_ACCESS_I		: std_logic;
	signal GSU_ROM_ACCESS_I		: std_logic;
	signal GSU_ROM_CE_N		: std_logic;


	
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
		ROM_DI		=> ROM_Q(7 downto 0),
		ROM_RD_N		=> ROM_OE_N,
		ROM_DONE		=> ROM_DONE,
		
		RAM_A			=> RAM_A,
		RAM_DI		=> BSRAM_Q,
		RAM_DO		=> BSRAM_D,
		RAM_WE_N		=> RAM_WE_N,
		RAM_CE_N		=> BSRAM_CE_N,
		RAM_DONE		=> BSRAM_DONE,
				
		TURBO			=> TURBO,

		GSU_RAM_ACCESS_O	=> GSU_RAM_ACCESS_I,

		GSU_ROM_ACCESS_O	=> GSU_ROM_ACCESS_I,
		GSU_ROM_CE_N		=> GSU_ROM_CE_N
	);
	
	ROM_ADDR 	<= ("00" & ROM_A) and ROM_MASK(22 downto 0);
	ROM_CE_N 	<= ROMSEL_N when GSU_ROM_ACCESS_I = '0' else GSU_ROM_CE_N;

	ROM_WORD	<= '0';
	
	BSRAM_ADDR 	<= "0000" & RAM_A(15 downto 0);
	BSRAM_OE_N 	<= not RAM_WE_N;
	BSRAM_WE_N 	<= RAM_WE_N;
	BSRAM_RD_N	<= (CPURD_CYC_N and PARD_CYC_N) when GSU_RAM_ACCESS_I = '0' else not RAM_WE_N;
	
	GSU_RAM_ACCESS <= GSU_RAM_ACCESS_I and MAP_SEL;
	GSU_ROM_ACCESS <= GSU_ROM_ACCESS_I and MAP_SEL;

end rtl;
