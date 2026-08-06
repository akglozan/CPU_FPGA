library IEEE;
use IEEE.STD_LOGIC_1164.all;

entity Board_Top is
    port (
        clk : in std_logic;
        rst : in std_logic
    );
end entity Board_Top;

architecture Structural of Board_Top is

    component CPU_FPGA is
        generic (
            DATA_WIDTH : integer := 32
        );
        port (
            clk         : in  std_logic;
            rst         : in  std_logic;
            pc_debug    : out std_logic_vector(31 downto 0);
            instr_debug : out std_logic_vector(31 downto 0);
            rs1_debug   : out std_logic_vector(31 downto 0);
            rs2_debug   : out std_logic_vector(31 downto 0)
        );
    end component;

    -- Internal dummy debug signals (prevents Quartus IO pin mapping)
    signal pc_debug_int    : std_logic_vector(31 downto 0);
    signal instr_debug_int : std_logic_vector(31 downto 0);
    signal rs1_debug_int   : std_logic_vector(31 downto 0);
    signal rs2_debug_int   : std_logic_vector(31 downto 0);

begin

    U_CPU : CPU_FPGA
        generic map (
            DATA_WIDTH => 32
        )
        port map (
            clk         => clk,
            rst         => rst,
            pc_debug    => pc_debug_int,
            instr_debug => instr_debug_int,
            rs1_debug   => rs1_debug_int,
            rs2_debug   => rs2_debug_int
        );

end architecture Structural;