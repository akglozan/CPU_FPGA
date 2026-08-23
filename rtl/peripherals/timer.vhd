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

-- Free-running 32-bit up-counter peripheral, incrementing by one every
-- clock cycle. Read-only; provides a simple cycle-counter / timestamp
-- source for firmware.
entity timer is

	port(
	
		clk		:	in std_logic;
		-- Active-low synchronous reset; clears the counter to zero.
		rst_n		: 	in std_logic;
		
		-- Current free-running counter value.
		timer_rdata	: out std_logic_vector(31 downto 0)
	
	);


end entity;

architecture Behavioral of timer is

	signal counter_reg : unsigned(31 downto 0);

begin

process(clk)
begin

	if rising_edge(clk) then
		if rst_n = '0' then
			counter_reg <= (others => '0');
		else
		counter_reg <= counter_reg + 1;
		end if;
	end if;

end process;

timer_rdata <= std_logic_vector(counter_reg);

end architecture;
