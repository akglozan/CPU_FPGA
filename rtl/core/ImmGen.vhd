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

entity ImmGen is 

	port(
	
		inst		: in		std_logic_vector(31 downto 0);
		imm_src	: in		std_logic_vector(2 downto 0);
		
		imm_ext 	: out 	std_logic_vector(31 downto 0)
	);


end entity;

architecture Behavioral of ImmGen is

begin


process(inst,imm_src)
begin


	case imm_src is
		when "000" => 	-- I-Type (e.g., ADDI, LW, JALR)
			imm_ext <=	(31 downto 11 => inst(31)) & inst(30 downto 20);
		when "001" =>	-- S-Type (e.g., SW, SB, SH)
			imm_ext <=	(31 downto 11 => inst(31)) & inst(30 downto 25) & inst(11 downto 7); 
		when "010" =>	-- B-Type (e.g., BEQ, BNE, BLT)
			imm_ext <=	(31 downto 12 => inst(31)) & inst(7) & inst(30 downto 25) & inst(11 downto 8) & '0'; 
		when "011" =>	-- U-Type (e.g., LUI, AUIPC)
			imm_ext <=	inst(31 downto 12) & (11 downto 0 => '0'); 
		when "100" =>	-- J-Type (e.g., JAL)
			imm_ext <=	 (31 downto 20 => inst(31)) & inst(19 downto 12) & inst(20) & inst(30 downto 21) & '0';
		when others => -- Default / Latch Prevention
			imm_ext <= (others => '0');
	end case;	
	

end process;


end architecture Behavioral;