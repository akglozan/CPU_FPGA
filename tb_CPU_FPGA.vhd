library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;

entity tb_CPU_FPGA is
-- Empty entity! No inputs or outputs.
end entity tb_CPU_FPGA;

architecture Behavior of tb_CPU_FPGA is

    component CPU_FPGA is
        port (
            clk             : in  std_logic;
            rst             : in  std_logic;
            pc_write        : in  std_logic;
            pc_src          : in  std_logic;
            pc_out          : out std_logic_vector(31 downto 0);
            instruction_out : out std_logic_vector(31 downto 0)
        );
    end component CPU_FPGA;
	 
	 -- Inputs to UUT (initialized)
    signal tb_clk      : std_logic := '0';
    signal tb_rst      : std_logic := '1'; -- Start in reset
    signal tb_pc_write : std_logic := '0';
    signal tb_pc_src   : std_logic := '0';

    -- Outputs from UUT
    signal tb_pc_out          : std_logic_vector(31 downto 0);
    signal tb_instruction_out : std_logic_vector(31 downto 0);
	 
	 constant CLK_PERIOD : time := 20 ns;
	 
	 
	 begin

    -- Instantiate Unit Under Test
    uut: CPU_FPGA
        port map (
            clk             => tb_clk,
            rst             => tb_rst,
            pc_write        => tb_pc_write,
            pc_src          => tb_pc_src,
            pc_out          => tb_pc_out,
            instruction_out => tb_instruction_out
        );
		  
		  -- Clock Generation Process (50 MHz)
    clk_process : process
    begin
        tb_clk <= '0';
        wait for CLK_PERIOD / 2;
        tb_clk <= '1';
        wait for CLK_PERIOD / 2;
    end process;
	 
	 
	 
	 stim_proc : process
	 begin
			-- 1. Initial Reset Phase
    tb_rst <= '1';
    tb_pc_write <= '0';
    wait for CLK_PERIOD * 2;

    -- 2. Enable Normal Execution
    tb_rst <= '0';
    tb_pc_write <= '1';
    wait for CLK_PERIOD * 5;

    -- 3. Simulate Pipeline Stall (pc_write = 0)
    tb_pc_write <= '0';
    wait for CLK_PERIOD * 2;

    -- 4. Resume Normal Execution
    tb_pc_write <= '1';
    wait for CLK_PERIOD * 3;

    -- 5. End Simulation
    wait;
	 end process;
			
end architecture Behavior;
			