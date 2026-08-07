library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;

entity tb_CPU_FPGA is
end entity tb_CPU_FPGA;

architecture Behavioral of tb_CPU_FPGA is

    -------------------------------------------------------------------
    -- Constants & Simulation Parameters
    -------------------------------------------------------------------
    constant DATA_WIDTH : integer := 32;
    constant CLK_PERIOD : time    := 20 ns; -- 50 MHz Clock Frequency

    -------------------------------------------------------------------
    -- Component Declaration
    -------------------------------------------------------------------
    component CPU_FPGA is
        generic (
            DATA_WIDTH : integer := 32
        );
        port (
            clk         : in  std_logic;
            rst         : in  std_logic;
            pc_debug    : out std_logic_vector(DATA_WIDTH-1 downto 0);
            instr_debug : out std_logic_vector(DATA_WIDTH-1 downto 0);
            rs1_debug   : out std_logic_vector(DATA_WIDTH-1 downto 0);
            rs2_debug   : out std_logic_vector(DATA_WIDTH-1 downto 0)
        );
    end component;

    -------------------------------------------------------------------
    -- UUT Interface Signals
    -------------------------------------------------------------------
    signal clk         : std_logic := '0';
    signal rst         : std_logic := '1';
    signal pc_debug    : std_logic_vector(DATA_WIDTH-1 downto 0);
    signal instr_debug : std_logic_vector(DATA_WIDTH-1 downto 0);
    signal rs1_debug   : std_logic_vector(DATA_WIDTH-1 downto 0);
    signal rs2_debug   : std_logic_vector(DATA_WIDTH-1 downto 0);

    signal sim_finished : boolean := false;

begin

    -------------------------------------------------------------------
    -- Unit Under Test (UUT) Instantiation
    -------------------------------------------------------------------
    UUT : CPU_FPGA
        generic map (
            DATA_WIDTH => DATA_WIDTH
        )
        port map (
            clk         => clk,
            rst         => rst,
            pc_debug    => pc_debug,
            instr_debug => instr_debug,
            rs1_debug   => rs1_debug,
            rs2_debug   => rs2_debug
        );

    -------------------------------------------------------------------
    -- Clock Generation Process (50 MHz)
    -------------------------------------------------------------------
    clk_process : process
    begin
        while not sim_finished loop
            clk <= '0';
            wait for CLK_PERIOD / 2;
            clk <= '1';
            wait for CLK_PERIOD / 2;
        end loop;
        wait;
    end process;

    -------------------------------------------------------------------
    -- Stimulus & Reset Sequence Process
    -------------------------------------------------------------------
    stim_process : process
    begin
        -- Assert Active-High Reset
        rst <= '1';
        wait for 100 ns;
        
        -- De-assert Reset
        rst <= '0';
        
        -- Execution timeout threshold
        wait for 10000 ns;
        
        sim_finished <= true;
        report "Simulation timeout reached." severity note;
        wait;
    end process;

    -------------------------------------------------------------------
    -- Execution Monitor & Halt Detection Process
    -------------------------------------------------------------------
    monitor_process : process(clk)
    begin
        if rising_edge(clk) then
            if rst = '0' then
                -- VHDL-93 compliant assertion halt for ModelSim/GHDL
                if instr_debug = x"0000006f" then
                    assert false report "Halt instruction (0x0000006f) detected. Terminating simulation." severity failure;
                end if;
            end if;
        end if;
    end process;

end architecture Behavioral;