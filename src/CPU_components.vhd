library ieee;
use ieee.std_logic_1164.all;

-- Component binding supports CPU.v for mixed-language synthesis and CPU.vhd
-- for VHDL simulation. Compile exactly one SCPU implementation.
package CPU_components is
    component SCPU is
        port (
            CLK : in std_logic;
            RST_N : in std_logic;
            ENABLE : in std_logic;
            CA : out std_logic_vector(23 downto 0);
            CPURD_N : out std_logic;
            CPUWR_N : out std_logic;
            CPURD_CYC_N : out std_logic;
            PARD_CYC_N : out std_logic;
            DOT_CLK_CE_O : out std_logic;
            PA : out std_logic_vector(7 downto 0);
            PARD_N : out std_logic;
            PAWR_N : out std_logic;
            DI : in std_logic_vector(7 downto 0);
            DO : out std_logic_vector(7 downto 0);
            RAMSEL_N : out std_logic;
            ROMSEL_N : out std_logic;
            JPIO67 : out std_logic_vector(7 downto 6);
            REFRESH : out std_logic;
            SYSCLK : out std_logic;
            SYSCLKF_CE : out std_logic;
            SYSCLKR_CE : out std_logic;
            HBLANK : in std_logic;
            VBLANK : in std_logic;
            IRQ_N : in std_logic;
            JOY1_DI : in std_logic_vector(1 downto 0);
            JOY2_DI : in std_logic_vector(1 downto 0);
            JOY_STRB : out std_logic;
            JOY1_CLK : out std_logic;
            JOY2_CLK : out std_logic;
            TURBO : in std_logic;
            DBG_CPU_EN : in std_logic
        );
    end component;
end package CPU_components;
