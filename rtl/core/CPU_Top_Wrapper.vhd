library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;

entity CPU_Top_Wrapper is
    port (
        clk           : in  std_logic;                      -- Physical Board Clock
        rst           : in  std_logic;                      -- Physical Reset Switch
        debug_sel     : in  std_logic_vector(1 downto 0);   -- MUX Select (Switches)
        led_out       : out std_logic_vector(7 downto 0)    -- 8 Onboard Diagnostic LEDs
    );
end entity CPU_Top_Wrapper;

architecture Structural of CPU_Top_Wrapper is

    component CPU_FPGA is
        generic ( DATA_WIDTH : integer := 32 );
        port (
            clk         : in  std_logic;
            rst         : in  std_logic;
            pc_debug    : out std_logic_vector(31 downto 0);
            instr_debug : out std_logic_vector(31 downto 0);
            rs1_debug   : out std_logic_vector(31 downto 0);
            rs2_debug   : out std_logic_vector(31 downto 0)
        );
    end component;

    signal pc_dbg    : std_logic_vector(31 downto 0);
    signal instr_dbg : std_logic_vector(31 downto 0);
    signal rs1_dbg   : std_logic_vector(31 downto 0);
    signal rs2_dbg   : std_logic_vector(31 downto 0);

begin

    -- Instantiate the Core Processor
    U_CPU : CPU_FPGA
        port map (
            clk         => clk,
            rst         => rst,
            pc_debug    => pc_dbg,
            instr_debug => instr_dbg,
            rs1_debug   => rs1_dbg,
            rs2_debug   => rs2_dbg
        );

    -- Time-Multiplex 128 Bits down to 8 Output Pins
    process(debug_sel, pc_dbg, instr_dbg, rs1_dbg, rs2_dbg)
    begin
        case debug_sel is
            when "00"   => led_out <= pc_dbg(7 downto 0);        -- Low byte of PC
            when "01"   => led_out <= instr_dbg(7 downto 0);     -- Low byte of Instruction
            when "10"   => led_out <= rs1_dbg(7 downto 0);       -- Low byte of RS1
            when "11"   => led_out <= rs2_dbg(7 downto 0);       -- Low byte of RS2
            when others => led_out <= (others => '0');
        end case;
    end process;

end architecture Structural;