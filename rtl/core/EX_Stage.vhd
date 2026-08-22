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

entity EX_Stage is
    port (
        clk                     : in  std_logic;
        rst_n                   : in  std_logic;
        stall_ex_mem_in         : in  std_logic; -- From Hazard Unit
        
        -- Inputs from ID/EX Register
        ex_pc_in                : in  std_logic_vector(31 downto 0);
        ex_pc_plus4_in          : in  std_logic_vector(31 downto 0);
        ex_imm_ext_in           : in  std_logic_vector(31 downto 0);
        ex_reg_data1_in         : in  std_logic_vector(31 downto 0);
        ex_reg_data2_in         : in  std_logic_vector(31 downto 0);
        ex_rs1_addr_in          : in  std_logic_vector(4 downto 0);
        ex_rs2_addr_in          : in  std_logic_vector(4 downto 0);
        ex_rd_addr_in           : in  std_logic_vector(4 downto 0);
        ex_funct3_in            : in  std_logic_vector(2 downto 0);
        
        -- Control Inputs from ID/EX Register
        ex_alu_src_in           : in  std_logic;
        ex_alu_src_a_in         : in  std_logic;
        ex_alu_ctrl_in          : in  std_logic_vector(3 downto 0);
        ex_is_m_ext_in          : in  std_logic;
        ex_mem_read_in          : in  std_logic;
        ex_mem_write_in         : in  std_logic;
        ex_branch_in            : in  std_logic;
        ex_jump_in              : in  std_logic;
        ex_reg_write_in         : in  std_logic;
        ex_wb_sel_in            : in  std_logic_vector(1 downto 0);
        
        -- Feedback Inputs from MEM and WB Stages for Forwarding
        mem_rd_addr_in          : in  std_logic_vector(4 downto 0);
        mem_reg_write_in        : in  std_logic;
        mem_mem_read_in         : in  std_logic;
        mem_result_in           : in  std_logic_vector(31 downto 0);
        wb_rd_addr_in           : in  std_logic_vector(4 downto 0);
        wb_reg_write_in         : in  std_logic;
        wb_rd_data_in           : in  std_logic_vector(31 downto 0);
        
        -- Outputs to Hazard Unit & Program Counter
        take_branch_out         : out std_logic;
        target_pc_out           : out std_logic_vector(31 downto 0);
        stall_m_out             : out std_logic;
        
        -- Outputs to EX/MEM Pipeline Register
        mem_result_out          : out std_logic_vector(31 downto 0);
        mem_write_data_out      : out std_logic_vector(31 downto 0);
        mem_rd_addr_out         : out std_logic_vector(4 downto 0);
        mem_pc_plus4_out        : out std_logic_vector(31 downto 0);
        mem_reg_write_out       : out std_logic;
        mem_mem_read_out        : out std_logic;
        mem_mem_write_out       : out std_logic;
        mem_wb_sel_out          : out std_logic_vector(1 downto 0);
        mem_funct3_out          : out std_logic_vector(2 downto 0)
    );
end entity EX_Stage;

architecture Structural of EX_Stage is

    component ALU is
        port (
            alu_ctrl   : in  std_logic_vector(3 downto 0);
            operand_a  : in  std_logic_vector(31 downto 0);
            operand_b  : in  std_logic_vector(31 downto 0);
            alu_result : out std_logic_vector(31 downto 0);
            zero_flag  : out std_logic
        );
    end component;

    component M_Extension_Unit is
        port (
            clk       : in  std_logic;
            rst_n     : in  std_logic;
            is_m_ext  : in  std_logic;
            funct3    : in  std_logic_vector(2 downto 0);
            operand_a : in  std_logic_vector(31 downto 0);
            operand_b : in  std_logic_vector(31 downto 0);
            m_result  : out std_logic_vector(31 downto 0);
            stall_m   : out std_logic
        );
    end component;

    component Forwarding_Unit is
        port (
            ex_rs1_addr   : in  std_logic_vector(4 downto 0);
            ex_rs2_addr   : in  std_logic_vector(4 downto 0);
            mem_rd_addr   : in  std_logic_vector(4 downto 0);
            mem_reg_write : in  std_logic;
            mem_mem_read  : in  std_logic;
            wb_rd_addr    : in  std_logic_vector(4 downto 0);
            wb_reg_write  : in  std_logic;
            forward_a     : out std_logic_vector(1 downto 0);
            forward_b     : out std_logic_vector(1 downto 0)
        );
    end component;

    component ex_mem_register is
    port (
        clk   : in std_logic;
        rst_n : in std_logic;
        flush : in std_logic;
        stall : in std_logic;

        ex_result       : in std_logic_vector(31 downto 0);
        ex_operand_b    : in std_logic_vector(31 downto 0);
        ex_rd_addr      : in std_logic_vector(4 downto 0);
        ex_pc_plus4     : in std_logic_vector(31 downto 0);

        ex_reg_write    : in std_logic;
        ex_mem_read     : in std_logic;
        ex_mem_write    : in std_logic;
        ex_wb_sel       : in std_logic_vector(1 downto 0);
        ex_funct3       : in std_logic_vector(2 downto 0);

        mem_addr        : out std_logic_vector(31 downto 0);
        mem_result      : out std_logic_vector(31 downto 0);
        mem_write_data  : out std_logic_vector(31 downto 0);
        mem_rd_addr     : out std_logic_vector(4 downto 0);
        mem_pc_plus4    : out std_logic_vector(31 downto 0);

        mem_reg_write   : out std_logic;
        mem_read        : out std_logic;
        mem_write       : out std_logic;
        mem_wb_sel      : out std_logic_vector(1 downto 0);
        mem_funct3      : out std_logic_vector(2 downto 0)
    );
end component;

    signal forward_a              : std_logic_vector(1 downto 0);
    signal forward_b              : std_logic_vector(1 downto 0);
    signal ex_operand_a_forwarded : std_logic_vector(31 downto 0);
    signal ex_operand_b_forwarded : std_logic_vector(31 downto 0);
    signal ex_alu_operand_a       : std_logic_vector(31 downto 0);
    signal ex_alu_operand_b       : std_logic_vector(31 downto 0);
    signal ex_base_alu_res        : std_logic_vector(31 downto 0);
    signal ex_zero_flag           : std_logic;
    signal ex_m_ext_res           : std_logic_vector(31 downto 0);
    signal ex_final_result        : std_logic_vector(31 downto 0);
    signal stall_m_wire           : std_logic;
    signal branch_cond_met        : std_logic;
    signal ex_mem_stall_combined  : std_logic;
    signal jalr_sum               : unsigned(31 downto 0);
    signal jal_sum                : unsigned(31 downto 0);

begin

    stall_m_out <= stall_m_wire;
    ex_mem_stall_combined <= stall_m_wire or stall_ex_mem_in;

    with forward_a select
        ex_operand_a_forwarded <= ex_reg_data1_in when "00",
                                  mem_result_in   when "10",
                                  wb_rd_data_in   when "01",
                                  (others => '0') when others;

    with forward_b select
        ex_operand_b_forwarded <= ex_reg_data2_in when "00",
                                  mem_result_in   when "10",
                                  wb_rd_data_in   when "01",
                                  (others => '0') when others;

    ex_alu_operand_a <= ex_pc_in when ex_alu_src_a_in = '1' else ex_operand_a_forwarded;
    ex_alu_operand_b <= ex_imm_ext_in when ex_alu_src_in = '1' else ex_operand_b_forwarded;

    U_FWD : Forwarding_Unit
        port map (
            ex_rs1_addr   => ex_rs1_addr_in,
            ex_rs2_addr   => ex_rs2_addr_in,
            mem_rd_addr   => mem_rd_addr_in,
            mem_reg_write => mem_reg_write_in,
            mem_mem_read  => mem_mem_read_in,
            wb_rd_addr    => wb_rd_addr_in,
            wb_reg_write  => wb_reg_write_in,
            forward_a     => forward_a,
            forward_b     => forward_b
        );

    U_ALU : ALU
        port map (
            alu_ctrl   => ex_alu_ctrl_in,
            operand_a  => ex_alu_operand_a,
            operand_b  => ex_alu_operand_b,
            alu_result => ex_base_alu_res,
            zero_flag  => ex_zero_flag
        );

    U_M_EXT : M_Extension_Unit
        port map (
            clk       => clk,
            rst_n     => rst_n,
            is_m_ext  => ex_is_m_ext_in,
            funct3    => ex_funct3_in,
            operand_a => ex_operand_a_forwarded,
            operand_b => ex_operand_b_forwarded,
            m_result  => ex_m_ext_res,
            stall_m   => stall_m_wire
        );

    ex_final_result <= ex_m_ext_res when ex_is_m_ext_in = '1' else ex_base_alu_res;

    process(ex_funct3_in, ex_operand_a_forwarded, ex_operand_b_forwarded, ex_zero_flag)
    begin
        case ex_funct3_in is
            when "000" => branch_cond_met <= ex_zero_flag;
            when "001" => branch_cond_met <= not ex_zero_flag;
            when "100" =>
                if signed(ex_operand_a_forwarded) < signed(ex_operand_b_forwarded) then
                    branch_cond_met <= '1';
                else
                    branch_cond_met <= '0';
                end if;
            when "101" =>
                if signed(ex_operand_a_forwarded) >= signed(ex_operand_b_forwarded) then
                    branch_cond_met <= '1';
                else
                    branch_cond_met <= '0';
                end if;
            when "110" =>
                if unsigned(ex_operand_a_forwarded) < unsigned(ex_operand_b_forwarded) then
                    branch_cond_met <= '1';
                else
                    branch_cond_met <= '0';
                end if;
            when "111" =>
                if unsigned(ex_operand_a_forwarded) >= unsigned(ex_operand_b_forwarded) then
                    branch_cond_met <= '1';
                else
                    branch_cond_met <= '0';
                end if;
            when others =>
                branch_cond_met <= '0';
        end case;
    end process;

    take_branch_out <= (ex_branch_in and branch_cond_met) or ex_jump_in;

    jalr_sum <= unsigned(ex_operand_a_forwarded) + unsigned(ex_imm_ext_in);
    jal_sum  <= unsigned(ex_pc_in) + unsigned(ex_imm_ext_in);

    -- JALR target: Bit 0 is always cleared ('0'); JAL target: PC + imm
    target_pc_out <= std_logic_vector(jalr_sum(31 downto 1)) & '0' when (ex_jump_in = '1' and ex_alu_src_in = '1')
                     else std_logic_vector(jal_sum);

    u_ex_mem_register : ex_mem_register
    port map (
        clk   => clk,
        rst_n => rst_n,
        flush => '0',
        stall => ex_mem_stall,

        ex_result       => ex_final_result,
        ex_operand_b    => ex_operand_b_forwarded,
        ex_rd_addr      => ex_rd_addr_in,
        ex_pc_plus4     => ex_pc_plus4_in,

        ex_reg_write    => ex_reg_write_in,
        ex_mem_read     => ex_mem_read_in,
        ex_mem_write    => ex_mem_write_in,
        ex_wb_sel       => ex_wb_sel_in,
        ex_funct3       => ex_funct3_in,

        mem_addr        => mem_addr_out,
        mem_result      => mem_result_out,
        mem_write_data  => mem_write_data_out,
        mem_rd_addr     => mem_rd_addr_out,
        mem_pc_plus4    => mem_pc_plus4_out,

        mem_reg_write   => mem_reg_write_out,
        mem_read        => mem_read_out,
        mem_write       => mem_write_out,
        mem_wb_sel      => mem_wb_sel_out,
        mem_funct3      => mem_funct3_out
    );

end architecture Structural;