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

-- EX-stage top-level wrapper. Instantiates the Forwarding_Unit, ALU,
-- M_Extension_Unit, and EX_MEM_Register, resolving forwarded operands,
-- computing the ALU/M-extension result, evaluating branch conditions
-- and JAL/JALR target addresses, and latching everything into the
-- EX/MEM pipeline register.
entity EX_Stage is
    port (
        clk                     : in  std_logic;
        -- Active-low synchronous reset.
        rst_n                   : in  std_logic;
        stall_ex_mem_in         : in  std_logic; -- From Hazard Unit
        
        -- Inputs from ID/EX Register
        -- Program counter of the instruction in EX.
        ex_pc_in                : in  std_logic_vector(31 downto 0);
        -- PC+4, used for JAL/JALR target calc and write-back.
        ex_pc_plus4_in          : in  std_logic_vector(31 downto 0);
        -- Sign-extended immediate.
        ex_imm_ext_in           : in  std_logic_vector(31 downto 0);
        -- Register file read data for rs1 (pre-forwarding).
        ex_reg_data1_in         : in  std_logic_vector(31 downto 0);
        -- Register file read data for rs2 (pre-forwarding).
        ex_reg_data2_in         : in  std_logic_vector(31 downto 0);
        -- Source register 1 address, for the Forwarding Unit.
        ex_rs1_addr_in          : in  std_logic_vector(4 downto 0);
        -- Source register 2 address, for the Forwarding Unit.
        ex_rs2_addr_in          : in  std_logic_vector(4 downto 0);
        -- Destination register address.
        ex_rd_addr_in           : in  std_logic_vector(4 downto 0);
        -- funct3 field, for M-extension op selection and branch
        -- condition evaluation.
        ex_funct3_in            : in  std_logic_vector(2 downto 0);
        
        -- Control Inputs from ID/EX Register
        -- Selects ALU operand B: forwarded register value or immediate.
        ex_alu_src_in           : in  std_logic;
        -- Selects ALU operand A: forwarded register value or PC (AUIPC).
        ex_alu_src_a_in         : in  std_logic;
        -- 4-bit ALU operation select.
        ex_alu_ctrl_in          : in  std_logic_vector(3 downto 0);
        -- Asserted for RV32M multiply/divide instructions.
        ex_is_m_ext_in          : in  std_logic;
        -- Asserted for load instructions.
        ex_mem_read_in          : in  std_logic;
        -- Asserted for store instructions.
        ex_mem_write_in         : in  std_logic;
        -- Asserted for conditional branch instructions.
        ex_branch_in            : in  std_logic;
        -- Asserted for unconditional jump instructions.
        ex_jump_in              : in  std_logic;
        -- Register file write enable.
        ex_reg_write_in         : in  std_logic;
        -- Write-back source select.
        ex_wb_sel_in            : in  std_logic_vector(1 downto 0);
        
        -- Feedback Inputs from MEM and WB Stages for Forwarding
        -- MEM-stage destination register address.
        mem_rd_addr_in          : in  std_logic_vector(4 downto 0);
        -- MEM-stage register-write enable.
        mem_reg_write_in        : in  std_logic;
        -- MEM-stage load indicator (inhibits MEM-stage forwarding).
        mem_mem_read_in         : in  std_logic;
        -- MEM-stage result value, available for forwarding.
        mem_result_in           : in  std_logic_vector(31 downto 0);
        -- WB-stage destination register address.
        wb_rd_addr_in           : in  std_logic_vector(4 downto 0);
        -- WB-stage register-write enable.
        wb_reg_write_in         : in  std_logic;
        -- WB-stage write-back data, available for forwarding.
        wb_rd_data_in           : in  std_logic_vector(31 downto 0);
        
        -- Outputs to Hazard Unit & Program Counter
        -- Asserted when a branch/jump in this stage resolves as taken.
        take_branch_out         : out std_logic;
        -- Computed branch/jump target address.
        target_pc_out           : out std_logic_vector(31 downto 0);
        -- Asserted while the M-extension unit needs extra cycles.
        stall_m_out             : out std_logic;
        
        -- Outputs to EX/MEM Pipeline Register
        -- See EX_MEM_Register's mem_addr.
        mem_addr_out            : out std_logic_vector(31 downto 0);
        -- See EX_MEM_Register's mem_result.
        mem_result_out          : out std_logic_vector(31 downto 0);
        -- See EX_MEM_Register's mem_write_data.
        mem_write_data_out      : out std_logic_vector(31 downto 0);
        -- See EX_MEM_Register's mem_rd_addr.
        mem_rd_addr_out         : out std_logic_vector(4 downto 0);
        -- See EX_MEM_Register's mem_pc_plus4.
        mem_pc_plus4_out        : out std_logic_vector(31 downto 0);
        -- See EX_MEM_Register's mem_reg_write.
        mem_reg_write_out       : out std_logic;
        -- See EX_MEM_Register's mem_read.
        mem_mem_read_out        : out std_logic;
        -- See EX_MEM_Register's mem_write.
        mem_mem_write_out       : out std_logic;
        -- See EX_MEM_Register's mem_wb_sel.
        mem_wb_sel_out          : out std_logic_vector(1 downto 0);
        -- See EX_MEM_Register's mem_funct3.
        mem_funct3_out          : out std_logic_vector(2 downto 0)
    );
end entity EX_Stage;

architecture Structural of EX_Stage is

    -- Direct entity instantiation (entity work.X) is used throughout
    -- this project instead of component declarations: the port list
    -- lives in exactly one place (the entity itself), so there's
    -- nothing here to fall out of sync with it.
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

    U_FWD : entity work.Forwarding_Unit
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

    U_ALU : entity work.ALU
        port map (
            alu_ctrl   => ex_alu_ctrl_in,
            operand_a  => ex_alu_operand_a,
            operand_b  => ex_alu_operand_b,
            alu_result => ex_base_alu_res,
            zero_flag  => ex_zero_flag
        );

    U_M_EXT : entity work.M_Extension_Unit
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

    u_ex_mem_register : entity work.EX_MEM_Register
    port map (
        clk   => clk,
        rst_n => rst_n,
        flush => '0',
        stall => ex_mem_stall_combined,

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
        mem_read        => mem_mem_read_out,
        mem_write       => mem_mem_write_out,
        mem_wb_sel      => mem_wb_sel_out,
        mem_funct3      => mem_funct3_out
    );

end architecture Structural;