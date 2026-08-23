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

-- ID/EX pipeline register. Latches every datapath value and control
-- signal decoded/read during the ID stage, so the EX stage sees a
-- stable snapshot for exactly one cycle. Cleared to all-zero/disabled
-- (a NOP-equivalent bubble) on reset or flush (control hazard); held
-- unchanged on stall (e.g. a load-use hazard freezing this stage).
entity ID_EX_Register is
    port (
        clk           : in  std_logic;
        -- Active-low synchronous reset.
        rst_n         : in  std_logic;
        -- Holds the register's current outputs unchanged this cycle.
        stall         : in  std_logic;
        -- Clears all outputs to a bubble this cycle (control hazard).
        flush         : in  std_logic;
        
        -- Program counter of the instruction in ID.
        pc_in         : in  std_logic_vector(31 downto 0);
        -- PC+4 (link address candidate for JAL/JALR).
        pc_plus4_in   : in  std_logic_vector(31 downto 0);
        -- Sign-extended immediate from ImmGen.
        imm_ext_in    : in  std_logic_vector(31 downto 0);
        -- Register file read data for rs1.
        reg_data1_in  : in  std_logic_vector(31 downto 0);
        -- Register file read data for rs2.
        reg_data2_in  : in  std_logic_vector(31 downto 0);
        -- Source register 1 address (for the EX-stage forwarding unit).
        rs1_addr_in   : in  std_logic_vector(4 downto 0);
        -- Source register 2 address (for the EX-stage forwarding unit).
        rs2_addr_in   : in  std_logic_vector(4 downto 0);
        -- Destination register address.
        rd_addr_in    : in  std_logic_vector(4 downto 0);
        -- funct3 field, needed by EX/MEM for M-extension op selection
        -- and load/store width/sign formatting.
        funct3_in     : in  std_logic_vector(2 downto 0);
        
        -- Selects ALU operand B: register value or immediate.
        alu_src_in    : in  std_logic;
        -- Selects ALU operand A: register value or PC (AUIPC).
        alu_src_a_in  : in  std_logic;
        -- 4-bit ALU operation select from Control_Unit.
        alu_ctrl_in   : in  std_logic_vector(3 downto 0);
        -- Asserted for RV32M multiply/divide instructions.
        is_m_ext_in   : in  std_logic;
        -- Asserted for load instructions.
        mem_read_in   : in  std_logic;
        -- Asserted for store instructions.
        mem_write_in  : in  std_logic;
        -- Asserted for conditional branch instructions.
        branch_in     : in  std_logic;
        -- Asserted for unconditional jump instructions.
        jump_in       : in  std_logic;
        -- Register file write enable.
        reg_write_in  : in  std_logic;
        -- Write-back source select (ALU result / memory data / PC+4).
        wb_sel_in     : in  std_logic_vector(1 downto 0);
        
        -- Registered pc_in, presented to the EX stage.
        pc_out        : out std_logic_vector(31 downto 0);
        -- Registered pc_plus4_in, presented to the EX stage.
        pc_plus4_out  : out std_logic_vector(31 downto 0);
        -- Registered imm_ext_in, presented to the EX stage.
        imm_ext_out   : out std_logic_vector(31 downto 0);
        -- Registered reg_data1_in, presented to the EX stage.
        reg_data1_out : out std_logic_vector(31 downto 0);
        -- Registered reg_data2_in, presented to the EX stage.
        reg_data2_out : out std_logic_vector(31 downto 0);
        -- Registered rs1_addr_in, presented to the EX stage.
        rs1_addr_out  : out std_logic_vector(4 downto 0);
        -- Registered rs2_addr_in, presented to the EX stage.
        rs2_addr_out  : out std_logic_vector(4 downto 0);
        -- Registered rd_addr_in, presented to the EX stage.
        rd_addr_out   : out std_logic_vector(4 downto 0);
        -- Registered funct3_in, presented to the EX stage.
        funct3_out    : out std_logic_vector(2 downto 0);
        
        -- Registered alu_src_in, presented to the EX stage.
        alu_src_out   : out std_logic;
        -- Registered alu_src_a_in, presented to the EX stage.
        alu_src_a_out : out std_logic;
        -- Registered alu_ctrl_in, presented to the EX stage.
        alu_ctrl_out  : out std_logic_vector(3 downto 0);
        -- Registered is_m_ext_in, presented to the EX stage.
        is_m_ext_out  : out std_logic;
        -- Registered mem_read_in, presented to the EX stage.
        mem_read_out  : out std_logic;
        -- Registered mem_write_in, presented to the EX stage.
        mem_write_out : out std_logic;
        -- Registered branch_in, presented to the EX stage.
        branch_out    : out std_logic;
        -- Registered jump_in, presented to the EX stage.
        jump_out      : out std_logic;
        -- Registered reg_write_in, presented to the EX stage.
        reg_write_out : out std_logic;
        -- Registered wb_sel_in, presented to the EX stage.
        wb_sel_out    : out std_logic_vector(1 downto 0)
    );
end entity ID_EX_Register;

architecture Behavioral of ID_EX_Register is
begin

    process(clk)
    begin
        if rising_edge(clk) then
            if rst_n = '0' or flush = '1' then
                pc_out        <= (others => '0');
                pc_plus4_out  <= (others => '0');
                imm_ext_out   <= (others => '0');
                reg_data1_out <= (others => '0');
                reg_data2_out <= (others => '0');
                rs1_addr_out  <= (others => '0');
                rs2_addr_out  <= (others => '0');
                rd_addr_out   <= (others => '0');
                funct3_out    <= (others => '0');
                alu_src_out   <= '0';
                alu_src_a_out <= '0';
                alu_ctrl_out  <= (others => '0');
                is_m_ext_out  <= '0';
                mem_read_out  <= '0';
                mem_write_out <= '0';
                branch_out    <= '0';
                jump_out      <= '0';
                reg_write_out <= '0';
                wb_sel_out    <= (others => '0');
            elsif stall = '0' then
                pc_out        <= pc_in;
                pc_plus4_out  <= pc_plus4_in;
                imm_ext_out   <= imm_ext_in;
                reg_data1_out <= reg_data1_in;
                reg_data2_out <= reg_data2_in;
                rs1_addr_out  <= rs1_addr_in;
                rs2_addr_out  <= rs2_addr_in;
                rd_addr_out   <= rd_addr_in;
                funct3_out    <= funct3_in;
                alu_src_out   <= alu_src_in;
                alu_src_a_out <= alu_src_a_in;
                alu_ctrl_out  <= alu_ctrl_in;
                is_m_ext_out  <= is_m_ext_in;
                mem_read_out  <= mem_read_in;
                mem_write_out <= mem_write_in;
                branch_out    <= branch_in;
                jump_out      <= jump_in;
                reg_write_out <= reg_write_in;
                wb_sel_out    <= wb_sel_in;
            end if;
        end if;
    end process;

end architecture Behavioral;