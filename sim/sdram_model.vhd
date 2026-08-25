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
        tWR_CK  : natural := 2    -- last write beat -> PRECHARGE
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

    -- CAS Latency 2 Read Pipeline
    signal read_valid_0 : std_logic := '0';
    signal read_valid_1 : std_logic := '0';
    signal read_valid_2 : std_logic := '0';
    signal word0_reg    : std_logic_vector(15 downto 0) := (others => '0');
    signal word1_reg    : std_logic_vector(15 downto 0) := (others => '0');

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

    -- Burst Write Tracking
    signal write_active : std_logic := '0';
    signal write_cell1  : integer range 0 to N_BANKS * SIM_ROWS * N_COLS - 1 := 0;

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

begin

    -- Tri-state buffer for DQ (delayed by 1 clock to match CAS 2)
    dq <= word0_reg when (read_valid_1 = '1') else
          word1_reg when (read_valid_2 = '1') else
          (others => 'Z');

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

                -- Shift read valid pipeline
                read_valid_2 <= read_valid_1;
                read_valid_1 <= read_valid_0;
                read_valid_0 <= '0';

                -- Execute Cycle 2 of Burst Write
                if write_active = '1' then
                    if dqm(0) = '0' then
                        ram_block(write_cell1)(7 downto 0) <= dq(7 downto 0);
                    end if;
                    if dqm(1) = '0' then
                        ram_block(write_cell1)(15 downto 8) <= dq(15 downto 8);
                    end if;
                    write_active <= '0';
                    t_write_beat(bank_idx) <= now_ck;
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

                        -- addr(8) is deliberately NOT read: on a 256-column
                        -- part it is not a column bit, and dropping it here
                        -- is what makes a 9-bit-column controller alias in
                        -- simulation exactly as it does on hardware.
                        col_v := addr(7 downto 0);
                        col0  := to_integer(unsigned(col_v));
                        -- BL=2 sequential wraps inside the 2-word block,
                        -- so the second beat is the column with bit 0
                        -- flipped. It can never cross a row boundary.
                        col1  := to_integer(unsigned(col_v xor "00000001"));

                        cell0 := cell_index(bank_idx, active_row(bank_idx), col0);
                        cell1 := cell_index(bank_idx, active_row(bank_idx), col1);

                        if cmd = "0101" then      -- READ
                            word0_reg    <= ram_block(cell0);
                            word1_reg    <= ram_block(cell1);
                            read_valid_0 <= '1';  -- data on pins at CAS edge 2
                        else                      -- WRITE, beat 1
                            if dqm(0) = '0' then
                                ram_block(cell0)(7 downto 0) <= dq(7 downto 0);
                            end if;
                            if dqm(1) = '0' then
                                ram_block(cell0)(15 downto 8) <= dq(15 downto 8);
                            end if;
                            write_active        <= '1';
                            write_cell1         <= cell1;
                            t_write_beat(bank_idx) <= now_ck;
                        end if;

                    when "0000" => -- LOAD MODE REGISTER
                        t_lmr <= now_ck;

                    when others =>
                        null;
                end case;
            end if;
        end if;
    end process;

end architecture sim;
