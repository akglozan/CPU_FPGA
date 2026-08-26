-- SPDX-License-Identifier: Apache-2.0
-- Copyright 2026 Ozan Akgül
--
-- Licensed under the Apache License, Version 2.0 (the "License");
-- you may not use this file except in compliance with the License.
-- You may obtain a copy of the License at
--
--     http://www.apache.org/licenses/LICENSE-2.0
--
-- Unless required by applicable law or agreed to in writing, software
-- distributed under the License is distributed on an "AS IS" BASIS,
-- WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
-- See the License for the specific language governing permissions and
-- limitations under the License.

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
            rst_n         : in  std_logic;
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
    signal rst_n         : std_logic := '1';
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
            rst_n         => rst_n,
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
        -- Assert Active-Low Reset
        rst_n <= '0';
        wait for 100 ns;
        
        -- De-assert Reset
        rst_n <= '1';
        
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
            if rst_n = '0' then
                -- VHDL-93 compliant assertion halt for ModelSim/GHDL
                if instr_debug = x"0000006f" then
                    assert false report "Halt instruction (0x0000006f) detected. Terminating simulation." severity failure;
                end if;
            end if;
        end if;
    end process;

end architecture Behavioral;