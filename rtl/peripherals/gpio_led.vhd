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

-- 4-bit GPIO output peripheral. Latches the low 4 bits of an MMIO
-- write into a register that drives the board's LEDs directly.
entity gpio_led is

	port(
		clk 	:	in std_logic;
		-- Active-low synchronous reset.
		rst_n	:	in std_logic;
		--Write Enable Strobe
		we		:	in std_logic;
		--CPU Write Data
		wdata	:	in std_logic_vector(31 downto 0);
		
		led_out	: out std_logic_vector(3 downto 0)--Have 4 leds available on the board, can be upgraded
			
	);
end entity;


architecture Behavioral of gpio_led is
	
	signal led_reg	: std_logic_vector(3 downto 0);
	
begin 

process(clk)

begin

	if rising_edge(clk) then
		if rst_n = '0' then
			led_reg <= (others => '0');
		elsif we = '1' then
			led_reg <= wdata(3 downto 0);
		end if;
	end if;
end process;

led_out <= led_reg;

end architecture Behavioral;