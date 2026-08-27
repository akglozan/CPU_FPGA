-- SPDX-License-Identifier: Apache-2.0
-- Copyright 2026 Ozan Akgul
--
-- NOTE ON READ TIMING (resolved 2026-08-24): wait_cnt in ST_READ_CMD is 1.
-- This was fought over hard during SDRAM hardware bring-up: real CPU-driven
-- reads kept coming back wrong (both 16-bit halves equal to the correct
-- upper half, e.g. 0xDEADBEEF read back as 0xDEADDEAD) no matter what this
-- value was set to -- a runtime-sweepable register briefly existed here to
-- try every value from 0 to 4, and ALL of them gave the identical wrong
-- result. That was the tell: if this were really a read-capture-timing
-- problem, different values would have sampled different (if still wrong)
-- points on the bus. Getting the exact same answer regardless of timing
-- meant the bus wasn't changing at all -- the SDRAM chip was never
-- responding to any command. Root cause: sdram_clk (SD_CLK, board pin 43)
-- had never been wired to anything in this project's history; every other
-- SDRAM pin matched the RZ-EasyFPGA A2.2 vendor pin table exactly except
-- that one. Once sdram_clk was added and pinned, wait_cnt = 1 -- the value
-- that was already correct against sim/ghdl/tb_sdram.vhd's behavioural
-- sdram_model.vhd -- turned out to be correct on real hardware too.
-- Confirmed with a 5-word CPU-driven test spanning three consecutive
-- words, a different row, and a different bank: all five round-tripped
-- correctly. See docs/notes/bringup_bug_report_2026-08-23.txt for the full
-- investigation.
--
-- NOTE ON BURST ALIGNMENT (resolved 2026-08-27) -- the actual root cause
-- of the "80 vertical stripes" / corrupted-framebuffer bug.
--
-- This controller used to derive the column straight from
-- latched_adr(8 downto 1), justified by the claim in the ADDRESS MAPPING
-- note below that "bus addresses are 32-bit aligned (adr(1 downto 0) =
-- 00), so the starting column is always even and the burst never wraps".
-- That claim is FALSE. rtl/core/MEM_Stage.vhd drives the full byte
-- address onto the bus -- "wb_addr_o <= mem_addr", with no alignment
-- masking -- and selects the lane with wb_sel instead. So every byte or
-- halfword access to an odd halfword (adr(1) = '1') presented an ODD
-- start column.
--
-- With BL=2 sequential, a burst starting on an odd column wraps backwards
-- inside its own 2-column block: it visits col, then col-1. The two beats
-- come out SWAPPED. For a store that means beat 2's DQM-selected byte --
-- meant for the upper halfword -- lands on the LOWER one, overwriting the
-- data a previous store just put there; the upper halfword is never
-- written at all and keeps whatever was in DRAM before.
--
-- On hardware that produced a framebuffer where every word read back as
-- {stale, 0xBBBB}: the 0xBB bytes destined for bytes 2..3 had clobbered
-- bytes 0..1, and bytes 2..3 still held leftover DOOM1.WAD payload. The
-- giveaway was that the "garbage" half was byte-identical across two runs
-- with completely different fill patterns -- it was never written, so it
-- could not change. Word-sized accesses (wb_sel = "1111", adr(1..0) =
-- "00") were always immune, which is why the ESP32 boot DMA loaded
-- FIRMWARE.BIN and DOOM1.WAD perfectly and WAD[0] read back as "IWAD"
-- throughout, and why this looked for a long time like a read-path fault
-- specific to vga_line_fetch.
--
-- Fix: force adr(1) to '0' when forming the column, so the burst always
-- starts on an even column and beat 1 / beat 2 map to the low / high
-- halfword unconditionally. The existing DQM mapping (sel(1 downto 0) on
-- beat 1, sel(3 downto 2) on beat 2) is then correct by construction for
-- every access size. Word accesses are bit-for-bit unaffected.
--
-- Missed by every testbench because tb_sdram.vhd only ever drove
-- wb_sel = "1111" word accesses. sim/ghdl/tb_vga_sdram.vhd now fills
-- through byte stores and fails without this fix.
--
-- NOTE ON READ CAPTURE ALIGNMENT (2026-08-27): READ_CAS_WAIT is the
-- number of cycles ST_READ_WAIT burns between issuing READ and sampling
-- burst beat 1 in ST_READ_DATA. Simulation wants 1; real hardware wants
-- 0, and the difference is not a bug in either -- it is a genuine
-- one-cycle difference in round-trip latency that the behavioural model
-- cannot reproduce.
--
-- sim/sdram_model.vhd captures a command at the rising edge AFTER the
-- controller registers it onto the pins, because both sides share one
-- ideal zero-delay clock signal. The real chip is clocked by a
-- FORWARDED copy of clk on SD_CLK, which arrives at the chip at
-- essentially the same instant the FPGA launches the command -- so the
-- chip captures it a full cycle earlier in relative terms, and its data
-- comes back one cycle sooner than the model's does. Sampling at the
-- model's alignment therefore lands one cycle late on hardware.
--
-- Evidence (hardware, 2026-08-27): with the framebuffer filled so that
-- burst beat 1 = 0xAAAA and beat 2 = 0xBBBB, every 32-bit read returned
-- 0x????BBBB -- beat 2's data sitting in beat 1's half, with the high
-- half sampling a bus the chip had already stopped driving. A full
-- 64,000-byte readback reported exactly 32,000 bad bytes, all of them
-- the two low bytes of each word and none of the two high bytes: the
-- fingerprint of every read returning the upper halfword.
--
-- This had been invisible for four rounds of hardware debugging because
-- the diagnostic filled memory uniformly with 0x01, making beat 1 and
-- beat 2 byte-identical -- a one-cycle-late capture reads back perfect
-- against a uniform pattern. It also made the fault look specific to
-- vga_line_fetch's access pattern when in fact the CPU's own reads were
-- corrupted identically the whole time. Do not re-verify this path with
-- a uniform fill.
--
-- NOTE ON ADDRESS MAPPING (resolved 2026-08-25): the fitted chip is a
-- Winbond W9864G6KH-6 -- 64 Mbit organised 4M x 16, i.e. 4 banks x 4096
-- rows x 256 columns. 256 columns means the column address is only 8
-- bits wide (A0-A7). This controller previously drove NINE column bits
-- ("000" & latched_adr(9 downto 1)), putting latched_adr(9) onto A8,
-- which the chip ignores during a READ/WRITE command. That bit was
-- therefore silently discarded, so every pair of addresses 512 bytes
-- apart aliased onto the same physical cells: writing offset 512 of a
-- buffer destroyed offset 0. Invisible during bring-up because the
-- 5-word test above spans only 20 bytes -- far less than the 512-byte
-- alias stride -- and only surfaced once the ESP32 boot loader began
-- DMAing megabyte-scale files in (DOOM1.WAD's first word read back as
-- its own offset-512 contents rather than the "IWAD" magic).
--
-- Correct slicing for this part, in byte-address terms:
--   adr(0)         byte within the 16-bit word (selected via DQM)
--   adr(8 downto 1)   column, 8 bits  -> 256 columns
--   adr(20 downto 9)  row,    12 bits -> 4096 rows
--   adr(22 downto 21) bank,    2 bits -> 4 banks
-- Total adr(22 downto 0) = 8 MB, exactly the chip's capacity. The old
-- mapping claimed adr(23 downto 0) = 16 MB, i.e. twice the real part,
-- which is the same error stated a different way.
--
-- Burst length is 2, so each 32-bit Wishbone word is one command plus
-- two 16-bit beats at col and col+1. Bus addresses are 32-bit aligned
-- (adr(1 downto 0) = "00"), so the starting column adr(8 downto 1) is
-- always even and the burst never wraps into a neighbouring word.

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

-- SDRAM controller for a 16-bit-wide SDR SDRAM chip, exposed as a
-- Wishbone B4 slave. Handles the power-on init sequence (precharge
-- all banks, two auto-refresh cycles, mode register load: sequential
-- burst, BL=2, CAS=2), periodic auto-refresh, and single-word
-- transactions -- each 32-bit CPU word is split across two 16-bit
-- SDRAM beats (burst length 2). Only one row is ever open at a time:
-- every transaction precharges the row it used before returning to
-- ST_IDLE, trading peak throughput for a much simpler FSM.
entity sdram_controller is
    generic (
        CLK_FREQ_MHZ : integer := 50;   -- System Clock Frequency in MHz
        SIMULATION   : boolean := false; -- Set to true for fast simulation boot

        -- Cycles spent in ST_READ_WAIT between issuing READ and sampling
        -- burst beat 1. See NOTE ON READ CAPTURE ALIGNMENT above for why
        -- this is a generic rather than a constant, and why simulation
        -- and hardware legitimately want different values (1 and 0).
        READ_CAS_WAIT : natural := 1
    );
    port (
        clk           : in    std_logic;
        -- Active-low asynchronous reset.
        reset_n       : in    std_logic;

        -- Wishbone B4 Slave Interface
        wb_adr_i      : in    std_logic_vector(31 downto 0);
        wb_dat_i      : in    std_logic_vector(31 downto 0);
        wb_dat_o      : out   std_logic_vector(31 downto 0);
        wb_sel_i      : in    std_logic_vector(3 downto 0);
        wb_we_i       : in    std_logic;
        wb_stb_i      : in    std_logic;
        wb_cyc_i      : in    std_logic;
        wb_ack_o      : out   std_logic;

        -- Physical SDRAM Pins
        -- Clock enable; tied permanently high.
        sdram_cke     : out   std_logic;
        -- Chip select, active low (part of the 4-bit command bus).
        sdram_cs_n    : out   std_logic;
        -- Row address strobe, active low (part of the command bus).
        sdram_ras_n   : out   std_logic;
        -- Column address strobe, active low (part of the command bus).
        sdram_cas_n   : out   std_logic;
        -- Write enable, active low (part of the command bus).
        sdram_we_n    : out   std_logic;
        -- Bank address select.
        sdram_ba      : out   std_logic_vector(1 downto 0);
        -- Multiplexed row/column address bus.
        sdram_addr    : out   std_logic_vector(11 downto 0);
        -- Data mask, one bit per byte lane of the 16-bit data bus.
        sdram_dqm     : out   std_logic_vector(1 downto 0);
        -- Bidirectional 16-bit SDRAM data bus.
        sdram_dq      : inout std_logic_vector(15 downto 0);
        -- Clock forwarded to the physical SDRAM chip (RZ-EasyFPGA A2.2:
        -- SD_CLK, pin 43). See the NOTE ON READ TIMING above -- this was
        -- missing entirely until 2026-08-24 and was the real root cause
        -- of every SDRAM bring-up failure. A plain unregistered copy of
        -- clk, same as every other design on this class of board.
        sdram_clk     : out   std_logic
    );
end entity sdram_controller;

architecture rtl of sdram_controller is

    -- SDRAM Commands {CS_N, RAS_N, CAS_N, WE_N}
    constant CMD_NOP     : std_logic_vector(3 downto 0) := "0111";
    constant CMD_ACTIVE  : std_logic_vector(3 downto 0) := "0011";
    constant CMD_READ    : std_logic_vector(3 downto 0) := "0101";
    constant CMD_WRITE   : std_logic_vector(3 downto 0) := "0100";
    constant CMD_PRECHG  : std_logic_vector(3 downto 0) := "0010";
    constant CMD_REFRESH : std_logic_vector(3 downto 0) := "0001";
    constant CMD_LOAD_MR : std_logic_vector(3 downto 0) := "0000";

    type state_t is (
        ST_BOOT_WAIT, ST_BOOT_PRECHARGE, ST_BOOT_REF1, ST_BOOT_REF2, ST_BOOT_LMR,
        ST_IDLE, ST_ACTIVE, ST_READ_CMD, ST_READ_WAIT, ST_READ_DATA, ST_READ_DATA2,
        ST_WRITE_CMD, ST_WRITE_DATA2, ST_WRITE_REC, ST_PRECHARGE, ST_REFRESH
    );
    signal state : state_t := ST_BOOT_WAIT;

    -- Refresh timer: 64ms / 4096 rows = 15.625 us -> ~780 cycles @ 50MHz
    constant REFRESH_PERIOD : integer := (CLK_FREQ_MHZ * 15);
    signal refresh_cnt      : integer range 0 to REFRESH_PERIOD := 0;
    signal refresh_req      : std_logic := '0';

    -- General Delay / Wait Counter (Expanded range to prevent overflow)
    signal wait_cnt         : integer range 0 to 65535 := 0;

    -- Internal Registers
    signal dq_out           : std_logic_vector(15 downto 0);
    signal dq_oe            : std_logic := '0';
    signal rdata_reg        : std_logic_vector(31 downto 0);
    signal latched_adr      : std_logic_vector(31 downto 0);
    signal latched_wdata    : std_logic_vector(31 downto 0);
    signal latched_sel      : std_logic_vector(3 downto 0);

    -- Page-mode open-row tracking (added 2026-08-27 -- see ST_IDLE below).
    -- At most one row is ever open at a time (this part has 4 banks, but
    -- the controller only tracks a single open row/bank pair, matching
    -- its existing "precharge all banks" behaviour). open_valid='1' means
    -- open_bank/open_row identify the currently-active row; a request
    -- that hits it can skip straight to READ_CMD/WRITE_CMD with no
    -- ACTIVATE and no tRCD wait.
    signal open_valid : std_logic := '0';
    signal open_bank  : std_logic_vector(1 downto 0) := (others => '0');
    signal open_row   : std_logic_vector(11 downto 0) := (others => '0');

begin

    sdram_cke <= '1';
    sdram_clk <= clk;
    sdram_dq  <= dq_out when (dq_oe = '1') else (others => 'Z');
    wb_dat_o  <= rdata_reg;

    -- Refresh Request Generator
    process(clk, reset_n)
    begin
        if reset_n = '0' then
            refresh_cnt <= 0;
            refresh_req <= '0';
        elsif rising_edge(clk) then
            if refresh_cnt >= REFRESH_PERIOD then
                refresh_cnt <= 0;
                refresh_req <= '1';
            else
                refresh_cnt <= refresh_cnt + 1;
            end if;
            if state = ST_REFRESH then
                refresh_req <= '0';
            end if;
        end if;
    end process;

    -- Main Control FSM
    process(clk, reset_n)
        procedure send_cmd(cmd : in std_logic_vector(3 downto 0)) is
        begin
            sdram_cs_n  <= cmd(3);
            sdram_ras_n <= cmd(2);
            sdram_cas_n <= cmd(1);
            sdram_we_n  <= cmd(0);
        end procedure;
    begin
        if reset_n = '0' then
            state      <= ST_BOOT_WAIT;
            wb_ack_o   <= '0';
            dq_oe      <= '0';
            sdram_ba   <= "00";
            sdram_addr <= (others => '0');
            sdram_dqm  <= "11";
            open_valid <= '0';
            send_cmd(CMD_NOP);
            if SIMULATION then
                wait_cnt <= 10;
            else
                wait_cnt <= CLK_FREQ_MHZ * 150;
            end if;
        elsif rising_edge(clk) then
            send_cmd(CMD_NOP); -- Default command to avoid latching control pulses
            wb_ack_o <= '0';   -- Single-cycle ACK clear default

            case state is
                ----------------------------------------------------------------
                -- Power-On Initialization Sequence
                ----------------------------------------------------------------
                when ST_BOOT_WAIT =>
                    if wait_cnt = 0 then
                        state <= ST_BOOT_PRECHARGE;
                    else
                        wait_cnt <= wait_cnt - 1;
                    end if;

                when ST_BOOT_PRECHARGE =>
                    send_cmd(CMD_PRECHG);
                    sdram_addr(10) <= '1'; -- All banks
                    wait_cnt <= 2;
                    state    <= ST_BOOT_REF1;

                when ST_BOOT_REF1 =>
                    if wait_cnt = 0 then
                        send_cmd(CMD_REFRESH);
                        wait_cnt <= 4;
                        state    <= ST_BOOT_REF2;
                    else
                        wait_cnt <= wait_cnt - 1;
                    end if;

                when ST_BOOT_REF2 =>
                    if wait_cnt = 0 then
                        send_cmd(CMD_REFRESH);
                        wait_cnt <= 4;
                        state    <= ST_BOOT_LMR;
                    else
                        wait_cnt <= wait_cnt - 1;
                    end if;

                when ST_BOOT_LMR =>
                    if wait_cnt = 0 then
                        send_cmd(CMD_LOAD_MR);
                        sdram_ba   <= "00";
                        -- Mode: Sequential, BL=2, CAS=2 (0x021)
                        sdram_addr <= "00" & '0' & "00" & "010" & '0' & "001";
                        wait_cnt   <= 2;
                        state      <= ST_IDLE;
                    else
                        wait_cnt <= wait_cnt - 1;
                    end if;

                ----------------------------------------------------------------
                -- Idle & Arbitration
                ----------------------------------------------------------------
                when ST_IDLE =>
                    dq_oe <= '0';
                    -- Honour any delay the previous state asked for.
                    -- ST_PRECHARGE (tRP) and ST_BOOT_LMR (tMRD) both set
                    -- wait_cnt and then fell straight through to here,
                    -- where nothing consumed it -- so both delays were
                    -- silently skipped. At 50 MHz tRP still happened to
                    -- be met by the one cycle the state transition
                    -- provides, but tMRD (2 clocks, specified in clocks
                    -- rather than nanoseconds) was not: a request already
                    -- pending when boot finished issued ACTIVE one clock
                    -- after LOAD MODE REGISTER. Confirmed by the timing
                    -- assertions in sim/sdram_model.vhd.
                    --
                    -- PAGE MODE (added 2026-08-27): this controller used
                    -- to precharge unconditionally after every single
                    -- transaction, so every access -- no matter how close
                    -- together or to the same row -- paid a full
                    -- ACTIVATE+tRCD before and a PRECHARGE+tRP after.
                    -- vga_line_fetch (Phase 4.2) is the first thing in
                    -- this design to hammer the controller with 80
                    -- back-to-back word reads per scanline, continuously,
                    -- for the life of the device -- and since a 320-byte
                    -- scanline is smaller than the 512-byte row stride
                    -- (see the ADDRESS MAPPING note in the header), those
                    -- 80 reads mostly target the SAME open row. Real
                    -- hardware showed 80 clean vertical stripes: burst
                    -- beat 1 of every word always read back correct,
                    -- beat 2 always came back as unrepeatable garbage
                    -- (confirmed via vga_line_fetch's debug word-capture
                    -- ports piped out over UART) -- and a CPU-side
                    -- readback (slow, single accesses, the same path
                    -- that already reads WAD[0] back correctly) confirmed
                    -- the data is genuinely correct at rest in SDRAM.
                    -- Widening tRP/tRCD 2->6 cycles made no difference,
                    -- and delaying beat 2's own sample point by one cycle
                    -- broke sim/ghdl/tb_sdram.vhd outright (the burst has
                    -- ended by then; the bus is expected to have gone
                    -- high-Z). Neither pointed at the actual mechanism.
                    -- What IS architecturally unique about vga_line_fetch
                    -- versus every other access pattern this controller
                    -- has ever been tested against (including the
                    -- historical 5-word CPU bring-up test, which
                    -- deliberately spanned different rows and banks) is
                    -- the sheer rate of repeated ACTIVATE/PRECHARGE
                    -- cycling to the SAME row -- so this closes that gap:
                    -- track whether the requested row/bank is already
                    -- open (open_valid/open_bank/open_row below) and, if
                    -- so, skip ACTIVATE and its tRCD wait entirely,
                    -- issuing READ_CMD/WRITE_CMD immediately. A row is
                    -- now only closed (ST_PRECHARGE) when a request
                    -- targets a different row, or when a refresh is due,
                    -- both handled below.
                    if wait_cnt /= 0 then
                        wait_cnt <= wait_cnt - 1;
                    elsif refresh_req = '1' then
                        if open_valid = '1' then
                            -- Close the open row before refreshing; once
                            -- ST_PRECHARGE clears open_valid and returns
                            -- here, this branch is retaken with
                            -- open_valid='0' and refresh proceeds.
                            state <= ST_PRECHARGE;
                        else
                            send_cmd(CMD_REFRESH);
                            wait_cnt <= 4;
                            state    <= ST_REFRESH;
                        end if;
                    elsif (wb_cyc_i = '1' and wb_stb_i = '1') then
                        if open_valid = '1' and
                           (open_bank /= wb_adr_i(22 downto 21) or
                            open_row  /= wb_adr_i(20 downto 9)) then
                            -- Page miss: a different row is open. Close
                            -- it first; wb_cyc_i/wb_stb_i/wb_adr_i are
                            -- held stable by the master until ack, so
                            -- this same request is re-seen (and latched)
                            -- on the next pass through ST_IDLE once
                            -- open_valid is clear.
                            state <= ST_PRECHARGE;
                        else
                            latched_adr   <= wb_adr_i;
                            latched_wdata <= wb_dat_i;
                            latched_sel   <= wb_sel_i;

                            if open_valid = '1' then
                                -- Page hit: requested row already open --
                                -- skip ACTIVATE and its tRCD wait.
                                if wb_we_i = '1' then
                                    state <= ST_WRITE_CMD;
                                else
                                    state <= ST_READ_CMD;
                                end if;
                            else
                                -- No row open: issue ACTIVATE. See the
                                -- ADDRESS MAPPING note in the header for
                                -- why these slices are what they are.
                                send_cmd(CMD_ACTIVE);
                                sdram_ba   <= wb_adr_i(22 downto 21); -- Bank
                                sdram_addr <= wb_adr_i(20 downto 9);  -- Row
                                open_valid <= '1';
                                open_bank  <= wb_adr_i(22 downto 21);
                                open_row   <= wb_adr_i(20 downto 9);
                                -- tRCD delay. Was 2 (40 ns @ 50 MHz);
                                -- widened to 6 (120 ns, 3x this part's
                                -- ~15-20 ns tRCD spec) while chasing the
                                -- stripe bug -- kept at 6 since it's pure
                                -- margin and page mode makes ACTIVATE
                                -- infrequent enough that the extra cycles
                                -- cost nothing.
                                wait_cnt   <= 6;
                                state      <= ST_ACTIVE;
                            end if;
                        end if;
                    end if;

                when ST_REFRESH =>
                    if wait_cnt = 0 then
                        state <= ST_IDLE;
                    else
                        wait_cnt <= wait_cnt - 1;
                    end if;

                when ST_ACTIVE =>
                    if wait_cnt = 0 then
                        if wb_we_i = '1' then
                            state <= ST_WRITE_CMD;
                        else
                            state <= ST_READ_CMD;
                        end if;
                    else
                        wait_cnt <= wait_cnt - 1;
                    end if;

                ----------------------------------------------------------------
                -- Read Sequence (CAS Latency = 2, BL = 2)
                ----------------------------------------------------------------
                when ST_READ_CMD =>
                    send_cmd(CMD_READ);
                    sdram_ba       <= latched_adr(22 downto 21);
                    -- 8 column bits; bit 10 = '0' suppresses auto-precharge
                    -- (this controller precharges explicitly). See the
                    -- ADDRESS MAPPING and BURST ALIGNMENT notes in the
                    -- header -- adr(1) is forced to '0' so the burst
                    -- always starts on an even column.
                    sdram_addr     <= "0000" & latched_adr(8 downto 2) & '0';
                    sdram_dqm      <= "00";
                    -- See NOTE ON READ CAPTURE ALIGNMENT in the header.
                    wait_cnt       <= READ_CAS_WAIT;
                    state          <= ST_READ_WAIT;

                when ST_READ_WAIT =>
                    if wait_cnt = 0 then
                        state <= ST_READ_DATA;
                    else
                        wait_cnt <= wait_cnt - 1;
                    end if;

                when ST_READ_DATA =>
                    rdata_reg(15 downto 0) <= sdram_dq;
                    state                  <= ST_READ_DATA2;

                when ST_READ_DATA2 =>
                    rdata_reg(31 downto 16) <= sdram_dq;
                    wb_ack_o                <= '1';
                    -- Page mode (see ST_IDLE): leave the row open instead
                    -- of unconditionally precharging. ST_IDLE closes it
                    -- later only if a different row is requested or a
                    -- refresh comes due.
                    --
                    -- wait_cnt<=1 forces ST_IDLE to burn one cycle before
                    -- it looks at wb_cyc_i/wb_stb_i again. Without it,
                    -- ST_IDLE is re-entered the SAME cycle wb_ack_o goes
                    -- high, and a master whose wb_xfer-style protocol
                    -- drops cyc/stb one cycle AFTER observing the ack
                    -- (rather than the same cycle) still has the just-
                    -- completed request's stale cyc/stb/adr on the bus at
                    -- that instant -- so ST_IDLE spuriously re-latched and
                    -- re-issued that same already-finished request a
                    -- second time, silently shifting every subsequent
                    -- read/write by one. Caught by sim/ghdl/tb_sdram.vhd's
                    -- "sustained back-to-back traffic" test (104 failures,
                    -- every readback one word behind what was written) --
                    -- previously this race never showed up because every
                    -- transaction detoured through ST_PRECHARGE's 7+
                    -- cycles first, which incidentally gave the master
                    -- plenty of time to drop cyc/stb. One bubble cycle
                    -- here is far cheaper than that detour and preserves
                    -- it. Genuine back-to-back masters that hold cyc/stb
                    -- high continuously (already-updated address) are
                    -- unaffected -- they just see one extra idle cycle.
                    wait_cnt                <= 1;
                    state                   <= ST_IDLE;

                ----------------------------------------------------------------
                -- Write Sequence (BL = 2)
                ----------------------------------------------------------------
                when ST_WRITE_CMD =>
                    send_cmd(CMD_WRITE);
                    sdram_ba       <= latched_adr(22 downto 21);
                    -- Same slicing as ST_READ_CMD above -- see the
                    -- ADDRESS MAPPING and BURST ALIGNMENT notes in the
                    -- header.
                    sdram_addr     <= "0000" & latched_adr(8 downto 2) & '0';
                    sdram_dqm      <= not latched_sel(1 downto 0);
                    dq_out         <= latched_wdata(15 downto 0);
                    dq_oe          <= '1';
                    state          <= ST_WRITE_DATA2;

                when ST_WRITE_DATA2 =>
                    sdram_dqm      <= not latched_sel(3 downto 2);
                    dq_out         <= latched_wdata(31 downto 16);
                    wait_cnt       <= 2; -- tWR recovery
                    state          <= ST_WRITE_REC;

                when ST_WRITE_REC =>
                    dq_oe <= '0';
                    if wait_cnt = 0 then
                        wb_ack_o <= '1';
                        -- Page mode: leave the row open (see
                        -- ST_READ_DATA2). Same 1-cycle turnaround bubble
                        -- as ST_READ_DATA2, for the same reason.
                        wait_cnt <= 1;
                        state    <= ST_IDLE;
                    else
                        wait_cnt <= wait_cnt - 1;
                    end if;

                ----------------------------------------------------------------
                -- Precharge & Close Row
                ----------------------------------------------------------------
                -- Reached only from ST_IDLE, either because a request
                -- targets a row/bank other than the one currently open,
                -- or because a refresh is due and a row is open. Always
                -- closes whatever row is open (precharge-all-banks, as
                -- before) and clears open_valid so ST_IDLE's next pass
                -- re-evaluates cleanly.
                when ST_PRECHARGE =>
                    send_cmd(CMD_PRECHG);
                    sdram_addr(10) <= '1';
                    open_valid     <= '0';
                    -- tRP delay. Widened 2 -> 6 alongside ST_IDLE's
                    -- tRCD delay above -- see that comment for why.
                    wait_cnt <= 6;
                    state    <= ST_IDLE;

            end case;
        end if;
    end process;

end architecture rtl;
