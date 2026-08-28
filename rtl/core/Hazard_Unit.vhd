-- SPDX-License-Identifier: Apache-2.0
-- Copyright 2026 Ozan Akgül

library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;

-- Central pipeline hazard/stall/flush controller. Detects load-use
-- data hazards, multi-cycle M-extension stalls, bus wait-states, and
-- control hazards (taken branches/jumps), and drives the stall/flush
-- signals for every pipeline register accordingly. See the
-- architecture body below for the branch_pending state machine that
-- accounts for the instruction memory's fetch-in-flight timing when
-- flushing a stale pre-branch fetch.
entity Hazard_Unit is 
    port (
        -- System clock; used only by the internal branch_pending
        -- state register.
        clk           : in  std_logic;
        -- Active-low synchronous reset for branch_pending.
        rst_n         : in  std_logic;

        -- Asserted while the M-extension unit is performing a
        -- multi-cycle multiply/divide.
        stall_m       : in  std_logic;
        stall_wb_mem  : in  std_logic; -- High when WB bus transaction is waiting for ack
        -- Phase 5: high while an instruction fetch to SDRAM is
        -- outstanding (see rv32im_soc.vhd's if_bus_stall). Deliberately
        -- a separate port from stall_wb_mem rather than OR'd into it --
        -- see the dedicated case below for why.
        if_bus_stall  : in  std_logic;
        -- ID-stage source register 1 address, compared against
        -- ex_rd_addr for load-use hazard detection.
        id_rs1_addr   : in  std_logic_vector(4 downto 0);
        -- ID-stage source register 2 address, compared against
        -- ex_rd_addr for load-use hazard detection.
        id_rs2_addr   : in  std_logic_vector(4 downto 0);
        -- EX-stage destination register address.
        ex_rd_addr    : in  std_logic_vector(4 downto 0);
        -- Asserted when the EX-stage instruction is a load (source of
        -- a possible load-use hazard).
        ex_mem_read   : in  std_logic;
        -- Asserted when a branch/jump resolves as taken.
        take_branch   : in  std_logic;
        -- PC register write enable; deasserted to freeze the PC during
        -- a stall.
        pc_write      : out std_logic;
        -- Freezes the IF/ID pipeline register.
        if_id_stall   : out std_logic;
        -- Clears the IF/ID pipeline register (inserts a bubble).
        if_id_flush   : out std_logic;
        -- Freezes the ID/EX pipeline register.
        id_ex_stall   : out std_logic;
        -- Clears the ID/EX pipeline register (inserts a bubble).
        id_ex_flush   : out std_logic;
        -- Freezes the EX/MEM pipeline register.
        ex_mem_stall  : out std_logic;
        -- Freezes the MEM/WB pipeline register.
        mem_wb_stall  : out std_logic
    );
end entity Hazard_Unit;

architecture Behavioral of Hazard_Unit is

    -- bram_4kb's instruction port is a registered (synchronous) read, so
    -- a fetch issued the cycle a branch is taken is already in flight and
    -- lands in instr_fetch_in one cycle *after* take_branch is seen here.
    -- A single-cycle if_id_flush pulse (as in the original combinational
    -- design) would clear the pipeline too early, letting that stale
    -- pre-branch instruction slip into ID the following cycle.
    --
    -- branch_just_taken is a single registered pulse, high for exactly
    -- the one cycle immediately after take_branch -- the only cycle on
    -- which a stale pre-branch fetch could possibly land in IF/ID. If
    -- if_id_stall_comb is already '1' that cycle (IF/ID frozen for any
    -- reason -- a bus wait-state, a load-use hazard, or Phase 5's SDRAM
    -- if_bus_stall), the freeze itself already prevents the stale word
    -- from being latched, so no flush is needed and none is asserted.
    --
    -- Earlier version of this logic (branch_pending) stayed pending
    -- across every subsequent if_id_stall cycle and fired the flush
    -- whenever if_id_stall_comb *next* happened to drop -- correct only
    -- if that first post-branch cycle was guaranteed to be the one that
    -- captures the stale fetch. That assumption broke for a branch
    -- landing on an SDRAM address: if_bus_stall asserts immediately
    -- (freezing IF/ID before any stale word lands, per the paragraph
    -- above), so the "pending" flush instead fired many cycles later,
    -- on the cycle the CORRECT target instruction finally arrived from
    -- SDRAM -- silently replacing it with a bubble. Found via
    -- tb_if_sdram_fetch: the first SDRAM-resident instruction after a
    -- JALR into SDRAM never reached ID at all. Restricting the check to
    -- a single one-shot cycle (this version) fixes that: if the freeze
    -- is already up that one cycle, the flush is simply skipped rather
    -- than deferred.
    --
    -- This does not affect id_ex_flush, which flushes instructions
    -- already resident in pipeline registers (not a fetch in flight)
    -- and is unaffected by fetch latency of any kind.
    signal branch_just_taken   : std_logic := '0';
    signal if_id_stall_comb    : std_logic;
    signal take_branch_flush   : std_logic;

begin

    -- The one and only cycle this flush can take effect: the cycle right
    -- after a taken branch, and only if IF/ID isn't already frozen for
    -- some other reason this same cycle. take_branch itself is handled
    -- separately by case 4 below (unchanged, same-cycle flush of
    -- whatever's already resident in IF/ID).
    take_branch_flush <= branch_just_taken and not if_id_stall_comb;

process(clk)
begin
    if rising_edge(clk) then
        if rst_n = '0' then
            branch_just_taken <= '0';
        else
            branch_just_taken <= take_branch;
        end if;
    end if;
end process;

    -- Mirrors the if_id_stall conditions from cases 1-3 below, computed
    -- independently so take_branch_flush (used by the registered process
    -- above) does not depend on signals assigned inside process(all).
    if_id_stall_comb <= '1' when (stall_wb_mem = '1') or (stall_m = '1') or
        (ex_mem_read = '1' and (ex_rd_addr = id_rs1_addr or ex_rd_addr = id_rs2_addr) and ex_rd_addr /= "00000")
        or (if_bus_stall = '1')
        else '0';

process(all)
begin
    -- Default Assignments
    pc_write      <= '1';
    if_id_stall   <= '0';
    id_ex_stall   <= '0';
    ex_mem_stall  <= '0';
    mem_wb_stall  <= '0';
    if_id_flush   <= take_branch_flush;
    id_ex_flush   <= '0';

    -- 1. Global Bus Stall (SDRAM / Multi-cycle memory access wait-state)
    if stall_wb_mem = '1' then
        pc_write     <= '0';
        if_id_stall  <= '1';
        id_ex_stall  <= '1';
        ex_mem_stall <= '1';
        mem_wb_stall <= '1';
        if_id_flush  <= '0';
        id_ex_flush  <= '0';

    -- 2. Multi-Cycle M-Extension Stall Handling
    elsif stall_m = '1' then
        pc_write     <= '0';
        if_id_stall  <= '1';
        id_ex_stall  <= '1';
        ex_mem_stall <= '0';
        mem_wb_stall <= '0';
        if_id_flush  <= '0';
        id_ex_flush  <= '0';
    
    -- 3. Load-Use Data Hazard Detection (Freeze IF/ID, flush ID/EX with bubble)
    elsif ex_mem_read = '1' and (ex_rd_addr = id_rs1_addr or ex_rd_addr = id_rs2_addr) and ex_rd_addr /= "00000" then        
        pc_write     <= '0';
        if_id_stall  <= '1';
        id_ex_stall  <= '0';
        ex_mem_stall <= '0';
        mem_wb_stall <= '0';
        id_ex_flush  <= '1';
    
    -- 4. Instruction-Fetch Stall (SDRAM fetch in flight, no MEM-stage
    -- bus wait of its own -- that's cases 1/2 above). Freezes only the
    -- front of the pipe: IF/ID holds its position (there's nothing new
    -- to fetch yet) and ID/EX gets a bubble every cycle instead of being
    -- frozen, so EX/MEM/WB keep draining normally, governed solely by
    -- MEM_Stage's own bus_stall_o. Deliberately NOT merged into case 1's
    -- global freeze: prolonging ex_mem_stall/mem_wb_stall past a MEM
    -- transaction's own ack (which is level-driven off a frozen EX/MEM
    -- register) would re-assert wb_we_o/wb_stb_o/wb_cyc_o for extra
    -- cycles after that transaction already completed -- harmless for
    -- idempotent memory, but a real bug for a write with side effects
    -- (UART TX, GPIO, palette) getting re-executed.
    --
    -- This also takes priority over case 5 (branch) below: a branch
    -- resolving while a fetch is outstanding is held pending rather
    -- than applied immediately, so the outstanding SDRAM request is
    -- never abandoned mid-transaction. See CPU_FPGA.vhd's
    -- pending_branch/pending_target latch, which holds the redirect
    -- (take_branch is already that latched, "effective" signal by the
    -- time it reaches this port) until this case clears.
    elsif if_bus_stall = '1' then
        pc_write     <= '0';
        if_id_stall  <= '1';
        id_ex_stall  <= '0';
        ex_mem_stall <= '0';
        mem_wb_stall <= '0';
        id_ex_flush  <= '1';

    -- 5. Control Hazards (Branch / Jump Flushes)
    elsif take_branch = '1' then
        pc_write     <= '1';
        if_id_flush  <= '1';
        id_ex_flush  <= '1';
    end if;

end process;

end architecture Behavioral;