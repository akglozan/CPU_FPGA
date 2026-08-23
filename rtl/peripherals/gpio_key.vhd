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

-- 4-button GPIO input peripheral. Double-flops the raw asynchronous
-- key inputs onto the system clock (a standard 2-stage synchronizer)
-- to avoid metastability, and exposes the synchronized value
-- zero-extended to a 32-bit MMIO read word.
entity gpio_key is

	port(
		clk 	:	in std_logic;
		-- Active-low synchronous reset.
		rst_n	:	in std_logic;
		-- Raw, asynchronous button inputs.
		key_in:	in std_logic_vector(3 downto 0);
		
		-- Synchronized key state, zero-extended to 32 bits.
		key_rdata	: out std_logic_vector(31 downto 0)
		
		
	);
end entity;


architecture Behavioral of gpio_key is

		signal key_sync1	: std_logic_vector(3 downto 0);
		signal key_sync2	: std_logic_vector(3 downto 0);

	
begin 

process(clk)

begin
	
	if rising_edge(clk) then
		if rst_n = '0' then
			key_sync1 <= (others => '0');--da vedere i valori rispetto ai pulsanti
			key_sync2 <= (others => '0');
		else 
		key_sync1 <= key_in;
		key_sync2 <= key_sync1;
		end if;
	end if;
		

end process;

key_rdata <= (31 downto 4 => '0') & key_sync2; 

end architecture Behavioral;