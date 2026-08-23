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

-- 4-bit-controlled combinational Arithmetic Logic Unit for the RV32I/M
-- execute stage. Implements ADD, SUB, logical/arithmetic shifts,
-- SLT/SLTU set-less-than compares, bitwise XOR/OR/AND, and a LUI
-- pass-through, selected by alu_ctrl (see the case statement in the
-- architecture body for the full opcode encoding). Also produces a
-- zero_flag alongside the result, used by the branch unit to resolve
-- BEQ/BNE after a SUB-based comparison.
entity ALU is

	port(
		
		-- ALU operation select (0000=ADD 0001=SUB 0010=SLL 0011=SLT
		-- 0100=SLTU 0101=XOR 0110=SRL 0111=SRA 1000=OR 1001=AND
		-- 1010=LUI passthrough).
		alu_ctrl		:	in		std_logic_vector(3 downto 0);
		-- First ALU operand (typically rs1, or the PC for AUIPC-related adds).
		operand_a	:	in		std_logic_vector(31 downto 0);
		-- Second ALU operand (typically rs2, or a sign-extended immediate).
		operand_b	:	in		std_logic_vector(31 downto 0);
		-- Result of the selected operation.
		alu_result	:	out	std_logic_vector(31 downto 0);
		-- Asserted when alu_result is all zeros.
		zero_flag	:	out	std_logic

	
	);
	
end entity;


architecture Behavioral of ALU is

    signal result_int : std_logic_vector(31 downto 0);

begin

    ---------------------------------------------------------------------------
    -- Combinational ALU Core Process
    ---------------------------------------------------------------------------
    process(alu_ctrl, operand_a, operand_b)
        variable shift_amt : integer range 0 to 31;
    begin
        -- Extract the lower 5 bits of operand_b for shift counts
        shift_amt := to_integer(unsigned(operand_b(4 downto 0)));

        case alu_ctrl is

            -- 0000: ADD / Pass-Through Operations (ADD, ADDI, Loads, Stores, AUIPC, JALR)
            when "0000" =>
                result_int <= std_logic_vector(signed(operand_a) + signed(operand_b));

            -- 0001: SUB / Branch Comparison Subtraction
            when "0001" =>
                result_int <= std_logic_vector(signed(operand_a) - signed(operand_b));

            -- 0010: SLL / SLLI (Shift Left Logical)
            when "0010" =>
                result_int <= std_logic_vector(shift_left(unsigned(operand_a), shift_amt));

            -- 0011: SLT / SLTI (Set Less Than - Signed)
            when "0011" =>
                if signed(operand_a) < signed(operand_b) then
                    result_int <= x"00000001";
                else
                    result_int <= x"00000000";
                end if;

            -- 0100: SLTU / SLTIU (Set Less Than - Unsigned)
            when "0100" =>
                if unsigned(operand_a) < unsigned(operand_b) then
                    result_int <= x"00000001";
                else
                    result_int <= x"00000000";
                end if;

            -- 0101: XOR / XORI
            when "0101" =>
                result_int <= operand_a xor operand_b;

            -- 0110: SRL / SRLI (Shift Right Logical)
            when "0110" =>
                result_int <= std_logic_vector(shift_right(unsigned(operand_a), shift_amt));

            -- 0111: SRA / SRAI (Shift Right Arithmetic)
            when "0111" =>
                result_int <= std_logic_vector(shift_right(signed(operand_a), shift_amt));

            -- 1000: OR / ORI
            when "1000" =>
                result_int <= operand_a or operand_b;

            -- 1001: AND / ANDI
            when "1001" =>
                result_int <= operand_a and operand_b;

            -- 1010: LUI (Pass Operand B directly)
            when "1010" =>
                result_int <= operand_b;

            when others =>
                result_int <= (others => '0');

        end case;
    end process;

    ---------------------------------------------------------------------------
    -- Output & Zero Flag Generation
    ---------------------------------------------------------------------------
    alu_result <= result_int;
    zero_flag  <= '1' when result_int = x"00000000" else '0';

end architecture Behavioral;