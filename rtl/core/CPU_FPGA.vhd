-- SPDX-License-Identifier: Apache-2.0
-- Copyright 2026 Ozan Akgül

library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;

-- Top-level 5-stage pipelined RV32IM CPU core (IF/ID/EX/MEM/WB), with
-- full hazard detection, operand forwarding, and stall/flush control.
-- Composed here from IF_Stage, ID_Stage, EX_Stage, MEM_Stage, and
-- Hazard_Unit. Presents a simple synchronous-read port for instruction
-- fetch (external BRAM) and a Wishbone B4 master interface for the
-- data side (loads/stores to SDRAM/MMIO via the system bus).
entity CPU_FPGA is
    generic (
        -- Datapath / address width in bits (32 for RV32).
        DATA_WIDTH : integer := 32
    );
    port (
        clk             : in  std_logic;
        -- Active-low synchronous reset.
        rst_n           : in  std_logic;
        
        -- Instruction Fetch Bus (Port A of BRAM)
        -- Fetch address presented to the external instruction BRAM.
        imem_addr_o     : out std_logic_vector(31 downto 0);
        -- Instruction word returned by the BRAM (one cycle after the
        -- address was presented), or the SDRAM fetch path's data when
        -- pc is in SDRAM range -- rv32im_soc.vhd muxes the two.
        imem_rdata_i    : in  std_logic_vector(31 downto 0);

        -- Phase 5: high while an instruction fetch to SDRAM is
        -- outstanding (rv32im_soc.vhd's if_bus_stall). Feeds
        -- Hazard_Unit's dedicated fetch-stall case.
        if_bus_stall_i  : in  std_logic;
        -- Phase 5: pulses the one cycle a SDRAM-sourced instruction is
        -- being captured into IF_ID_Register. Feeds IF_Stage's
        -- pc_in_to_ifid mux (see IF_Stage.vhd for why that's needed).
        if_sdram_ack_i  : in  std_logic;

        -- Debug Outputs
        -- Current program counter, for on-chip debug (SignalTap/etc.).
        pc_debug        : out std_logic_vector(DATA_WIDTH-1 downto 0);
        -- Instruction currently in the ID stage, for debug.
        instr_debug     : out std_logic_vector(DATA_WIDTH-1 downto 0);
        -- ID-stage rs1 register file read data, for debug.
        rs1_debug       : out std_logic_vector(DATA_WIDTH-1 downto 0);
        -- ID-stage rs2 register file read data, for debug.
        rs2_debug       : out std_logic_vector(DATA_WIDTH-1 downto 0);
        
        -- Wishbone B4 Master Bus Interface (Data Side)
        wb_addr_o       : out std_logic_vector(DATA_WIDTH-1 downto 0);
        wb_data_o       : out std_logic_vector(DATA_WIDTH-1 downto 0);
        wb_data_i       : in  std_logic_vector(DATA_WIDTH-1 downto 0);
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

    -- Phase 5: take_branch_wire/target_pc_wire are EX_Stage's raw,
    -- single-cycle combinational outputs -- valid only the one cycle a
    -- branch resolves, since EX_Stage moves on to whatever's next
    -- (a bubble, if id_ex_flush fired) the very next cycle regardless.
    -- Hazard_Unit's existing branch_pending mechanism only remembers
    -- THAT a branch happened (a one-bit flag), which was enough when
    -- the redirect always applies the very next cycle (BRAM's fixed
    -- one-cycle fetch latency). It is not enough here: if a branch
    -- resolves while if_bus_stall_i is asserted, case 4 in Hazard_Unit
    -- deliberately holds pc_write low rather than apply the redirect
    -- (see that case's comment for why -- aborting the in-flight SDRAM
    -- fetch is what we're avoiding), and that stall can run for many
    -- cycles. Without latching WHERE to jump, target_pc_wire would be
    -- long gone (EX_Stage having moved on to other instructions) by the
    -- time the redirect is finally allowed to happen, and the branch
    -- would be silently dropped. pending_branch/pending_target hold it.
    signal pending_branch  : std_logic := '0';
    signal pending_target  : std_logic_vector(31 downto 0) := (others => '0');
    signal take_branch_eff : std_logic;
    signal target_pc_eff   : std_logic_vector(31 downto 0);

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
    signal mem_addr : std_logic_vector(31 downto 0);

    signal wb_result         : std_logic_vector(31 downto 0);
    signal wb_read_data      : std_logic_vector(31 downto 0);
    signal wb_rd_addr        : std_logic_vector(4 downto 0);
    signal wb_reg_write      : std_logic;
    signal wb_sel            : std_logic_vector(1 downto 0);
    signal wb_rd_data        : std_logic_vector(31 downto 0);
    signal wb_pc_plus4       : std_logic_vector(31 downto 0);

begin

    -- Phase 5 branch-target latch. Set the cycle a branch resolves while
    -- a SDRAM fetch is outstanding (can't apply it yet); applied (and
    -- cleared) the cycle the fetch finally completes. See the signals'
    -- declaration above for the full rationale.
    -- 2026-08-29: if_bus_stall_i alone isn't the whole story -- Hazard_
    -- Unit's case 1 (stall_wb_mem, fed by bus_stall_wire below) holds
    -- pc_write low for exactly the same reason (a data-side store/load,
    -- e.g. a UART_TX write, still waiting on its own bus ack), but this
    -- pending-branch latch previously only watched if_bus_stall_i. A
    -- branch resolving (take_branch_wire='1', target_pc_wire valid for
    -- that one cycle only) while bus_stall_wire='1' and if_bus_stall_i='0'
    -- was falling straight through: take_branch_eff went high that same
    -- cycle even though pc_write was held low by Hazard_Unit, and by the
    -- time the stall actually cleared, target_pc_wire had already moved
    -- on to whatever EX_Stage computed next -- silently replaying
    -- already-executed instructions once the stall released. Confirmed
    -- via tb_firmware_sdram: uart_putc's busy-poll loop (a backward
    -- bnez) resolving while the previous uart_putc's own UART_TX store
    -- was still stall_wb_mem-stalled caused already-sent bytes ('B',
    -- then 'A') to be physically retransmitted before the real next
    -- byte ('C') finally went out -- see uart_tx.vhd's debug report log,
    -- which shows genuine, fully-framed duplicate transmissions, not
    -- bit-level corruption. The process and take_branch_eff below now
    -- OR in bus_stall_wire alongside if_bus_stall_i so the same
    -- latch-and-defer mechanism covers either stall source.
    process (clk)
    begin
        if rising_edge(clk) then
            if rst_n = '0' then
                pending_branch <= '0';
                pending_target <= (others => '0');
            elsif take_branch_wire = '1' and
                  (if_bus_stall_i = '1' or bus_stall_wire = '1') then
                pending_branch <= '1';
                pending_target <= target_pc_wire;
            elsif pending_branch = '1' and
                  if_bus_stall_i = '0' and bus_stall_wire = '0' then
                pending_branch <= '0';
            end if;
        end if;
    end process;

    -- Whenever neither stall source ever asserts, pending_branch stays 0
    -- forever and these reduce to exactly take_branch_wire/target_pc_wire
    -- -- unchanged behavior for anything that never hits a bus wait.
    take_branch_eff <= '1' when if_bus_stall_i = '0' and bus_stall_wire = '0' and
                                 (take_branch_wire = '1' or pending_branch = '1')
                        else '0';
    target_pc_eff   <= pending_target when pending_branch = '1' else target_pc_wire;

    -- pragma translate_off
    -- Temporary trace, narrow time window bracketing the tb_firmware_sdram
    -- UART duplicate-byte hang, to see what the PC/stall/branch signals
    -- are actually doing cycle-by-cycle. Remove once the bug is found.
    process (clk)
    begin
        if rising_edge(clk) then
            if now >= 7290000 ns and now <= 7345000 ns then
                report "CPU trace: pc=" & to_hstring(pc_current) &
                       " take_branch_wire=" & std_logic'image(take_branch_wire) &
                       " target_pc_wire=" & to_hstring(target_pc_wire) &
                       " if_bus_stall_i=" & std_logic'image(if_bus_stall_i) &
                       " bus_stall_wire=" & std_logic'image(bus_stall_wire) &
                       " pending_branch=" & std_logic'image(pending_branch) &
                       " take_branch_eff=" & std_logic'image(take_branch_eff) &
                       " target_pc_eff=" & to_hstring(target_pc_eff) &
                       " @ " & time'image(now);
            end if;
        end if;
    end process;
    -- pragma translate_on

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
            pc_src          => take_branch_eff,
            target_pc       => target_pc_eff,
            if_sdram_ack    => if_sdram_ack_i,
            pc_fetch_out    => imem_addr_o,
            instr_fetch_in  => imem_rdata_i,
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
            mem_addr_out            => mem_addr,
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

    -- Forward the EX/MEM-registered ALU/memory result back into EX_Stage's
    -- forwarding mux (forward_a/forward_b = "10" selects this signal).
    mem_result_fwd <= mem_result;

    -- 4. Memory Stage (Wishbone Master)
    u_mem_stage : entity work.MEM_Stage
    port map (
        clk   => clk,
        rst_n => rst_n,

        stall_wb => mem_wb_stall_wire,

        mem_addr       => mem_addr,
        mem_result     => mem_result,
        mem_write_data => mem_write_data,
        mem_rd_addr    => mem_rd_addr,
        mem_pc_plus4   => mem_pc_plus4,

        mem_reg_write  => mem_reg_write,
        mem_read       => mem_mem_read,
        mem_write      => mem_mem_write,
        mem_wb_sel     => mem_wb_sel,
        mem_funct3     => mem_funct3,

        wb_addr_o      => wb_addr_o,
        wb_data_o      => wb_data_o,
        wb_data_i      => wb_data_i,
        wb_sel_bus_o   => wb_sel_o,
        wb_we_o        => wb_we_o,
        wb_stb_o       => wb_stb_o,
        wb_cyc_o       => wb_cyc_o,
        wb_ack_i       => wb_ack_i,

        bus_stall_o    => bus_stall_wire,

        wb_result_o    => wb_result,
        wb_read_data_o => wb_read_data,
        wb_rd_addr_o   => wb_rd_addr,
        wb_pc_plus4_o  => wb_pc_plus4,
        wb_reg_write_o => wb_reg_write,
        wb_sel_o       => wb_sel
    );

    -- 5. Hazard & Pipeline Stall Unit
    U_HAZARD : entity work.Hazard_Unit
        port map (
            clk           => clk,
            rst_n         => rst_n,
            stall_m       => stall_m_wire,
            stall_wb_mem  => bus_stall_wire,
            if_bus_stall  => if_bus_stall_i,
            id_rs1_addr   => id_rs1_addr,
            id_rs2_addr   => id_rs2_addr,
            ex_rd_addr    => ex_rd_addr,
            ex_mem_read   => ex_mem_read,
            take_branch   => take_branch_eff,
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