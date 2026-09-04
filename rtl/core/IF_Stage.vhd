-- SPDX-License-Identifier: Apache-2.0
-- Copyright 2026 Ozan Akgül

library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;

-- IF-stage top-level wrapper: instantiates the Program_Counter and
-- IF_ID_Register, and re-aligns the fetched instruction with the PC
-- that produced it to account for the instruction memory's one-cycle
-- registered read latency (see pc_delayed in the architecture body).
entity IF_Stage is
    generic (
        -- PC / address width in bits.
        DATA_WIDTH : integer := 32
    );
    port (
        clk             : in  std_logic;
        -- Active-low synchronous reset.
        rst_n           : in  std_logic;
        
        -- Hazard Controls
        -- Forwarded to Program_Counter; deasserted to freeze the PC
        -- during a pipeline stall.
        pc_write        : in  std_logic;
        -- Forwarded to IF_ID_Register; freezes the PC/instruction pair
        -- during a stall.
        if_id_stall     : in  std_logic;
        -- Forwarded to IF_ID_Register; inserts a NOP bubble.
        if_id_flush     : in  std_logic;
        
        -- Branch / Jump Controls
        -- Selects the next PC source: PC+4, or target_pc.
        pc_src          : in  std_logic;
        -- Branch/jump target address.
        target_pc       : in  std_logic_vector(31 downto 0);

        -- 2026-08-31: no longer used within this architecture -- see
        -- pc_fetch_delayed's comment in the architecture body for what
        -- replaced the if_sdram_ack-keyed mux this port used to drive.
        -- Left in the port list rather than removed, to avoid touching
        -- every instantiation's port map for a pure no-op removal.
        if_sdram_ack    : in  std_logic;

        -- External Instruction Memory / BRAM Interface
        -- PC value driven out to the instruction memory this cycle.
        pc_fetch_out    : out std_logic_vector(31 downto 0);
        -- Instruction word returned by the instruction memory (one
        -- cycle after pc_fetch_out was presented).
        instr_fetch_in  : in  std_logic_vector(31 downto 0);
        
        -- Outputs to ID Stage & Debug
        -- Current PC value, exposed for debug.
        pc_current_out  : out std_logic_vector(31 downto 0);
        -- PC value passed into the ID stage.
        id_pc_out       : out std_logic_vector(31 downto 0);
        -- PC + 4 value passed into the ID stage.
        id_pc_plus4_out : out std_logic_vector(31 downto 0);
        -- Instruction word passed into the ID stage.
        id_instr_out    : out std_logic_vector(31 downto 0)
    );
end entity IF_Stage;

architecture Structural of IF_Stage is

    signal pc_wire             : std_logic_vector(31 downto 0);
    signal pc_plus4_wire       : std_logic_vector(31 downto 0);

    -- bram_4kb's instruction-fetch port is now a registered (synchronous)
    -- read: the data for the address presented on pc_fetch_out in cycle N
    -- only appears on instr_fetch_in in cycle N+1. pc_wire itself has
    -- already moved on to the *next* fetch address by then, so it can no
    -- longer be used directly as the PC that matches instr_fetch_in.
    -- pc_delayed re-aligns them: it captures pc_wire one cycle behind,
    -- so in the same cycle that instr_fetch_in becomes valid for a given
    -- fetch, pc_delayed holds the PC that produced it. It freezes under
    -- the same if_id_stall condition as IF_ID_Register so the two stay
    -- in lockstep during multi-cycle stalls (load-use hazards, bus
    -- wait-states) rather than sliding out of sync.
    signal pc_delayed          : std_logic_vector(31 downto 0) := (others => '0');
    signal pc_plus4_delayed    : std_logic_vector(31 downto 0) := (others => '0');

    -- 2026-08-31: pc_delayed's own one-cycle capture only re-aligns
    -- correctly for a fixed one-cycle memory (BRAM). The previous fix
    -- for SDRAM's multi-cycle latency tried to detect the ack cycle
    -- combinationally (pc_wire when if_sdram_ack = '1' else pc_delayed)
    -- and grab pc_wire directly, on the theory that pc_write being held
    -- low for the whole stall keeps pc_wire pinned at the right address
    -- until the ack arrives. That's true up to but NOT including the
    -- ack cycle itself: if pc_write releases the same cycle if_sdram_ack
    -- fires, pc_wire is read here before Program_Counter's own next-
    -- cycle advance takes effect, so it usually still holds the frozen
    -- address -- but there is no guarantee the two happen in that order,
    -- and tb_firmware_sdram caught a cycle where IF_ID_Register latched
    -- pc = (a fresh address) paired with instruction_in = (the previous
    -- fetch's stale word), one full word out of pairing -- see the
    -- 2026-08-31 CPU trace investigation for the exact cycle.
    --
    -- pc_fetch_out already does the job we actually need, for both BRAM
    -- and SDRAM: it holds the outstanding fetch address steady for the
    -- entire stall, however long it runs (see the comment below). So
    -- instead of guessing which cycle is "the" ack cycle, just delay
    -- pc_fetch_out by one clock, unconditionally -- no stall-gating, no
    -- if_sdram_ack. Because pc_fetch_out never moves while if_id_stall
    -- is high, this one-cycle-behind copy is *always* the address whose
    -- data is arriving on instr_fetch_in this cycle, whether that took
    -- 1 cycle or 100 -- the same guarantee pc_delayed gives for the
    -- fixed-latency BRAM case, just built from the signal that's
    -- actually held constant through a variable-length stall.
    signal pc_plus4_fetch_out     : std_logic_vector(31 downto 0);
    signal pc_fetch_delayed       : std_logic_vector(31 downto 0) := (others => '0');
    signal pc_plus4_fetch_delayed : std_logic_vector(31 downto 0) := (others => '0');

    -- 2026-09-01: wrong-path fetch squash, decided by IDENTITY rather
    -- than by timing.
    --
    -- Hazard_Unit's branch_just_taken one-shot assumes at most ONE stale
    -- fetch can be in flight when a redirect lands -- true for
    -- bram_4kb's fixed one-cycle registered read, which is what it was
    -- sized for. instr_cache is two cycles (S_IDLE latches the address,
    -- S_COMPARE registers cpu_ack_o/cpu_dat_o, so the word lands two
    -- cycles later), so a THIRD instruction in the branch shadow is
    -- still inside the cache when the redirect is applied and arrives
    -- one cycle AFTER that one-shot has expired. Nothing flushed it, so
    -- it executed for real -- confirmed twice in tb_firmware_sdram:
    --   * `sw a4,680(a5)` at 0x80000258, three instructions past the
    --     framebuffer loop's backward `bne`, ran once per iteration with
    --     a5 still holding the loop's pixel value (0xAA/0xBB instead of
    --     0xC0000000), writing to 0x2A8+0xAA=0x352 and 0x2A8+0xBB=0x363
    --     -- 29236 bogus word stores into BRAM, one per loop iteration.
    --   * `sw a3,8(a4)` at 0x8000015C, three past the UART poll loop's
    --     `bnez`, with a4=1 from `andi a4,a4,1`, writing 'A' to 0x9.
    -- In both cases shadow +1 and +2 were correctly squashed and only
    -- +3 leaked, which is exactly the one-cycle shortfall above.
    --
    -- The earlier persistent branch_pending would have caught this but
    -- killed the CORRECT target instruction instead (see Hazard_Unit's
    -- header). Both versions are guessing from cycle counts. Now that
    -- pc_fetch_delayed is a truthful record of which address each
    -- arriving word belongs to, latch WHERE we jumped to and discard
    -- every arriving fetch until the one that actually belongs to that
    -- address shows up. The only word ever accepted is one whose own
    -- fetch address equals the redirect target, so a short forward
    -- branch whose target was already in flight is not an aliasing
    -- hazard -- that in-flight word simply IS the right instruction,
    -- and the words behind it are target+4, target+8, also right.
    signal redirect_target : std_logic_vector(31 downto 0) := (others => '0');
    signal fetch_squash    : std_logic := '0';
    signal wrong_path      : std_logic;
    signal if_id_flush_eff : std_logic;

begin

    pc_current_out <= pc_wire;

    -- A stall drops an instruction unless the fetch address is rewound.
    --
    -- On the cycle a stall begins (bus wait-state or load-use hazard),
    -- instr_fetch_in is carrying the instruction for pc_delayed -- and
    -- IF_ID_Register is frozen, so it does NOT capture it. Meanwhile
    -- pc_write is also low, so pc_wire holds the NEXT address, whose
    -- data lands on instr_fetch_in the following cycle and overwrites
    -- the one that was never consumed. That instruction is then gone
    -- from the stream forever: the CPU silently skips one instruction
    -- per stall cycle, and pc_delayed no longer matches the instruction
    -- IF_ID_Register eventually latches.
    --
    -- Re-presenting pc_delayed while stalled re-fetches the un-consumed
    -- instruction, so it is still on instr_fetch_in when the stall lifts
    -- and IF_ID_Register finally captures it -- paired with the frozen
    -- pc_delayed that produced it. pc_wire is unchanged during the stall,
    -- so normal fetch resumes from the right place on the next cycle.
    pc_fetch_out       <= pc_delayed       when if_id_stall = '1' else pc_wire;
    pc_plus4_fetch_out <= pc_plus4_delayed when if_id_stall = '1' else pc_plus4_wire;

    process(clk)
    begin
        if rising_edge(clk) then
            if rst_n = '0' then
                pc_delayed       <= (others => '0');
                pc_plus4_delayed <= (others => '0');
            elsif if_id_stall = '0' then
                pc_delayed       <= pc_wire;
                pc_plus4_delayed <= pc_plus4_wire;
            end if;
            -- when if_id_stall = '1', hold pc_delayed and pc_plus4_delayed, 
            -- matching IF_ID_Register's own freeze-on-stall behavior.
        end if;
    end process;

    -- One clock behind pc_fetch_out/pc_plus4_fetch_out, unconditionally.
    -- No stall-gating needed here: pc_fetch_out already freezes itself
    -- for the whole stall, so this is simply "the address one cycle
    -- ago," which is exactly the address whose data instr_fetch_in
    -- carries this cycle, for a stall of any length. Replaces the old
    -- if_sdram_ack-keyed pc_in_to_ifid/pc_plus4_in_to_ifid mux.
    process(clk)
    begin
        if rising_edge(clk) then
            if rst_n = '0' then
                pc_fetch_delayed       <= (others => '0');
                pc_plus4_fetch_delayed <= (others => '0');
            else
                pc_fetch_delayed       <= pc_fetch_out;
                pc_plus4_fetch_delayed <= pc_plus4_fetch_out;
            end if;
        end if;
    end process;

    -- An arriving word is wrong-path while a redirect is outstanding and
    -- its own fetch address (pc_fetch_delayed) is not the target. Gated
    -- on if_id_stall because IF_ID_Register's flush outranks its stall,
    -- so asserting a flush during a freeze would clobber a validly held
    -- instruction instead of squashing an incoming one.
    wrong_path <= '1' when fetch_squash = '1' and if_id_stall = '0' and
                           pc_fetch_delayed /= redirect_target
                  else '0';

    if_id_flush_eff <= if_id_flush or wrong_path;

    process(clk)
    begin
        if rising_edge(clk) then
            if rst_n = '0' then
                redirect_target <= (others => '0');
                fetch_squash    <= '0';
            elsif pc_src = '1' then
                -- Redirect applied this cycle: every fetch already
                -- issued belongs to the abandoned path. Re-arms cleanly
                -- if another redirect lands while this one is pending.
                redirect_target <= target_pc;
                fetch_squash    <= '1';
            elsif fetch_squash = '1' and if_id_stall = '0' and
                  pc_fetch_delayed = redirect_target then
                -- The post-redirect fetch has arrived and is being
                -- latched into IF/ID this cycle. Resume normally.
                fetch_squash <= '0';
            end if;
        end if;
    end process;

    -- Program Counter
    U_PC : entity work.Program_Counter
        generic map ( DATA_WIDTH => DATA_WIDTH )
        port map (
            clk       => clk,
            rst_n     => rst_n,
            pc_write  => pc_write,
            pc_src    => pc_src,
            target_pc => target_pc,
            pc_out    => pc_wire,
            pc_plus4  => pc_plus4_wire
        );

    -- IF/ID Pipeline Register
    U_IF_ID : entity work.IF_ID_Register
        port map (
            clk             => clk,
            rst_n           => rst_n,
            stall           => if_id_stall,
            flush           => if_id_flush_eff,
            pc_in           => pc_fetch_delayed,
            pc_plus4_in     => pc_plus4_fetch_delayed,
            instruction_in  => instr_fetch_in,
            pc_out          => id_pc_out,
            pc_plus4_out    => id_pc_plus4_out,
            instruction_out => id_instr_out
        );

end architecture Structural;