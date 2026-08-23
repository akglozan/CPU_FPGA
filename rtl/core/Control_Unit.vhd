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

-- Single-cycle instruction decoder / control unit. Decodes the 7-bit
-- opcode (with funct3/funct7) into datapath control signals for the
-- ALU, register write-back, memory access, and branch/jump resolution.
-- Decode happens in two stages internally: the first process maps
-- opcode to imm_src/alu_src/wb_sel/branch/jump plus a coarse 2-bit
-- alu_op; the second expands alu_op (with funct3/funct7) into the
-- final 4-bit alu_ctrl consumed by the ALU, and flags RV32M
-- multiply/divide ops via is_m_ext.
entity Control_Unit is
    port (
        -- 7-bit RISC-V opcode field (instr[6:0]); selects the instruction
        -- format/operation class.
        opcode    : in  std_logic_vector(6 downto 0);
        -- funct3 field (instr[14:12]); disambiguates instructions within
        -- an opcode group.
        funct3    : in  std_logic_vector(2 downto 0);
        -- funct7 field (instr[31:25]); distinguishes ADD/SUB, logical vs
        -- arithmetic shifts, and RV32M multiply/divide ops.
        funct7    : in  std_logic_vector(6 downto 0);
        
        -- Selects which immediate encoding ImmGen should sign-extend
        -- (I/S/B/U/J format).
        imm_src   : out std_logic_vector(2 downto 0);
        -- Selects ALU operand B source: '0' = register file (rs2),
        -- '1' = the decoded immediate.
        alu_src   : out std_logic;
        alu_src_a : out std_logic; -- '1' selects PC for AUIPC
        -- Enables the register file write for this instruction.
        reg_write : out std_logic;
        -- Enables a data memory read (loads).
        mem_read  : out std_logic;
        -- Enables a data memory write (stores).
        mem_write : out std_logic;
        -- Selects the write-back source: ALU result, memory read data,
        -- or PC+4 (JAL/JALR link address).
        wb_sel    : out std_logic_vector(1 downto 0);
        -- Asserted for conditional branch instructions; combined with
        -- the ALU's zero_flag to decide whether to redirect the PC.
        branch    : out std_logic;
        -- Asserted for unconditional jump instructions (JAL/JALR).
        jump      : out std_logic;
        -- Final 4-bit ALU operation select, forwarded to the ALU.
        alu_ctrl  : out std_logic_vector(3 downto 0);
        -- Asserted when the decoded R-type instruction is an RV32M
        -- multiply/divide extension op (funct7 = "0000001").
        is_m_ext  : out std_logic
    );
end entity Control_Unit;

architecture Behavioral of Control_Unit is
    signal alu_op : std_logic_vector(1 downto 0);
begin

    process(opcode)
    begin
        -- Default assignments to prevent inferred latches
        imm_src   <= "000";
        alu_src   <= '0';
        alu_src_a <= '0';
        reg_write <= '0';
        mem_read  <= '0';
        mem_write <= '0';
        wb_sel    <= "00";
        branch    <= '0';
        jump      <= '0';
        alu_op    <= "00";
    
        case opcode is
            when "0110011" => -- R-Type
                reg_write <= '1';
                alu_src   <= '0';
                alu_op    <= "10";
            
            when "0010011" => -- I-Type ALU
                reg_write <= '1';
                alu_src   <= '1';
                imm_src   <= "000";
                alu_op    <= "11";
            
            when "0000011" => -- Load
                reg_write <= '1';
                alu_src   <= '1';
                mem_read  <= '1';
                wb_sel    <= "01";
                imm_src   <= "000";
                alu_op    <= "00";
            
            when "0100011" => -- Store
                alu_src   <= '1';
                mem_write <= '1';
                imm_src   <= "001";
                alu_op    <= "00";
            
            when "1100011" => -- Branch
                branch  <= '1';
                alu_src <= '0';
                imm_src <= "010";
                alu_op  <= "01";
                
            when "1101111" => -- JAL
                reg_write <= '1';
                jump      <= '1';
                wb_sel    <= "10";
                imm_src   <= "100";
                alu_op    <= "00";
                
            when "1100111" => -- JALR
                reg_write <= '1';
                jump      <= '1';
                alu_src   <= '1';
                wb_sel    <= "10";
                imm_src   <= "000";
                alu_op    <= "00";
            
            when "0110111" => -- LUI
                reg_write <= '1';
                alu_src   <= '1';
                imm_src   <= "011";
                alu_op    <= "11";
                
            when "0010111" => -- AUIPC (PC + Imm)
                reg_write <= '1';
                alu_src   <= '1';
                alu_src_a <= '1'; -- Route PC into ALU Operand A
                imm_src   <= "011";
                alu_op    <= "00";
                
            when others =>
                null;
        end case;
    end process;

    process(alu_op, funct3, funct7, opcode)
    begin
        alu_ctrl <= "0000";
        is_m_ext <= '0';
        
        case alu_op is
            when "00" => -- Memory addresses / AUIPC / JALR addition
                alu_ctrl <= "0000";
                
            when "01" => -- Branch comparison subtraction
                alu_ctrl <= "0001";
                
            when "10" => -- R-Type
                if funct7 = "0000001" then
                    is_m_ext <= '1';
                    alu_ctrl <= '0' & funct3;
                else    
                    case funct3 is
                        when "000" =>
                            if funct7(5) = '1' then
                                alu_ctrl <= "0001"; -- SUB
                            else
                                alu_ctrl <= "0000"; -- ADD
                            end if;
                        when "001" => alu_ctrl <= "0010"; -- SLL
                        when "010" => alu_ctrl <= "0011"; -- SLT
                        when "011" => alu_ctrl <= "0100"; -- SLTU
                        when "100" => alu_ctrl <= "0101"; -- XOR
                        when "101" =>
                            if funct7(5) = '1' then
                                alu_ctrl <= "0111"; -- SRA
                            else
                                alu_ctrl <= "0110"; -- SRL
                            end if;
                        when "110" => alu_ctrl <= "1000"; -- OR
                        when "111" => alu_ctrl <= "1001"; -- AND
                        when others => alu_ctrl <= "0000";
                    end case;
                end if;
                
            when "11" => -- I-Type & LUI
                if opcode = "0110111" then
                    alu_ctrl <= "1010"; -- Pass Operand B (LUI)
                else
                    case funct3 is
                        when "000" => alu_ctrl <= "0000"; -- ADDI
                        when "001" => alu_ctrl <= "0010"; -- SLLI
                        when "010" => alu_ctrl <= "0011"; -- SLTI
                        when "011" => alu_ctrl <= "0100"; -- SLTIU
                        when "100" => alu_ctrl <= "0101"; -- XORI
                        when "101" =>
                            if funct7(5) = '1' then
                                alu_ctrl <= "0111"; -- SRAI
                            else
                                alu_ctrl <= "0110"; -- SRLI
                            end if;
                        when "110" => alu_ctrl <= "1000"; -- ORI
                        when "111" => alu_ctrl <= "1001"; -- ANDI
                        when others => alu_ctrl <= "0000";
                    end case;
                end if;
            when others =>
                alu_ctrl <= "0000";
        end case;
    end process;    

end architecture Behavioral;