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

entity M_Extension_Unit_tb is
end entity;

architecture Testbench of M_Extension_Unit_tb is

    -- Component Declaration
    component M_Extension_Unit
        port(
            clk        : in  std_logic;
            rst_n      : in  std_logic;
            is_m_ext   : in  std_logic;
            funct3     : in  std_logic_vector(2 downto 0);
            operand_a  : in  std_logic_vector(31 downto 0);
            operand_b  : in  std_logic_vector(31 downto 0);
            m_result   : out std_logic_vector(31 downto 0);
            stall_m    : out std_logic
        );
    end component;

    -- Testbench Signals
    signal clk        : std_logic := '0';
    signal rst_n      : std_logic := '0';
    signal is_m_ext   : std_logic := '0';
    signal funct3     : std_logic_vector(2 downto 0) := "000";
    signal operand_a  : std_logic_vector(31 downto 0) := (others => '0');
    signal operand_b  : std_logic_vector(31 downto 0) := (others => '0');
    signal m_result   : std_logic_vector(31 downto 0);
    signal stall_m    : std_logic;

    constant CLK_PERIOD : time := 20 ns;

begin

    -- Instantiate Device Under Test (DUT)
    uut: M_Extension_Unit
        port map (
            clk       => clk,
            rst_n     => rst_n,
            is_m_ext  => is_m_ext,
            funct3    => funct3,
            operand_a => operand_a,
            operand_b => operand_b,
            m_result  => m_result,
            stall_m   => stall_m
        );

    -- Clock Generation Process
    clk_process : process
    begin
        clk <= '0';
        wait for CLK_PERIOD / 2;
        clk <= '1';
        wait for CLK_PERIOD / 2;
    end process;

    -- Stimulus Process
    stim_proc: process
    begin
        -- 1. System Reset
        rst_n <= '1';
        wait for CLK_PERIOD * 2;
        rst_n <= '0';
        wait for CLK_PERIOD;

        --------------------------------------------------------------------
        -- TEST CASE 1: Standard Multiplication (MUL: 10 * 5 = 50)
        --------------------------------------------------------------------
        operand_a <= std_logic_vector(to_signed(10, 32));
        operand_b <= std_logic_vector(to_signed(5, 32));
        funct3    <= "000"; -- MUL
        is_m_ext  <= '1';
        wait for CLK_PERIOD;
        assert m_result = std_logic_vector(to_signed(50, 32))
            report "Error: MUL Failed!" severity error;

        --------------------------------------------------------------------
        -- TEST CASE 2: Signed Upper Multiplication (MULH: -2 * 2)
        --------------------------------------------------------------------
        operand_a <= std_logic_vector(to_signed(-2, 32));
        operand_b <= std_logic_vector(to_signed(2, 32));
        funct3    <= "001"; -- MULH
        wait for CLK_PERIOD;
        assert m_result = x"FFFFFFFF"
            report "Error: MULH Failed!" severity error;

        --------------------------------------------------------------------
        -- TEST CASE 3: Signed Division (DIV: 20 / 3 = 6)
        --------------------------------------------------------------------
        operand_a <= std_logic_vector(to_signed(20, 32));
        operand_b <= std_logic_vector(to_signed(3, 32));
        funct3    <= "100"; -- DIV
        
        wait until rising_edge(stall_m);  -- Wait for stall signal to go HIGH
        wait until falling_edge(stall_m); -- Wait for multi-cycle division completion
        wait for 1 ns;                     -- Sample settled outputs after clock edge
        assert m_result = std_logic_vector(to_signed(6, 32))
            report "Error: DIV 20/3 Failed!" severity error;

			--------------------------------------------------------------------
			-- TEST CASE 4: Signed Remainder with Negative Dividend (REM: -20 % 3 = -2)
			--------------------------------------------------------------------
			operand_a <= std_logic_vector(to_signed(-20, 32));
			operand_b <= std_logic_vector(to_signed(3, 32));
			funct3    <= "110"; -- REM

			wait until rising_edge(stall_m);  -- Wait for stall to go HIGH
			wait until falling_edge(stall_m); -- Wait for stall to go LOW
			wait until rising_edge(clk);      -- Wait 1 clock edge for registered negation to settle
			wait for 1 ns;                     -- Sample settled output

			assert m_result = std_logic_vector(to_signed(-2, 32))
			report "Error: REM -20%3 Failed!" severity error;

        --------------------------------------------------------------------
        -- TEST CASE 5: Exception - Division by Zero (DIV: 100 / 0 = 0xFFFFFFFF)
        --------------------------------------------------------------------
        operand_a <= std_logic_vector(to_signed(100, 32));
        operand_b <= std_logic_vector(to_signed(0, 32));
        funct3    <= "100"; -- DIV
        
        wait until rising_edge(stall_m);
        wait until falling_edge(stall_m);
        wait for 1 ns;
        assert m_result = x"FFFFFFFF"
            report "Error: Division by Zero Quotient Failed!" severity error;

        --------------------------------------------------------------------
        -- TEST CASE 6: Exception - Signed Overflow (-2^31 / -1 = 0x80000000)
        --------------------------------------------------------------------
        operand_a <= x"80000000"; -- -2^31
        operand_b <= x"FFFFFFFF"; -- -1
        funct3    <= "100"; -- DIV
        
        wait until rising_edge(stall_m);
        wait until falling_edge(stall_m);
        wait for 1 ns;
        assert m_result = x"80000000"
            report "Error: Signed Overflow Failed!" severity error;

        -- End Simulation
        is_m_ext <= '0';
        report "ALL M-EXTENSION TESTS PASSED SUCCESSFULLY!" severity note;
        wait;
    end process;

end architecture;