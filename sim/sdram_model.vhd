-- SPDX-License-Identifier: Apache-2.0
-- Copyright 2026 Ozan Akgül
--
-- Behavioural model of a 16-bit SDR SDRAM, used by
-- sim/ghdl/tb_sdram.vhd and the ModelSim flow. Simulation only -- never
-- add this to a synthesis file list.
--
-- ADDRESS DECODE (fixed 2026-08-23)
--
-- The previous version decoded the column as addr(8 downto 1) and built
-- its storage index as row(5 downto 0)*256 + col, with the bank not in
-- the index at all. Three consequences, all of which made the model
-- disagree with any real chip:
--
--   1. Dropping addr(0) halved the column resolution. The controller
--      drives a full 9-bit column, adr(9 downto 1), so consecutive
--      32-bit CPU words landed one 16-bit cell apart instead of two and
--      OVERLAPPED: writing 0x8000_0004 corrupted the upper half of
--      0x8000_0000. Reading it back gave 0xBABEBEEF instead of
--      0xDEADBEEF.
--   2. The bank was ignored, so all four banks aliased onto the same
--      storage -- a write to 0x8040_0000 (bank 1) destroyed
--      0x8000_0000 (bank 0).
--   3. Only 6 row bits were used against a 12-bit row address.
--
-- Bank and column are now decoded in full. Only the low SIM_ROWS rows of
-- each bank are stored -- backing every row with VHDL signals is
-- impractical -- so rows at or above SIM_ROWS fold onto lower ones. That
-- is the one deliberate departure from real behaviour.
--
-- COLUMN WIDTH (fixed 2026-08-25)
--
-- This model previously declared 512 columns and decoded a 9-bit column
-- from addr(8 downto 0), described in the comment above as what "a real
-- part" does. That was wrong for the fitted chip and, worse, it was
-- wrong in exactly the same way sdram_controller.vhd was wrong: the
-- controller drove a 9-bit column too. A model that reproduces the
-- design's own mistake cannot fail on it, which is why sim/tb_boot_path
-- passed cleanly while real hardware silently corrupted every transfer
-- larger than 512 bytes.
--
-- The board's part is a Winbond W9864G6KH-6: 64 Mbit as 4M x 16, i.e.
-- 4 banks x 4096 rows x 256 columns. 256 columns is an 8-bit column
-- address, A7-A0. A8 is NOT a column bit -- a real part ignores it
-- during READ/WRITE -- so this model now decodes addr(7 downto 0) and
-- lets addr(8) fall on the floor, precisely as the chip does. Any future
-- regression to a 9-bit column will now alias here the same way it
-- aliases on hardware, and tb_boot_path.vhd's two-file test below will
-- catch it. See the ADDRESS MAPPING note in rtl/memory/sdram_controller.vhd.

library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;

entity sdram_model is
    generic (
        -- Minimum command spacing, in clocks at the system frequency.
        -- Defaults are for a common -7 grade 16-bit SDR part at 50 MHz
        -- (20 ns period): tRP/tRCD ~20 ns -> 1 clock, tRAS ~42 ns -> 3,
        -- tRC ~63 ns -> 4. tMRD and tWR are specified in clocks by the
        -- datasheet, not nanoseconds.
        tRP_CK  : natural := 1;   -- PRECHARGE -> ACTIVE, same bank
        tRCD_CK : natural := 1;   -- ACTIVE -> READ/WRITE, same bank
        tRAS_CK : natural := 3;   -- ACTIVE -> PRECHARGE, same bank
        tRC_CK  : natural := 4;   -- ACTIVE -> ACTIVE, same bank
        tMRD_CK : natural := 2;   -- LOAD MODE REGISTER -> any command
        tWR_CK  : natural := 2;   -- last write beat -> PRECHARGE

        -- Fail on a READ/WRITE whose start column is not aligned to the
        -- programmed burst length. See the BURST ALIGNMENT CHECK below.
        -- Settable so a testbench that deliberately exercises wrapped
        -- bursts can turn it off; nothing in this project does.
        strict_burst_align : boolean := true
    );
    port (
        clk     : in    std_logic;
        cke     : in    std_logic;
        cs_n    : in    std_logic;
        ras_n   : in    std_logic;
        cas_n   : in    std_logic;
        we_n    : in    std_logic;
        ba      : in    std_logic_vector(1 downto 0);
        addr    : in    std_logic_vector(11 downto 0);
        dqm     : in    std_logic_vector(1 downto 0);
        dq      : inout std_logic_vector(15 downto 0)
    );
end entity sdram_model;

architecture sim of sdram_model is

    constant N_BANKS  : natural := 4;
    constant N_COLS   : natural := 256;   -- 8-bit column, A7-A0 (see header)
    constant SIM_ROWS : natural := 64;    -- rows actually backed by storage

    type ram_type is array (0 to N_BANKS * SIM_ROWS * N_COLS - 1)
        of std_logic_vector(15 downto 0);
    signal ram_block : ram_type := (others => (others => '0'));

    type row_array is array (0 to 3) of std_logic_vector(11 downto 0);
    signal active_row   : row_array := (others => (others => '0'));
    signal bank_active  : std_logic_vector(3 downto 0) := (others => '0');

    -- ------------------------------------------------------------------
    -- MODE REGISTER (honoured since 2026-08-27)
    --
    -- This model used to treat LOAD MODE REGISTER as a no-op that merely
    -- timestamped itself for the tMRD check, with burst length 2 and CAS
    -- latency 2 HARDCODED into a fixed three-stage pipeline. That made a
    -- whole class of bug structurally invisible: if the controller ever
    -- programmed the wrong burst length, or the LOAD MODE REGISTER command
    -- failed to land at all, every testbench would still pass while real
    -- hardware returned one good beat followed by a floating bus for the
    -- second. That is precisely the failure mode described in the COLUMN
    -- WIDTH note above -- a model that shares the design's own assumption
    -- cannot fail on it.
    --
    -- The register is now decoded and enforced, so burst length, burst
    -- type and CAS latency all come from what the controller actually
    -- programmed, and a READ/WRITE issued before any LOAD MODE REGISTER
    -- is a hard error rather than silently working.
    --
    -- Field layout (JEDEC SDR, A11..A0):
    --   A2..A0  burst length   000=1 001=2 010=4 011=8 111=full page
    --   A3      burst type     0=sequential 1=interleaved
    --   A6..A4  CAS latency    010=2 011=3
    --   A8..A7  operating mode 00=standard
    --   A9      write burst    0=same length as read 1=single location
    -- ------------------------------------------------------------------
    signal mr_loaded    : std_logic := '0';
    signal mr_burst_len : natural   := 0;
    signal mr_interleav : std_logic := '0';
    signal mr_cas_lat   : natural   := 0;
    signal mr_wr_single : std_logic := '0';

    -- Read data pipeline. Deep enough for the worst legal combination
    -- (CAS 3 + burst 8) with slack. Slot 0 is what DQ drives during the
    -- current cycle, and every rising edge shifts the whole thing down by
    -- one. A READ schedules its beat k into slot CL-1+k, so beat k becomes
    -- sampleable exactly CL+k edges after the command was captured.
    constant PIPE_DEPTH : natural := 12;
    type dq_pipe_t is array (0 to PIPE_DEPTH) of std_logic_vector(15 downto 0);
    signal dq_pipe   : dq_pipe_t := (others => (others => '0'));
    signal dq_pipe_v : std_logic_vector(0 to PIPE_DEPTH) := (others => '0');

    -- Timing checks. A real part silently corrupts data when command
    -- spacing is violated; here we say so instead. NEVER_YET is far
    -- enough in the past that the first command of each kind passes.
    constant NEVER_YET : integer := -1000;
    type cycle_array is array (0 to 3) of integer;
    signal now_ck        : integer := 0;
    signal t_precharge   : cycle_array := (others => NEVER_YET);
    signal t_active      : cycle_array := (others => NEVER_YET);
    signal t_write_beat  : cycle_array := (others => NEVER_YET);
    signal t_lmr         : integer := NEVER_YET;

    -- Burst write tracking: beats after the first, which lands on the same
    -- edge as the WRITE command itself (write latency 0).
    signal wr_active : std_logic := '0';
    signal wr_beat   : natural   := 0;
    signal wr_len    : natural   := 0;
    signal wr_bank   : integer range 0 to 3 := 0;
    signal wr_col0   : integer range 0 to N_COLS - 1 := 0;

    -- Storage index for one {bank, open row, column} triple.
    function cell_index (
        bank : integer;
        row  : std_logic_vector(11 downto 0);
        col  : integer
    ) return integer is
    begin
        return ((bank * SIM_ROWS) + (to_integer(unsigned(row)) mod SIM_ROWS))
               * N_COLS + col;
    end function;

    -- Column visited by beat k of a burst that started at column c.
    -- A burst never leaves its own naturally-aligned block of bl columns:
    -- sequential mode counts up and wraps inside the block, interleaved
    -- mode XORs the beat index in. This is why a burst can never cross a
    -- row boundary regardless of where it starts.
    function burst_col (
        c          : integer;
        k          : integer;
        bl         : integer;
        interleave : std_logic
    ) return integer is
        variable blk : integer;
    begin
        if bl <= 1 then
            return c;
        end if;
        if interleave = '1' then
            return (c / bl) * bl +
                   (to_integer(to_unsigned(c mod bl, 8) xor
                               to_unsigned(k, 8)) mod bl);
        end if;
        blk := (c / bl) * bl;
        return blk + (((c - blk) + k) mod bl);
    end function;

begin

    -- Tri-state buffer for DQ. Driven only while the read pipeline has a
    -- scheduled beat in slot 0; at every other moment the model releases
    -- the bus, so a controller that samples outside its burst window sees
    -- 'Z' here and reads a floating bus on hardware.
    dq <= dq_pipe(0) when dq_pipe_v(0) = '1' else (others => 'Z');

    process(clk)
        variable cmd       : std_logic_vector(3 downto 0);
        variable bank_idx  : integer range 0 to 3;
        variable col_v     : std_logic_vector(7 downto 0);
        variable col0      : integer range 0 to N_COLS - 1;
        variable col1      : integer range 0 to N_COLS - 1;
        variable cell0     : integer range 0 to N_BANKS * SIM_ROWS * N_COLS - 1;
        variable cell1     : integer range 0 to N_BANKS * SIM_ROWS * N_COLS - 1;
        procedure check_gap (
            what     : string;
            since    : integer;
            min_ck   : natural;
            bank     : integer
        ) is
        begin
            if since /= NEVER_YET and (now_ck - since) < min_ck then
                report "sdram_model: TIMING VIOLATION " & what &
                       " on bank " & integer'image(bank) &
                       " -- " & integer'image(now_ck - since) &
                       " clocks elapsed, minimum is " & integer'image(min_ck)
                       severity warning;
            end if;
        end procedure;
    begin
        if rising_edge(clk) then
            if cke = '1' then
                now_ck   <= now_ck + 1;
                cmd      := cs_n & ras_n & cas_n & we_n;
                bank_idx := to_integer(unsigned(ba));

                -- Shift the read data pipeline down by one slot. A READ
                -- handled later in this same process overrides the slots
                -- it schedules into, so ordering here is safe.
                for s in 0 to PIPE_DEPTH - 1 loop
                    dq_pipe(s)   <= dq_pipe(s + 1);
                    dq_pipe_v(s) <= dq_pipe_v(s + 1);
                end loop;
                dq_pipe(PIPE_DEPTH)   <= (others => '0');
                dq_pipe_v(PIPE_DEPTH) <= '0';

                -- Remaining beats of a burst write.
                if wr_active = '1' then
                    cell1 := cell_index(wr_bank, active_row(wr_bank),
                                        burst_col(wr_col0, wr_beat, wr_len,
                                                  mr_interleav));
                    if dqm(0) = '0' then
                        ram_block(cell1)(7 downto 0) <= dq(7 downto 0);
                    end if;
                    if dqm(1) = '0' then
                        ram_block(cell1)(15 downto 8) <= dq(15 downto 8);
                    end if;
                    t_write_beat(wr_bank) <= now_ck;
                    if wr_beat >= wr_len - 1 then
                        wr_active <= '0';
                    else
                        wr_beat <= wr_beat + 1;
                    end if;
                end if;

                case cmd is
                    when "0011" => -- ACTIVE
                        check_gap("tRP  (PRECHARGE->ACTIVE)", t_precharge(bank_idx), tRP_CK,  bank_idx);
                        check_gap("tRC  (ACTIVE->ACTIVE)",    t_active(bank_idx),    tRC_CK,  bank_idx);
                        check_gap("tMRD (LOAD_MR->command)",  t_lmr,                 tMRD_CK, bank_idx);
                        bank_active(bank_idx) <= '1';
                        active_row(bank_idx)  <= addr;
                        t_active(bank_idx)    <= now_ck;

                    when "0010" => -- PRECHARGE
                        check_gap("tMRD (LOAD_MR->command)", t_lmr, tMRD_CK, bank_idx);
                        if addr(10) = '1' then
                            for b in 0 to 3 loop
                                if bank_active(b) = '1' then
                                    check_gap("tRAS (ACTIVE->PRECHARGE)",   t_active(b),     tRAS_CK, b);
                                    check_gap("tWR  (write beat->PRECHARGE)", t_write_beat(b), tWR_CK,  b);
                                end if;
                                t_precharge(b) <= now_ck;
                            end loop;
                            bank_active <= (others => '0');
                        else
                            if bank_active(bank_idx) = '1' then
                                check_gap("tRAS (ACTIVE->PRECHARGE)",   t_active(bank_idx),     tRAS_CK, bank_idx);
                                check_gap("tWR  (write beat->PRECHARGE)", t_write_beat(bank_idx), tWR_CK,  bank_idx);
                            end if;
                            t_precharge(bank_idx) <= now_ck;
                            bank_active(bank_idx) <= '0';
                        end if;

                    when "0101" | "0100" => -- READ or WRITE
                        -- A real part needs the row open first; flag it
                        -- rather than silently returning plausible data.
                        assert bank_active(bank_idx) = '1'
                            report "sdram_model: access to bank " &
                                   integer'image(bank_idx) &
                                   " with no row activated"
                            severity warning;

                        check_gap("tRCD (ACTIVE->READ/WRITE)", t_active(bank_idx), tRCD_CK, bank_idx);
                        check_gap("tMRD (LOAD_MR->command)",   t_lmr,              tMRD_CK, bank_idx);

                        -- The burst length and CAS latency used from here
                        -- on are whatever LOAD MODE REGISTER actually
                        -- programmed -- not an assumption baked into this
                        -- model. Accessing the array before the mode
                        -- register has been written is undefined on a real
                        -- part, so refuse to invent behaviour for it.
                        assert mr_loaded = '1'
                            report "sdram_model: READ/WRITE issued before " &
                                   "any LOAD MODE REGISTER -- burst length " &
                                   "and CAS latency are undefined"
                            severity failure;

                        -- addr(8) is deliberately NOT read: on a 256-column
                        -- part it is not a column bit, and dropping it here
                        -- is what makes a 9-bit-column controller alias in
                        -- simulation exactly as it does on hardware.
                        col_v := addr(7 downto 0);
                        col0  := to_integer(unsigned(col_v));

                        -- BURST ALIGNMENT CHECK (added 2026-08-27 after the
                        -- bug it would have caught -- see the NOTE ON BURST
                        -- ALIGNMENT in rtl/memory/sdram_controller.vhd).
                        --
                        -- A burst never leaves its own naturally-aligned
                        -- block of mr_burst_len columns: starting anywhere
                        -- but the bottom of that block, it counts up and
                        -- then WRAPS BACK to the start of the block. That
                        -- is legal, specified behaviour, so a real chip
                        -- does it silently and a controller that assumed
                        -- otherwise just gets its beats permuted -- which
                        -- is exactly how a byte store to an odd halfword
                        -- ended up writing the wrong column on hardware
                        -- while every testbench passed.
                        --
                        -- Almost no controller wants the wrapped ordering.
                        -- Flag it loudly rather than quietly reordering the
                        -- data, so the next controller that gets this wrong
                        -- fails in simulation instead of on the bench.
                        if strict_burst_align and mr_burst_len > 1 and
                           (col0 mod mr_burst_len) /= 0 then
                            report "sdram_model: UNALIGNED BURST START -- " &
                                   "column " & integer'image(col0) &
                                   " is not a multiple of the programmed " &
                                   "burst length " &
                                   integer'image(mr_burst_len) &
                                   ", so this burst wraps backwards inside " &
                                   "its column block and delivers its beats " &
                                   "in a rotated order"
                                   severity failure;
                        end if;

                        if cmd = "0101" then      -- READ
                            -- Schedule every beat the programmed burst
                            -- length calls for. Beat k is driven CL-1+k
                            -- slots out, so the controller can sample it
                            -- CL+k edges after this command.
                            for k in 0 to mr_burst_len - 1 loop
                                cell1 := cell_index(
                                    bank_idx, active_row(bank_idx),
                                    burst_col(col0, k, mr_burst_len,
                                              mr_interleav));
                                dq_pipe(mr_cas_lat - 1 + k)   <= ram_block(cell1);
                                dq_pipe_v(mr_cas_lat - 1 + k) <= '1';
                            end loop;
                        else                      -- WRITE, first beat
                            cell0 := cell_index(bank_idx,
                                                active_row(bank_idx), col0);
                            if dqm(0) = '0' then
                                ram_block(cell0)(7 downto 0) <= dq(7 downto 0);
                            end if;
                            if dqm(1) = '0' then
                                ram_block(cell0)(15 downto 8) <= dq(15 downto 8);
                            end if;
                            t_write_beat(bank_idx) <= now_ck;

                            -- A9=1 in the mode register makes writes
                            -- single-location regardless of burst length.
                            if mr_wr_single = '0' and mr_burst_len > 1 then
                                wr_active <= '1';
                                wr_beat   <= 1;
                                wr_len    <= mr_burst_len;
                                wr_bank   <= bank_idx;
                                wr_col0   <= col0;
                            end if;
                        end if;

                    when "0000" => -- LOAD MODE REGISTER
                        t_lmr     <= now_ck;
                        mr_loaded <= '1';

                        case addr(2 downto 0) is
                            when "000"  => mr_burst_len <= 1;
                            when "001"  => mr_burst_len <= 2;
                            when "010"  => mr_burst_len <= 4;
                            when "011"  => mr_burst_len <= 8;
                            when others =>
                                report "sdram_model: unsupported burst " &
                                       "length field A2..A0 in mode register"
                                       severity failure;
                        end case;

                        case addr(6 downto 4) is
                            when "010"  => mr_cas_lat <= 2;
                            when "011"  => mr_cas_lat <= 3;
                            when others =>
                                report "sdram_model: unsupported CAS " &
                                       "latency field A6..A4 in mode register"
                                       severity failure;
                        end case;

                        assert addr(8 downto 7) = "00"
                            report "sdram_model: mode register operating " &
                                   "mode A8..A7 must be 00"
                            severity failure;

                        mr_interleav <= addr(3);
                        mr_wr_single <= addr(9);

                        report "sdram_model: mode register loaded -- " &
                               "BL field=" & integer'image(
                                   to_integer(unsigned(addr(2 downto 0)))) &
                               " CL field=" & integer'image(
                                   to_integer(unsigned(addr(6 downto 4)))) &
                               " burst type=" & std_logic'image(addr(3))
                               severity note;

                    when others =>
                        null;
                end case;
            end if;
        end if;
    end process;

end architecture sim;
