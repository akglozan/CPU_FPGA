-- SPDX-License-Identifier: Apache-2.0
-- Copyright 2026 Ozan Akgül

library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;

entity CPU_FPGA is
    generic (
        DATA_WIDTH : integer := 32
    );
    port (
        clk             : in  std_logic;
        rst_n           : in  std_logic;
        
        -- Instruction Fetch Bus (Port A of BRAM)
        imem_addr_out   : out std_logic_vector(31 downto 0);
        imem_rdata_in   : in  std_logic_vector(31 downto 0);
        
        -- Debug Outputs
        pc_debug        : out std_logic_vector(DATA_WIDTH-1 downto 0);
        instr_debug     : out std_logic_vector(DATA_WIDTH-1 downto 0);
        rs1_debug       : out std_logic_vector(DATA_WIDTH-1 downto 0);
        rs2_debug       : out std_logic_vector(DATA_WIDTH-1 downto 0);
        
        -- Wishbone B4 Master Bus Interface (Data Side)
        wb_adr_o        : out std_logic_vector(DATA_WIDTH-1 downto 0);
        wb_dat_o        : out std_logic_vector(DATA_WIDTH-1 downto 0);
        wb_dat_i        : in  std_logic_vector(DATA_WIDTH-1 downto 0);
        wb_sel_o        : out std_logic_vector(3 downto 0);
        wb_we_o         : out std_logic;
        wb_stb_o        : out std_logic;
        wb_cyc_o        : out std_logic;
        wb_ack_i        : in  std_logic
    );
end entity CPU_FPGA;

architecture Structural of CPU_FPGA is

    signal pc_write_wire     : std_logic;
    signal if_id_stall_wire  : std_logic;
    signal if_id_flush_wire  : std_logic;
    signal id_ex_stall_wire  : std_logic;
    signal id_ex_flush_wire  : std_logic;
    signal ex_mem_stall_wire : std_logic;
    signal mem_wb_stall_wire : std_logic;
    signal take_branch_wire  : std_logic;
    signal target_pc_wire    : std_logic_vector(31 downto 0);
    signal stall_m_wire      : std_logic;
    signal bus_stall_wire    : std_logic;

    signal pc_current        : std_logic_vector(31 downto 0);
    signal id_pc             : std_logic_vector(31 downto 0);
    signal id_instr          : std_logic_vector(31 downto 0);
    signal id_rs1_addr       : std_logic_vector(4 downto 0);
    signal id_rs2_addr       : std_logic_vector(4 downto 0);
    signal id_rs1_data       : std_logic_vector(31 downto 0);
    signal id_rs2_data       : std_logic_vector(31 downto 0);

    signal ex_pc             : std_logic_vector(31 downto 0);
    signal ex_pc_plus4       : std_logic_vector(31 downto 0);
    signal ex_imm_ext        : std_logic_vector(31 downto 0);
    signal ex_reg_data1      : std_logic_vector(31 downto 0);
    signal ex_reg_data2      : std_logic_vector(31 downto 0);
    signal ex_rs1_addr       : std_logic_vector(4 downto 0);
    signal ex_rs2_addr       : std_logic_vector(4 downto 0);
    signal ex_rd_addr        : std_logic_vector(4 downto 0);
    signal ex_funct3         : std_logic_vector(2 downto 0);
    signal ex_alu_src        : std_logic;
    signal ex_alu_src_a      : std_logic;
    signal ex_alu_ctrl       : std_logic_vector(3 downto 0);
    signal ex_is_m_ext       : std_logic;
    signal ex_mem_read       : std_logic;
    signal ex_mem_write      : std_logic;
    signal ex_branch         : std_logic;
    signal ex_jump           : std_logic;
    signal ex_reg_write      : std_logic;
    signal ex_wb_sel         : std_logic_vector(1 downto 0);

    signal mem_result        : std_logic_vector(31 downto 0);
    signal mem_write_data    : std_logic_vector(31 downto 0);
    signal mem_rd_addr       : std_logic_vector(4 downto 0);
    signal mem_pc_plus4      : std_logic_vector(31 downto 0);
    signal mem_reg_write     : std_logic;
    signal mem_mem_read      : std_logic;
    signal mem_mem_write     : std_logic;
    signal mem_wb_sel        : std_logic_vector(1 downto 0);
    signal mem_funct3        : std_logic_vector(2 downto 0);
    signal mem_result_fwd    : std_logic_vector(31 downto 0);

    signal wb_result         : std_logic_vector(31 downto 0);
    signal wb_read_data      : std_logic_vector(31 downto 0);
    signal wb_rd_addr        : std_logic_vector(4 downto 0);
    signal wb_reg_write      : std_logic;
    signal wb_sel            : std_logic_vector(1 downto 0);
    signal wb_rd_data        : std_logic_vector(31 downto 0);
    signal wb_pc_plus4       : std_logic_vector(31 downto 0);

begin

    -- 1. Instruction Fetch Stage
    U_STAGE_IF : entity work.IF_Stage
        generic map ( 
            DATA_WIDTH => DATA_WIDTH 
        )
        port map (
            clk             => clk,
            rst_n           => rst_n,
            pc_write        => pc_write_wire,
            if_id_stall     => if_id_stall_wire,
            if_id_flush     => if_id_flush_wire,
            pc_src          => take_branch_wire,
            target_pc       => target_pc_wire,
            pc_fetch_out    => imem_addr_out,
            instr_fetch_in  => imem_rdata_in,
            pc_current_out  => pc_current,
            id_pc_out       => id_pc,
            id_instr_out    => id_instr
        );

    -- 2. Instruction Decode Stage
    U_STAGE_ID : entity work.ID_Stage
        port map (
            clk              => clk,
            rst_n            => rst_n,
            id_ex_stall      => id_ex_stall_wire,
            id_ex_flush      => id_ex_flush_wire,
            id_pc_in         => id_pc,
            id_pc_plus4_in   => std_logic_vector(unsigned(id_pc) + 4),
            id_instr_in      => id_instr,
            wb_reg_write     => wb_reg_write,
            wb_rd_addr       => wb_rd_addr,
            wb_rd_data       => wb_rd_data,
            id_rs1_addr_out  => id_rs1_addr,
            id_rs2_addr_out  => id_rs2_addr,
            id_rs1_data_out  => id_rs1_data,
            id_rs2_data_out  => id_rs2_data,
            ex_pc_out        => ex_pc,
            ex_pc_plus4_out  => ex_pc_plus4,
            ex_imm_ext_out   => ex_imm_ext,
            ex_reg_data1_out => ex_reg_data1,
            ex_reg_data2_out => ex_reg_data2,
            ex_rs1_addr_out  => ex_rs1_addr,
            ex_rs2_addr_out  => ex_rs2_addr,
            ex_rd_addr_out   => ex_rd_addr,
            ex_funct3_out    => ex_funct3,
            ex_alu_src_out   => ex_alu_src,
            ex_alu_src_a_out => ex_alu_src_a,
            ex_alu_ctrl_out  => ex_alu_ctrl,
            ex_is_m_ext_out  => ex_is_m_ext,
            ex_mem_read_out  => ex_mem_read,
            ex_mem_write_out => ex_mem_write,
            ex_branch_out    => ex_branch,
            ex_jump_out      => ex_jump,
            ex_reg_write_out => ex_reg_write,
            ex_wb_sel_out    => ex_wb_sel
        );

    -- 3. Execute Stage
    U_STAGE_EX : entity work.EX_Stage
        port map (
            clk                     => clk,
            rst_n                   => rst_n,
            stall_ex_mem_in         => ex_mem_stall_wire,
            ex_pc_in                => ex_pc,
            ex_pc_plus4_in          => ex_pc_plus4,
            ex_imm_ext_in           => ex_imm_ext,
            ex_reg_data1_in         => ex_reg_data1,
            ex_reg_data2_in         => ex_reg_data2,
            ex_rs1_addr_in          => ex_rs1_addr,
            ex_rs2_addr_in          => ex_rs2_addr,
            ex_rd_addr_in           => ex_rd_addr,
            ex_funct3_in            => ex_funct3,
            ex_alu_src_in           => ex_alu_src,
            ex_alu_src_a_in         => ex_alu_src_a,
            ex_alu_ctrl_in          => ex_alu_ctrl,
            ex_is_m_ext_in          => ex_is_m_ext,
            ex_mem_read_in          => ex_mem_read,
            ex_mem_write_in         => ex_mem_write,
            ex_branch_in            => ex_branch,
            ex_jump_in              => ex_jump,
            ex_reg_write_in         => ex_reg_write,
            ex_wb_sel_in            => ex_wb_sel,
            mem_rd_addr_in          => mem_rd_addr,
            mem_reg_write_in        => mem_reg_write,
            mem_mem_read_in         => mem_mem_read,
            mem_result_in           => mem_result_fwd,
            wb_rd_addr_in           => wb_rd_addr,
            wb_reg_write_in         => wb_reg_write,
            wb_rd_data_in           => wb_rd_data,
            take_branch_out         => take_branch_wire,
            target_pc_out           => target_pc_wire,
            stall_m_out             => stall_m_wire,
            mem_result_out          => mem_result,
            mem_write_data_out      => mem_write_data,
            mem_rd_addr_out         => mem_rd_addr,
            mem_pc_plus4_out        => mem_pc_plus4,
            mem_reg_write_out       => mem_reg_write,
            mem_mem_read_out        => mem_mem_read,
            mem_mem_write_out       => mem_mem_write,
            mem_wb_sel_out          => mem_wb_sel,
            mem_funct3_out          => mem_funct3
        );

    -- 4. Memory Stage (Wishbone Master)
    U_STAGE_MEM : entity work.MEM_Stage
        port map (
            clk                 => clk,
            rst_n               => rst_n,
            stall_wb            => mem_wb_stall_wire,
            mem_result_in       => mem_result,
            mem_write_data_in   => mem_write_data, 
            mem_rd_addr_in      => mem_rd_addr,
            mem_pc_plus4_in     => mem_pc_plus4,
            mem_reg_write_in    => mem_reg_write,
            mem_mem_read_in     => mem_mem_read,
            mem_mem_write_in    => mem_mem_write,
            mem_wb_sel_in       => mem_wb_sel,
            mem_funct3_in       => mem_funct3,
            wb_adr_o            => wb_adr_o,
            wb_dat_o            => wb_dat_o,
            wb_dat_i            => wb_dat_i,
            wb_sel_o            => wb_sel_o,
            wb_we_o             => wb_we_o,
            wb_stb_o            => wb_stb_o,
            wb_cyc_o            => wb_cyc_o,
            wb_ack_i            => wb_ack_i,
            bus_stall_out       => bus_stall_wire,
            mem_result_fwd_out  => mem_result_fwd,
            wb_result_out       => wb_result,
            wb_read_data_out    => wb_read_data,
            wb_rd_addr_out      => wb_rd_addr,
            wb_reg_write_out    => wb_reg_write,
            wb_sel_out          => wb_sel,
            wb_pc_plus4_out     => wb_pc_plus4
        );

    -- 5. Hazard & Pipeline Stall Unit
    U_HAZARD : entity work.Hazard_Unit
        port map (
            stall_m       => stall_m_wire,
            stall_wb_mem  => bus_stall_wire,
            id_rs1_addr   => id_rs1_addr,
            id_rs2_addr   => id_rs2_addr,
            ex_rd_addr    => ex_rd_addr,
            ex_mem_read   => ex_mem_read,
            take_branch   => take_branch_wire,
            pc_write      => pc_write_wire,
            if_id_stall   => if_id_stall_wire,
            if_id_flush   => if_id_flush_wire,
            id_ex_stall   => id_ex_stall_wire,
            id_ex_flush   => id_ex_flush_wire,
            ex_mem_stall  => ex_mem_stall_wire,
            mem_wb_stall  => mem_wb_stall_wire
        );

    -- Writeback Multiplexer
    with wb_sel select
        wb_rd_data <= wb_result       when "00",
                      wb_read_data    when "01",
                      wb_pc_plus4     when "10",
                      (others => '0') when others;

    -- Debug Signals
    pc_debug    <= pc_current;
    instr_debug <= id_instr;
    rs1_debug   <= id_rs1_data;
    rs2_debug   <= id_rs2_data;

end architecture Structural;