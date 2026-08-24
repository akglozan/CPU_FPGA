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

-- ID-stage top-level wrapper. Instantiates the RegFile, Control_Unit,
-- ImmGen, and ID_EX_Register, wiring the decoded instruction fields
-- and register reads through to the pipeline register that latches
-- everything for the EX stage. Also exposes the raw (pre-register)
-- rs1/rs2 addresses and read data to the Hazard Unit and Forwarding
-- Unit for hazard detection.
entity ID_Stage is
    port (
        clk             : in  std_logic;
        -- Active-low synchronous reset.
        rst_n           : in  std_logic;
        
        -- Hazard Controls from Hazard_Unit
        -- Forwarded to ID_EX_Register's stall input.
        id_ex_stall     : in  std_logic;
        -- Forwarded to ID_EX_Register's flush input.
        id_ex_flush     : in  std_logic;
        
        -- Inputs from IF/ID Register
        -- Program counter of the instruction being decoded.
        id_pc_in        : in  std_logic_vector(31 downto 0);
        -- PC+4, carried through for JAL/JALR write-back.
        id_pc_plus4_in  : in  std_logic_vector(31 downto 0);
        -- Raw instruction word to decode.
        id_instr_in     : in  std_logic_vector(31 downto 0);
        
        -- Inputs from WB Stage
        -- Register file write enable from the WB stage.
        wb_reg_write    : in  std_logic;
        -- Register file write address from the WB stage.
        wb_rd_addr      : in  std_logic_vector(4 downto 0);
        -- Register file write data from the WB stage.
        wb_rd_data      : in  std_logic_vector(31 downto 0);
        
        -- Outputs to Hazard Unit
        -- Raw (pre-pipeline-register) rs1 address, decoded this cycle.
        id_rs1_addr_out : out std_logic_vector(4 downto 0);
        -- Raw (pre-pipeline-register) rs2 address, decoded this cycle.
        id_rs2_addr_out : out std_logic_vector(4 downto 0);
        -- RegFile read data for rs1 this cycle.
        id_rs1_data_out : out std_logic_vector(31 downto 0);
        -- RegFile read data for rs2 this cycle.
        id_rs2_data_out : out std_logic_vector(31 downto 0);
        
        -- Outputs from ID/EX Pipeline Register to EX Stage
        -- See ID_EX_Register's pc_out.
        ex_pc_out       : out std_logic_vector(31 downto 0);
        -- See ID_EX_Register's pc_plus4_out.
        ex_pc_plus4_out : out std_logic_vector(31 downto 0);
        -- See ID_EX_Register's imm_ext_out.
        ex_imm_ext_out  : out std_logic_vector(31 downto 0);
        -- See ID_EX_Register's reg_data1_out.
        ex_reg_data1_out: out std_logic_vector(31 downto 0);
        -- See ID_EX_Register's reg_data2_out.
        ex_reg_data2_out: out std_logic_vector(31 downto 0);
        -- See ID_EX_Register's rs1_addr_out.
        ex_rs1_addr_out : out std_logic_vector(4 downto 0);
        -- See ID_EX_Register's rs2_addr_out.
        ex_rs2_addr_out : out std_logic_vector(4 downto 0);
        -- See ID_EX_Register's rd_addr_out.
        ex_rd_addr_out  : out std_logic_vector(4 downto 0);
        -- See ID_EX_Register's funct3_out.
        ex_funct3_out   : out std_logic_vector(2 downto 0);
        
        -- EX Control Outputs
        -- See ID_EX_Register's alu_src_out.
        ex_alu_src_out  : out std_logic;
        -- See ID_EX_Register's alu_src_a_out.
        ex_alu_src_a_out: out std_logic;
        -- See ID_EX_Register's alu_ctrl_out.
        ex_alu_ctrl_out : out std_logic_vector(3 downto 0);
        -- See ID_EX_Register's is_m_ext_out.
        ex_is_m_ext_out : out std_logic;
        -- See ID_EX_Register's mem_read_out.
        ex_mem_read_out : out std_logic;
        -- See ID_EX_Register's mem_write_out.
        ex_mem_write_out: out std_logic;
        -- See ID_EX_Register's branch_out.
        ex_branch_out   : out std_logic;
        -- See ID_EX_Register's jump_out.
        ex_jump_out     : out std_logic;
        -- See ID_EX_Register's reg_write_out.
        ex_reg_write_out: out std_logic;
        -- See ID_EX_Register's wb_sel_out.
        ex_wb_sel_out   : out std_logic_vector(1 downto 0)
    );
end entity ID_Stage;

architecture Structural of ID_Stage is

    -- Direct entity instantiation (entity work.X) is used throughout
    -- this project instead of component declarations: the port list
    -- lives in exactly one place (the entity itself), so there's
    -- nothing here to fall out of sync with it.
    signal rs1_addr_wire : std_logic_vector(4 downto 0);
    signal rs2_addr_wire : std_logic_vector(4 downto 0);
    signal rd_addr_wire  : std_logic_vector(4 downto 0);
    signal funct3_wire   : std_logic_vector(2 downto 0);
    
    signal reg_data1_wire : std_logic_vector(31 downto 0);
    signal reg_data2_wire : std_logic_vector(31 downto 0);
    signal imm_ext_wire   : std_logic_vector(31 downto 0);
    
    signal imm_src_wire   : std_logic_vector(2 downto 0);
    signal alu_src_wire   : std_logic;
    signal alu_src_a_wire : std_logic;
    signal reg_write_wire : std_logic;
    signal mem_read_wire  : std_logic;
    signal mem_write_wire : std_logic;
    signal wb_sel_wire    : std_logic_vector(1 downto 0);
    signal branch_wire    : std_logic;
    signal jump_wire      : std_logic;
    signal alu_ctrl_wire  : std_logic_vector(3 downto 0);
    signal is_m_ext_wire  : std_logic;

begin

    rs1_addr_wire <= id_instr_in(19 downto 15);
    rs2_addr_wire <= id_instr_in(24 downto 20);
    rd_addr_wire  <= id_instr_in(11 downto 7);
    funct3_wire   <= id_instr_in(14 downto 12);

    id_rs1_addr_out <= rs1_addr_wire;
    id_rs2_addr_out <= rs2_addr_wire;
    id_rs1_data_out <= reg_data1_wire;
    id_rs2_data_out <= reg_data2_wire;

    U_REGFILE : entity work.RegFile
        port map (
            clk       => clk,
            rst_n     => rst_n,
            reg_write => wb_reg_write,
            rd_addr   => wb_rd_addr,
            rs1_addr  => rs1_addr_wire,
            rs2_addr  => rs2_addr_wire,
            rd_data   => wb_rd_data,
            rs1_data  => reg_data1_wire,
            rs2_data  => reg_data2_wire
        );

    U_CONTROL : entity work.Control_Unit
        port map (
            opcode    => id_instr_in(6 downto 0),
            funct3    => funct3_wire,
            funct7    => id_instr_in(31 downto 25),
            imm_src   => imm_src_wire,
            alu_src   => alu_src_wire,
            alu_src_a => alu_src_a_wire,
            reg_write => reg_write_wire,
            mem_read  => mem_read_wire,
            mem_write => mem_write_wire,
            wb_sel    => wb_sel_wire,
            branch    => branch_wire,
            jump      => jump_wire,
            alu_ctrl  => alu_ctrl_wire,
            is_m_ext  => is_m_ext_wire
        );

    U_IMMGEN : entity work.ImmGen
        port map (
            inst    => id_instr_in,
            imm_src => imm_src_wire,
            imm_ext => imm_ext_wire
        );

    U_ID_EX : entity work.ID_EX_Register
        port map (
            clk           => clk,
            rst_n         => rst_n,
            stall         => id_ex_stall,
            flush         => id_ex_flush,
            pc_in         => id_pc_in,
            pc_plus4_in   => id_pc_plus4_in,
            imm_ext_in    => imm_ext_wire,
            reg_data1_in  => reg_data1_wire,
            reg_data2_in  => reg_data2_wire,
            rs1_addr_in   => rs1_addr_wire,
            rs2_addr_in   => rs2_addr_wire,
            rd_addr_in    => rd_addr_wire,
            funct3_in     => funct3_wire,
            alu_src_in    => alu_src_wire,
            alu_src_a_in  => alu_src_a_wire,
            alu_ctrl_in   => alu_ctrl_wire,
            is_m_ext_in   => is_m_ext_wire,
            mem_read_in   => mem_read_wire,
            mem_write_in  => mem_write_wire,
            branch_in     => branch_wire,
            jump_in       => jump_wire,
            reg_write_in  => reg_write_wire,
            wb_sel_in     => wb_sel_wire,
            pc_out        => ex_pc_out,
            pc_plus4_out  => ex_pc_plus4_out,
            imm_ext_out   => ex_imm_ext_out,
            reg_data1_out => ex_reg_data1_out,
            reg_data2_out => ex_reg_data2_out,
            rs1_addr_out  => ex_rs1_addr_out,
            rs2_addr_out  => ex_rs2_addr_out,
            rd_addr_out   => ex_rd_addr_out,
            funct3_out    => ex_funct3_out,
            alu_src_out   => ex_alu_src_out,
            alu_src_a_out => ex_alu_src_a_out,
            alu_ctrl_out  => ex_alu_ctrl_out,
            is_m_ext_out  => ex_is_m_ext_out,
            mem_read_out  => ex_mem_read_out,
            mem_write_out => ex_mem_write_out,
            branch_out    => ex_branch_out,
            jump_out      => ex_jump_out,
            reg_write_out => ex_reg_write_out,
            wb_sel_out    => ex_wb_sel_out
        );

end architecture Structural;