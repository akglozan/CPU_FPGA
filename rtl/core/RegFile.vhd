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

entity RegFile is
    port (
        clk       : in  std_logic;
        rst_n     : in  std_logic;
        reg_write : in  std_logic;
        rd_addr   : in  std_logic_vector(4 downto 0);
        rs1_addr  : in  std_logic_vector(4 downto 0);
        rs2_addr  : in  std_logic_vector(4 downto 0);
        rd_data   : in  std_logic_vector(31 downto 0);
        rs1_data  : out std_logic_vector(31 downto 0);
        rs2_data  : out std_logic_vector(31 downto 0)
    );
end entity RegFile;

architecture Behavioral of RegFile is

    type reg_array is array(0 to 31) of std_logic_vector(31 downto 0);
    signal registers : reg_array := (others => (others => '0'));

begin

    -- Synchronous Write Process with Active-Low Reset (rst_n = '0')
    process(clk)
    begin
        if rising_edge(clk) then
            if rst_n = '0' then
                registers <= (others => (others => '0'));
            elsif reg_write = '1' and rd_addr /= "00000" then
                registers(to_integer(unsigned(rd_addr))) <= rd_data;
            end if;
        end if;
    end process;
    
    -- Asynchronous Read with Write-Bypass Forwarding for RAW Hazard Resolution
    rs1_data <= x"00000000" when rs1_addr = "00000" else
                rd_data     when (reg_write = '1' and rd_addr = rs1_addr) else
                registers(to_integer(unsigned(rs1_addr)));

    rs2_data <= x"00000000" when rs2_addr = "00000" else
                rd_data     when (reg_write = '1' and rd_addr = rs2_addr) else
                registers(to_integer(unsigned(rs2_addr)));

end architecture Behavioral;