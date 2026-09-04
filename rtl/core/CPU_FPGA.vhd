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
    -- 2026-09-01: Hazard_Unit's own flush pulses (if_id_flush_hz/
    -- id_ex_flush_hz below) assume a taken branch is followed by AT
    -- MOST ONE stale in-flight fetch before the redirect lands --
    -- true for BRAM's fixed one-cycle latency, and still true for a
    -- single long contiguous SDRAM stall. instr_cache broke that:
    -- if_bus_stall now toggles on/off roughly every fetch instead of
    -- staying high for one stall, so while a branch redirect is stuck
    -- in pending_branch (deferred because take_branch resolved during
    -- a stall -- see that signal's comment), MULTIPLE separate
    -- wrong-path fetches each get their own brief non-stalled window
    -- and slip through the one-shot squash pulse to actually commit.
    -- Confirmed via tb_firmware_sdram: trap_loop's "j 8000002c"
    -- kept re-taking the branch correctly, but the LUI/ADDI/LW at
    -- 0x30/0x34/0x38 (wrong-path fetches issued while that redirect
    -- was pending) executed for real every pass, including a genuine
    -- MMIO read. pending_branch already flags exactly the window that
    -- needs squashing -- set the cycle a branch resolves-but-can't-
    -- apply, cleared the cycle it finally does -- so if_id_flush_wire/
    -- id_ex_flush_wire below OR it in on top of Hazard_Unit's own
    -- pulses, holding IF/ID and ID/EX squashed for the pending
    -- window's full duration instead of one cycle. Branches that never
    -- stall never set pending_branch, so this is a no-op for them.
    signal if_id_flush_hz    : std_logic;
    signal id_ex_flush_hz    : std_logic;
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
    signal id_pc_plus4       : std_logic_vector(31 downto 0);
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

    -- See if_id_flush_hz/id_ex_flush_hz's declaration above.
    if_id_flush_wire <= if_id_flush_hz or pending_branch;
    id_ex_flush_wire <= id_ex_flush_hz or pending_branch;

    -- pragma translate_off
    -- Temporary trace, narrow time window bracketing the tb_firmware_sdram
    -- UART duplicate-byte hang, to see what the PC/stall/branch signals
    -- are actually doing cycle-by-cycle. Remove once the bug is found.
    process (clk)
    begin
        if rising_edge(clk) then
            -- 2026-08-31: retargeted a second time -- the previous
            -- window (0x00000000-0x00000050) was based on a misreading:
            -- trap_loop (0x8000002c) is in the firmware image's own
            -- address space, not near physical 0x0. instr_cache's own
            -- fetch log confirms the CPU boots cleanly (the ~7.1ms of
            -- pc=0 before that is the expected pre-boot delay, not a
            -- hang) and then livelocks cycling
            -- 0x8000002c -> 0x80000030 -> 0x80000034 -> 0x80000034
            -- (again) -> 0x80000038 -> 0x8000002c forever, with
            -- 0x80000034 fetched twice every iteration -- despite
            -- 0x8000002c disassembling to "j 8000002c <trap_loop>", an
            -- unconditional self-jump that should never fall through.
            -- Retargeted to the real address range to see what EX/take_
            -- branch is doing there.
            -- 2026-09-01: retargeted again. The PC-window trigger is
            -- dead weight now that the boot-stub livelock is fixed (the
            -- CPU no longer sits in 0x2C-0x40). The open bug is a store
            -- that reaches the bus a second time after its base register
            -- has been clobbered by later instructions: 'A' is written
            -- correctly to UART_TX at 0xE0000008, and then written AGAIN
            -- to 0x00000008 -- which bus_interconnect decodes as BRAM --
            -- while the CPU is spinning in the 0x148/0x14C/0x150 UART
            -- busy-poll loop, whose own `lw a4,0(a5)` has by then
            -- overwritten a4 with 0. So trigger on any store in MEM or
            -- any asserted Wishbone write, and capture the EX pc and rs1
            -- value that produced it: a replayed store shows up as the
            -- same ex_pc appearing twice, the second time with
            -- reg_data1=00000000.
            if mem_mem_write = '1' or wb_we_o = '1' then
                report "CPU trace: pc=" & to_hstring(pc_current) &
                       " take_branch_wire=" & std_logic'image(take_branch_wire) &
                       " target_pc_wire=" & to_hstring(target_pc_wire) &
                       " if_bus_stall_i=" & std_logic'image(if_bus_stall_i) &
                       " bus_stall_wire=" & std_logic'image(bus_stall_wire) &
                       " pending_branch=" & std_logic'image(pending_branch) &
                       " take_branch_eff=" & std_logic'image(take_branch_eff) &
                       " target_pc_eff=" & to_hstring(target_pc_eff) &
                       " id_ex_flush=" & std_logic'image(id_ex_flush_wire) &
                       " id_ex_stall=" & std_logic'image(id_ex_stall_wire) &
                       " if_sdram_ack_i=" & std_logic'image(if_sdram_ack_i) &
                       " imem_addr_o=" & to_hstring(imem_addr_o) &
                       " imem_rdata_i=" & to_hstring(imem_rdata_i) &
                       " id_pc=" & to_hstring(id_pc) &
                       " @ " & time'image(now);

                -- 2026-08-31: extended for the GPIO_LED=0xF-lands-at-
                -- address-0 investigation. id_instr/id_rs*_data show what
                -- ID decoded the store as and what base value it read;
                -- ex_rs1_addr/ex_reg_data1/ex_mem_write show the same
                -- store one stage later, after forwarding; mem_addr/
                -- mem_mem_write/mem_write_data show what actually reached
                -- the bus. Comparing these across the same instruction as
                -- it moves ID -> EX -> MEM should show which stage first
                -- turns 0xE0000000 into 0x00000000 (or the store's rs1
                -- into something else entirely). Remove once found.
                report "  ID: instr=" & to_hstring(id_instr) &
                       " rs1=" & to_hstring(id_rs1_addr) &
                       " rs1_data=" & to_hstring(id_rs1_data) &
                       " rs2=" & to_hstring(id_rs2_addr) &
                       " rs2_data=" & to_hstring(id_rs2_data) &
                       "  EX: pc=" & to_hstring(ex_pc) &
                       " rs1=" & to_hstring(ex_rs1_addr) &
                       " reg_data1=" & to_hstring(ex_reg_data1) &
                       " reg_data2=" & to_hstring(ex_reg_data2) &
                       " alu_src_a=" & std_logic'image(ex_alu_src_a) &
                       " mem_write=" & std_logic'image(ex_mem_write) &
                       " reg_write=" & std_logic'image(ex_reg_write) &
                       " rd=" & to_hstring(ex_rd_addr) &
                       "  MEM: addr=" & to_hstring(mem_addr) &
                       " write_data=" & to_hstring(mem_write_data) &
                       " mem_write=" & std_logic'image(mem_mem_write) &
                       " rd=" & to_hstring(mem_rd_addr) &
                       "  BUS: wb_addr=" & to_hstring(wb_addr_o) &
                       " wb_data=" & to_hstring(wb_data_o) &
                       " wb_sel=" & to_hstring(wb_sel_o) &
                       " wb_we=" & std_logic'image(wb_we_o) &
                       " wb_stb=" & std_logic'image(wb_stb_o) &
                       " wb_cyc=" & std_logic'image(wb_cyc_o) &
                       " wb_ack=" & std_logic'image(wb_ack_i) &
                       " bus_stall=" & std_logic'image(bus_stall_wire) &
                       " ex_mem_stall=" & std_logic'image(ex_mem_stall_wire) &
                       " mem_wb_stall=" & std_logic'image(mem_wb_stall_wire) &
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
            id_pc_plus4_out => id_pc_plus4,
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
            id_pc_plus4_in   => id_pc_plus4,
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
            if_id_flush   => if_id_flush_hz,
            id_ex_stall   => id_ex_stall_wire,
            id_ex_flush   => id_ex_flush_hz,
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