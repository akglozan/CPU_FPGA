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

entity Program_Counter is
	generic(
	
	data_width:integer :=32
	
	);
	
	port(
		clk		:	in	std_logic;
		
		rst_n		:	in	std_logic;
		
		pc_write :	in	std_logic; -- Write Enable / Stall Signal
		
		pc_src	:	in std_logic; -- Jump/Branch Control
		
		target_pc:	in std_logic_vector(DATA_WIDTH-1 downto 0); --Target Address
		
	
      pc_out   :	out std_logic_vector(DATA_WIDTH-1 downto 0); --Current PC

		pc_plus4	:	out std_logic_vector(DATA_WIDTH-1 downto 0)  --Next PC / PC+4
	
	);
end entity Program_Counter;


architecture Behavioral of Program_Counter is
	signal pc_reg : unsigned (DATA_WIDTH-1 downto 0) := (others => '0');
	
begin 

process(clk)
begin
	if rising_edge(clk) then
		if rst_n = '0' then
				pc_reg <= (others => '0');
		elsif pc_write = '1' then
				if pc_src ='1' then
					pc_reg <= unsigned(target_pc);
				else
					pc_reg <= pc_reg + 4; ---'4' indicates a 4 byte(32 bit) 
				end if;	
		end if;
	end if;		
end process;

pc_out <= std_logic_vector(pc_reg);
pc_plus4 <= std_logic_vector(pc_reg +4);

end architecture Behavioral;