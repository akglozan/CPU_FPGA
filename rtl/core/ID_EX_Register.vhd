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

entity ID_EX_Register is
    port (
        clk           : in  std_logic;
        rst_n         : in  std_logic;
        stall         : in  std_logic;
        flush         : in  std_logic;
        
        pc_in         : in  std_logic_vector(31 downto 0);
        pc_plus4_in   : in  std_logic_vector(31 downto 0);
        imm_ext_in    : in  std_logic_vector(31 downto 0);
        reg_data1_in  : in  std_logic_vector(31 downto 0);
        reg_data2_in  : in  std_logic_vector(31 downto 0);
        rs1_addr_in   : in  std_logic_vector(4 downto 0);
        rs2_addr_in   : in  std_logic_vector(4 downto 0);
        rd_addr_in    : in  std_logic_vector(4 downto 0);
        funct3_in     : in  std_logic_vector(2 downto 0);
        
        alu_src_in    : in  std_logic;
        alu_src_a_in  : in  std_logic;
        alu_ctrl_in   : in  std_logic_vector(3 downto 0);
        is_m_ext_in   : in  std_logic;
        mem_read_in   : in  std_logic;
        mem_write_in  : in  std_logic;
        branch_in     : in  std_logic;
        jump_in       : in  std_logic;
        reg_write_in  : in  std_logic;
        wb_sel_in     : in  std_logic_vector(1 downto 0);
        
        pc_out        : out std_logic_vector(31 downto 0);
        pc_plus4_out  : out std_logic_vector(31 downto 0);
        imm_ext_out   : out std_logic_vector(31 downto 0);
        reg_data1_out : out std_logic_vector(31 downto 0);
        reg_data2_out : out std_logic_vector(31 downto 0);
        rs1_addr_out  : out std_logic_vector(4 downto 0);
        rs2_addr_out  : out std_logic_vector(4 downto 0);
        rd_addr_out   : out std_logic_vector(4 downto 0);
        funct3_out    : out std_logic_vector(2 downto 0);
        
        alu_src_out   : out std_logic;
        alu_src_a_out : out std_logic;
        alu_ctrl_out  : out std_logic_vector(3 downto 0);
        is_m_ext_out  : out std_logic;
        mem_read_out  : out std_logic;
        mem_write_out : out std_logic;
        branch_out    : out std_logic;
        jump_out      : out std_logic;
        reg_write_out : out std_logic;
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