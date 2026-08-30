-- SPDX-License-Identifier: Apache-2.0
-- Copyright 2026 Ozan Akgul
--
-- instr_cache.vhd -- Phase 5.3(?) direct-mapped, read-only instruction
-- cache for the SDRAM-resident fetch path added in the Phase 5
-- prerequisite closeout (see docs/README.md, "Phase 5 Prerequisite
-- Closeout -- SDRAM Instruction Fetch"). That note explicitly deferred
-- a cache: "the added verification surface wasn't worth it before
-- Doom's actual performance profile is known." That profile is now
-- known -- ~2.5s/frame on real hardware, 2026-08-29, with instruction
-- fetch for the CPU's entire 405KB firmware image going straight to
-- SDRAM on every single fetch, no caching, contending with CPU data
-- accesses and vga_line_fetch for sdram_controller's one open-row slot
-- the whole time. Doom's renderer re-executes the same handful of
-- tight loops (BSP walk, column/span drawing, texture sampling)
-- millions of times per frame -- about as favorable a locality profile
-- as software gets -- so an I-cache should be the single biggest lever
-- available without redesigning the CPU pipeline itself.
--
-- INSERTION POINT: this sits between IF_Stage's SDRAM-range fetch
-- request (if_fetch_adr/if_fetch_stb/if_fetch_cyc in rv32im_soc.vhd)
-- and fetch_arbiter's existing FETCH port, replacing what was a direct
-- wire. Both sides keep the exact protocol already in use elsewhere in
-- this design, specifically so nothing outside this file has to
-- change:
--
--   CPU side: a single-word request/ack pair (adr/stb/cyc in, dat/ack
--   out) with NO assumed fixed latency. if_bus_stall/if_sdram_ack in
--   rv32im_soc.vhd are already keyed purely off if_fetch_ack, and
--   Hazard_Unit's dedicated fetch-stall case already tolerates however
--   many cycles that takes -- a cache hit (2 cycles) and a cache miss
--   (line-fill, tens of cycles) both fall entirely inside that
--   existing, already-verified tolerance. IF_Stage.vhd, Hazard_Unit.vhd,
--   and CPU_FPGA.vhd's pending_branch/pending_target latch are
--   UNCHANGED by this file.
--
--   Memory side: this cache becomes fetch_arbiter's new FETCH master,
--   using the identical single-word request/ack protocol fetch_arbiter
--   already expects (fetch_sel_i tied to "1111" externally by
--   rv32im_soc.vhd as it is today). A line fill is just LINE_WORDS
--   sequential single-word fetches through this same port -- from
--   fetch_arbiter's perspective indistinguishable from the CPU fetching
--   several consecutive instructions the normal way. fetch_arbiter,
--   sdram_arbiter, and sdram_controller are all UNCHANGED.
--
-- FILL BUBBLE: rv32im_soc.vhd's if_fetch_bubble exists because holding
-- the fetch request asserted continuously across back-to-back fetches
-- starved DATA (and, one level up, VGA) out of ever winning
-- re-arbitration -- fetch_arbiter/sdram_arbiter only re-arbitrate when
-- the bus goes idle (m_cyc_o = '0'). A line fill issuing LINE_WORDS
-- requests back to back would reintroduce exactly that starvation risk
-- if it held mem_cyc_o high across all of them, so mem_stb_o/mem_cyc_o
-- here are driven purely combinationally off "currently issuing a fill
-- word" (state = S_FILL_ISSUE) -- the cycle immediately after an ack,
-- state has already moved to S_FILL_BUBBLE, so the bus is genuinely
-- idle for that one cycle before the next word is requested, mirroring
-- if_fetch_bubble's fix exactly.
--
-- WHY READ-ONLY, NO COHERENCY: this is a pure instruction cache over a
-- firmware image the CPU never writes to at runtime (no self-modifying
-- code in this port). A line, once filled, is valid until reset --
-- there is no invalidation path and none is needed.
--
-- SIZE: 4KB (256 lines x 4 words x 4 bytes), direct-mapped. Comparable
-- in size to bram_4kb.vhd's existing 4KB boot BRAM, and small next to
-- the board's 270Kbit (30 M9K) on-chip RAM budget -- tag+data together
-- use well under 40Kbit, roughly 4-5 M9K blocks. NOTE: NUM_LINES and
-- LINE_WORDS are exposed as generics but INDEX_BITS/WORD_BITS below
-- are NOT derived from them (kept as plain constants matching the
-- defaults, 8 and 2) -- changing the generics without updating those
-- two constants to match will silently break the address slicing.
--
-- DESIGN PHILOSOPHY: simple over cycle-shaving, same trade this
-- project's own sdram_controller.vhd explicitly makes ("trading peak
-- throughput for a much simpler FSM"). A hit costs 2 cycles (address
-- presented, then compare+ack); a miss re-does the lookup after the
-- fill completes rather than forwarding the just-fetched critical word
-- directly, which costs a couple of extra cycles per miss but keeps
-- the FSM small and auditable.
--
-- NOT YET VERIFIED ON HARDWARE OR IN SIMULATION. Treat this as a
-- drafted starting point, not a known-good module -- adapt
-- sim/ghdl/tb_if_sdram_fetch.vhd's approach (hand-assembled
-- instructions stored into SDRAM, then executed via JALR) to also
-- re-execute the same address twice and confirm the second pass hits
-- with no further SDRAM traffic, before this goes anywhere near real
-- hardware. Given how many of this project's other timing assumptions
-- turned out wrong on first contact with real SDRAM (see
-- sdram_controller.vhd's own header), that is not optional.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library altera_mf;
use altera_mf.altera_mf_components.all;

entity instr_cache is
    generic (
        LINE_WORDS : natural := 4;    -- words per line (16 bytes) -- see note above
        NUM_LINES  : natural := 256   -- lines; 256 * 16B = 4KB total -- see note above
    );
    port (
        clk   : in  std_logic;
        rst_n : in  std_logic;

        -- CPU side: same contract the raw SDRAM fetch path already
        -- presented to fetch_arbiter (see file header).
        cpu_adr_i : in  std_logic_vector(31 downto 0);
        cpu_stb_i : in  std_logic;
        cpu_cyc_i : in  std_logic;
        cpu_dat_o : out std_logic_vector(31 downto 0);
        cpu_ack_o : out std_logic;

        -- Memory side: drives fetch_arbiter's existing FETCH port,
        -- unchanged protocol.
        mem_adr_o : out std_logic_vector(31 downto 0);
        mem_dat_i : in  std_logic_vector(31 downto 0);
        mem_stb_o : out std_logic;
        mem_cyc_o : out std_logic;
        mem_ack_i : in  std_logic
    );
end entity instr_cache;

architecture rtl of instr_cache is

    -- Address slicing constants. See the generics note above -- these
    -- must be updated together with LINE_WORDS/NUM_LINES if either
    -- changes from its default.
    constant OFFSET_BITS : natural := 2;  -- byte-in-word, always "00" for instr fetch
    constant WORD_BITS   : natural := 2;  -- log2(LINE_WORDS=4) -- word-in-line select
    constant INDEX_BITS  : natural := 8;  -- log2(NUM_LINES=256)
    constant TAG_BITS    : natural := 32 - INDEX_BITS - WORD_BITS - OFFSET_BITS; -- 20

    -- altsyncram's GHDL simulation stand-in (sim/ghdl/altera_mf.vhd)
    -- commits writes in BYTE-granularity chunks gated by
    -- width_byteena_a/width_byteena_b (each defaults to 1, i.e. ONE
    -- byte-enable bit = only the low 8 bits of any write actually
    -- land, regardless of the port's real width) -- confirmed
    -- 2026-08-29 by reading that generic's default in
    -- sim/ghdl/altera_mf.vhd, after decoding a debug-log trace
    -- showing tag_rdata's valid bit (bit TAG_BITS = 20) permanently
    -- reading back '0' even immediately after a fill's tag write,
    -- forcing every lookup into a permanent miss/refill loop and
    -- hanging the CPU. bram_4kb.vhd already sets width_byteena_a/b
    -- explicitly (to 4, matching its byte-aligned 32-bit word) and so
    -- never hit this; u_tag_mem/u_data_mem below did not, and do now.
    -- u_data_mem's 32-bit words are already byte-aligned, so its fix
    -- is just width_byteena_a/b => 4. u_tag_mem's real width
    -- (TAG_BITS+1 = 21 bits) is NOT a multiple of 8 -- setting
    -- width_byteena_a/b => 3 (ceil(21/8)) directly against a 21-bit
    -- port would make the simulation model's per-byte write loop
    -- slice byte index 2 as bits 23 downto 16, out of range for a
    -- 21-bit vector. So the tag store's declared width is padded up
    -- to the next byte boundary here; tag_wdata/tag_rdata are sized
    -- to TAG_STORE_WIDTH below, with the valid bit and tag field kept
    -- at the same low bit positions (20 downto 0) they always had --
    -- the extra bits (TAG_STORE_WIDTH-1 downto TAG_BITS+1) are inert
    -- padding, tied '0' on write and never read.
    constant TAG_STORE_WIDTH : natural := ((TAG_BITS + 1 + 7) / 8) * 8; -- 24

    type state_t is (S_IDLE, S_COMPARE, S_FILL_ISSUE, S_FILL_BUBBLE);
    signal state : state_t := S_IDLE;

    -- Latched request being resolved (valid from the S_IDLE->S_COMPARE
    -- transition onward; cpu_adr_i itself is guaranteed stable the
    -- whole time since if_bus_stall holds the CPU frozen on this
    -- request until cpu_ack_o pulses).
    signal req_adr : std_logic_vector(31 downto 0) := (others => '0');

    -- Line-fill word counter, 0 .. LINE_WORDS-1.
    signal fill_word : unsigned(WORD_BITS-1 downto 0) := (others => '0');

    -- Live address fields, off the CPU-presented address (used for the
    -- normal read lookup in S_IDLE/S_COMPARE).
    signal req_index : std_logic_vector(INDEX_BITS-1 downto 0);
    signal latched_index : std_logic_vector(INDEX_BITS-1 downto 0);
    signal req_word  : std_logic_vector(WORD_BITS-1 downto 0);

    -- Tag+valid BRAM: {valid, tag} per line, one line per index.
    signal tag_addr  : std_logic_vector(INDEX_BITS-1 downto 0);
    signal tag_wdata : std_logic_vector(TAG_STORE_WIDTH-1 downto 0);
    signal tag_we    : std_logic;
    signal tag_rdata : std_logic_vector(TAG_STORE_WIDTH-1 downto 0);

    -- Data BRAM: one word per {index, word-in-line}.
    -- Split into a read-side address (port A, the normal lookup) and a
    -- write-side address (port B, only driven during a line fill) --
    -- see the BIDIR_DUAL_PORT rationale on u_tag_mem/u_data_mem below.
    signal data_addr    : std_logic_vector(INDEX_BITS+WORD_BITS-1 downto 0);
    signal data_wr_addr : std_logic_vector(INDEX_BITS+WORD_BITS-1 downto 0);
    signal data_wdata   : std_logic_vector(31 downto 0);
    signal data_we      : std_logic;
    signal data_rdata   : std_logic_vector(31 downto 0);

begin

    req_index <= cpu_adr_i(INDEX_BITS+WORD_BITS+OFFSET_BITS-1 downto WORD_BITS+OFFSET_BITS);
    req_word  <= cpu_adr_i(WORD_BITS+OFFSET_BITS-1 downto OFFSET_BITS);
    latched_index <= req_adr(INDEX_BITS+WORD_BITS+OFFSET_BITS-1 downto WORD_BITS+OFFSET_BITS);

    -- Tag+valid store: TAG_BITS+1 wide (1 valid + 20 tag), NUM_LINES deep.
    -- Single-port, UNREGISTERED output -- see bram_4kb.vhd's own comment
    -- on why: altsyncram always registers the read address, and leaving
    -- outdata_reg at its CLOCK0 default adds a SECOND register stage,
    -- doubling address-to-data latency to 2 cycles instead of 1. This
    -- design's S_IDLE/S_COMPARE cycle count assumes exactly 1.
    -- BIDIR_DUAL_PORT, not SINGLE_PORT: this project's GHDL-only
    -- simulation stand-in (sim/ghdl/altera_mf.vhd) only ever commits a
    -- write to its behavioral memory array via port B (wren_b/data_b);
    -- its non-DUAL_PORT branch -- which SINGLE_PORT falls into --
    -- treats a wren_a='1' write as a no-op that merely reports "***
    -- PORT-A WRITE (should never happen) ***" instead of actually
    -- writing. SINGLE_PORT mode writing through port A works fine on
    -- real Quartus hardware, but is silently broken in this simulation
    -- environment -- confirmed 2026-08-29 (every fill write dropped,
    -- tb_firmware_sdram: 2 CHECK(S) FAILED). Matching bram_4kb.vhd's
    -- already hardware-proven BIDIR_DUAL_PORT wiring instead: port A
    -- is the read-only lookup port, port B is the write-only fill
    -- port. All port-B register stages are pinned to CLOCK0 for the
    -- same reason bram_4kb.vhd pins them -- this is a single-clock
    -- (clock0-only) design, and BIDIR_DUAL_PORT otherwise defaults
    -- port B's register stages to clock1.
    u_tag_mem : altsyncram
        generic map (
            operation_mode                     => "BIDIR_DUAL_PORT",
            intended_device_family             => "Cyclone IV E",
            width_a                            => TAG_STORE_WIDTH,
            widthad_a                          => INDEX_BITS,
            numwords_a                         => NUM_LINES,
            outdata_reg_a                      => "UNREGISTERED",
            width_byteena_a                    => TAG_STORE_WIDTH / 8,
            width_b                            => TAG_STORE_WIDTH,
            widthad_b                          => INDEX_BITS,
            numwords_b                         => NUM_LINES,
            width_byteena_b                    => TAG_STORE_WIDTH / 8,
            address_reg_b                      => "CLOCK0",
            indata_reg_b                       => "CLOCK0",
            rdcontrol_reg_b                    => "CLOCK0",
            wrcontrol_wraddress_reg_b          => "CLOCK0",
            byteena_reg_b                      => "CLOCK0",
            read_during_write_mode_mixed_ports => "OLD_DATA"
        )
        port map (
            clock0    => clk,
            -- Port A: read-only lookup, same line index whether this
            -- is a normal hit check or the tag re-check after a fill.
            address_a => tag_addr,
            data_a    => (others => '0'),
            wren_a    => '0',
            q_a       => tag_rdata,
            -- Port B: write-only, commits the new {valid,tag} on the
            -- last word of a line fill.
            address_b => latched_index,
            data_b    => tag_wdata,
            wren_b    => tag_we
            
        );

    -- Data store: 32 bits wide, NUM_LINES*LINE_WORDS deep. Same
    -- UNREGISTERED rationale as the tag store above.
    -- Same BIDIR_DUAL_PORT rework as u_tag_mem above, same reason --
    -- see that instance's comment.
    u_data_mem : altsyncram
        generic map (
            operation_mode                     => "BIDIR_DUAL_PORT",
            intended_device_family             => "Cyclone IV E",
            width_a                            => 32,
            widthad_a                          => INDEX_BITS + WORD_BITS,
            numwords_a                         => NUM_LINES * LINE_WORDS,
            outdata_reg_a                      => "UNREGISTERED",
            width_byteena_a                    => 4,
            width_b                            => 32,
            widthad_b                          => INDEX_BITS + WORD_BITS,
            numwords_b                         => NUM_LINES * LINE_WORDS,
            width_byteena_b                    => 4,
            address_reg_b                      => "CLOCK0",
            indata_reg_b                       => "CLOCK0",
            rdcontrol_reg_b                    => "CLOCK0",
            wrcontrol_wraddress_reg_b          => "CLOCK0",
            byteena_reg_b                      => "CLOCK0",
            read_during_write_mode_mixed_ports => "OLD_DATA"
        )
        port map (
            clock0    => clk,
            -- Port A: read-only lookup word.
            address_a => data_addr,
            data_a    => (others => '0'),
            wren_a    => '0',
            q_a       => data_rdata,
            -- Port B: write-only, one word per fill-word ack.
            address_b => data_wr_addr,
            data_b    => data_wdata,
            wren_b    => data_we
        );

    -- ---- Combinational BRAM/bus driving -----------------------------
    -- Kept entirely outside the clocked process below so each of these
    -- signals has exactly one driver -- state, fill_word and req_adr
    -- are the only registered signals; everything else is a pure
    -- function of them plus the live inputs.

    -- Tag read (port A) address: req_index (live off cpu_adr_i) is
    -- valid throughout, since cpu_adr_i does not change while this
    -- request is outstanding. The tag write (port B, in u_tag_mem's
    -- port map above) reuses req_index directly rather than a separate
    -- signal, since a fill only ever writes the line it just missed on
    -- -- same index, no mux needed there either.
    tag_addr <= req_index;

    -- Tag write commits on the ack of the LAST word of a fill.
    tag_we    <= '1' when (state = S_FILL_ISSUE and mem_ack_i = '1'
                            and fill_word = to_unsigned(LINE_WORDS-1, WORD_BITS))
                      else '0';
    tag_wdata <= std_logic_vector(to_unsigned(0, TAG_STORE_WIDTH - (TAG_BITS + 1))) &
                 '1' & req_adr(31 downto INDEX_BITS+WORD_BITS+OFFSET_BITS);

    -- Data read (port A) address: always the originally-requested
    -- word. Now a single unconditional driver -- port A no longer
    -- doubles as the fill-write address (that's data_wr_addr/port B
    -- below), so there's nothing left to mux on state for.
    data_addr <= req_index & req_word;

  -- Data write (port B) address: the word currently being filled.
    data_wr_addr <= latched_index & std_logic_vector(fill_word);

    -- Data write commits on every fill word's ack.
    data_we    <= '1' when (state = S_FILL_ISSUE and mem_ack_i = '1') else '0';
    data_wdata <= mem_dat_i;

    -- Memory-side request: asserted for exactly the cycles spent in
    -- S_FILL_ISSUE. Falls low the moment state advances to
    -- S_FILL_BUBBLE (the cycle after ack) -- see the FILL BUBBLE note
    -- in the file header.
    mem_stb_o <= '1' when state = S_FILL_ISSUE else '0';
    mem_cyc_o <= '1' when state = S_FILL_ISSUE else '0';
    mem_adr_o <= req_adr(31 downto INDEX_BITS+WORD_BITS+OFFSET_BITS) &
                 req_adr(INDEX_BITS+WORD_BITS+OFFSET_BITS-1 downto WORD_BITS+OFFSET_BITS) &
                 std_logic_vector(fill_word) &
                 "00";

    -- ---- State machine -----------------------------------------------

    process (clk)
    begin
        if rising_edge(clk) then
            if rst_n = '0' then
                state     <= S_IDLE;
                cpu_ack_o <= '0';
                fill_word <= (others => '0');
            else
                cpu_ack_o <= '0';  -- single-cycle pulse, cleared by default

                case state is
                    ----------------------------------------------------
                    when S_IDLE =>
                        if cpu_stb_i = '1' and cpu_cyc_i = '1' then
                            -- tag_addr/data_addr above are already
                            -- presenting this cycle's request address to
                            -- both BRAMs; latch it so S_COMPARE knows
                            -- what the registered outputs correspond to.
                            req_adr <= cpu_adr_i;
                            state   <= S_COMPARE;
                            -- pragma translate_off
                            report "instr_cache: S_IDLE -> S_COMPARE, adr=0x" &
                                   to_hstring(cpu_adr_i);
                            -- pragma translate_on
                        end if;

                    ----------------------------------------------------
                    when S_COMPARE =>
                        -- pragma translate_off
                        report "instr_cache: S_COMPARE adr=0x" & to_hstring(req_adr) &
                               " tag_rdata=" & to_hstring(tag_rdata) &
                               " want_tag=0x" &
                               to_hstring(req_adr(31 downto INDEX_BITS+WORD_BITS+OFFSET_BITS));
                        -- pragma translate_on
                        if tag_rdata(TAG_BITS) = '1' and
                           tag_rdata(TAG_BITS-1 downto 0) =
                               req_adr(31 downto INDEX_BITS+WORD_BITS+OFFSET_BITS) then
                            -- Hit.
                            cpu_dat_o <= data_rdata;
                            cpu_ack_o <= '1';
                            state     <= S_IDLE;
                            -- pragma translate_off
                            report "instr_cache: HIT adr=0x" & to_hstring(req_adr) &
                                   " data=0x" & to_hstring(data_rdata);
                            -- pragma translate_on
                        else
                            -- Miss: start a line fill at this line's base.
                            fill_word <= (others => '0');
                            state     <= S_FILL_ISSUE;
                            -- pragma translate_off
                            report "instr_cache: MISS adr=0x" & to_hstring(req_adr) &
                                   " -> starting fill";
                            -- pragma translate_on
                        end if;

                    ----------------------------------------------------
                    when S_FILL_ISSUE =>
                        if mem_ack_i = '1' then
                            -- data_we/tag_we above already commit this
                            -- word's write (and, on the last word, the
                            -- tag write too) combinationally this same
                            -- cycle.
                            -- pragma translate_off
                            report "instr_cache: fill ack, word=" &
                                   integer'image(to_integer(fill_word)) &
                                   " mem_adr=0x" & to_hstring(mem_adr_o) &
                                   " mem_dat=0x" & to_hstring(mem_dat_i);
                            -- pragma translate_on
                            if fill_word = to_unsigned(LINE_WORDS-1, WORD_BITS) then
                                -- Line now warm; go back to S_IDLE, which
                                -- re-presents the same still-outstanding
                                -- request (cpu_adr_i unchanged -- the CPU
                                -- is stalled the whole time) and resolves
                                -- as a hit on the next pass. See file
                                -- header on why this re-lookup, rather
                                -- than forwarding the critical word
                                -- directly, was chosen.
                                state <= S_IDLE;
                                -- pragma translate_off
                                report "instr_cache: fill complete, back to S_IDLE";
                                -- pragma translate_on
                            else
                                fill_word <= fill_word + 1;
                                state     <= S_FILL_BUBBLE;
                            end if;
                        end if;

                    ----------------------------------------------------
                    when S_FILL_BUBBLE =>
                        -- One idle cycle (mem_stb_o/mem_cyc_o already
                        -- low, see combinational block above) so
                        -- fetch_arbiter/sdram_arbiter see a genuine idle
                        -- moment and can re-arbitrate in DATA's (or
                        -- VGA's) favour before the next fill word.
                        state <= S_FILL_ISSUE;

                end case;
            end if;
        end if;
    end process;

end architecture rtl;
