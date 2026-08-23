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
    -- branch_pending tracks "there is a stale pre-branch fetch still in
    -- flight that needs to be discarded." It is set the cycle a branch is
    -- taken, and stays set across any intervening if_id_stall cycles
    -- (bus wait-states, load-use hazards) since IF_ID_Register is frozen
    -- during those and the stale instruction hasn't landed yet anyway.
    -- It only clears on the cycle the flush actually takes effect (i.e.
    -- if_id_stall = '0'), which is also the cycle it forces if_id_flush.
    -- This does not affect id_ex_flush, which flushes instructions
    -- already resident in pipeline registers (not a fetch in flight)
    -- and is unaffected by BRAM latency.
    signal branch_pending      : std_logic := '0';
    signal if_id_stall_comb    : std_logic;
    signal take_branch_flush   : std_logic;

begin

    -- Cycle this flush actually takes effect: pending from a PRIOR taken
    -- branch, and IF/ID is not frozen this cycle. take_branch itself is
    -- handled separately by case 4 below (unchanged, same-cycle flush of
    -- whatever's already resident in IF/ID); this signal only covers the
    -- following cycle's stale in-flight fetch.
    take_branch_flush <= branch_pending and not if_id_stall_comb;

process(clk)
begin
    if rising_edge(clk) then
        if rst_n = '0' then
            branch_pending <= '0';
        elsif take_branch = '1' then
            -- A new branch always (re-)arms the pending flag, even if a
            -- previously pending flush is also resolving this same cycle
            -- (back-to-back taken branches) -- the new branch's own fetch
            -- is now in flight and needs its own future flush.
            branch_pending <= '1';
        elsif take_branch_flush = '1' then
            branch_pending <= '0';
        end if;
    end if;
end process;

    -- Mirrors the if_id_stall conditions from cases 1-3 below, computed
    -- independently so take_branch_flush (used by the registered process
    -- above) does not depend on signals assigned inside process(all).
    if_id_stall_comb <= '1' when (stall_wb_mem = '1') or (stall_m = '1') or
        (ex_mem_read = '1' and (ex_rd_addr = id_rs1_addr or ex_rd_addr = id_rs2_addr) and ex_rd_addr /= "00000")
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
    
    -- 4. Control Hazards (Branch / Jump Flushes)
    elsif take_branch = '1' then
        pc_write     <= '1';
        if_id_flush  <= '1';
        id_ex_flush  <= '1';
    end if;

end process;

end architecture Behavioral;