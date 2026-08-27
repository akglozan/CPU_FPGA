-- SPDX-License-Identifier: Apache-2.0
--
-- vga_line_fetch.vhd -- Wishbone master (sys clk domain) that pulls one
-- 320-byte scanline out of the SDRAM-resident framebuffer per
-- start_fetch_pix pulse from vga_timing_gen (pix_clk domain), and
-- writes it into the inactive bank of vga_line_buffer.
--
-- CROSS-CLOCK HANDSHAKE: start_fetch_pix and line_num_pix both live in
-- the 25 MHz pix_clk domain; this module runs on the system clock.
-- vga_timing_gen holds line_num stable for an entire scanline period
-- (~1600 pix_clk cycles) between pulses, and this module captures both
-- the pulse (as a toggle bit) and the line value together, on the same
-- pix_clk edge, into registers that then stay constant across that same
-- long window -- so a plain 2-flop synchronizer on each is safe here
-- (this is the same "value changes rarely and stays stable far longer
-- than the synchronizer's settling time" pattern rst_sync.vhd and
-- rv32im_soc.vhd's boot_done synchronizer already use elsewhere in this
-- design), without needing a full request/acknowledge handshake back
-- across the boundary.
--
-- Fetches line (captured_line + 1) mod FB_HEIGHT -- i.e. the row AFTER
-- the one currently on screen when the pulse fires, giving this module
-- the rest of the current scanline plus the next one to finish before
-- the fetched row is actually needed for display.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.vga_pkg.all;

entity vga_line_fetch is
    port (
        clk   : in  std_logic;  -- sys clk domain
        rst_n : in  std_logic;

        -- From vga_timing_gen, pix_clk domain.
        pix_clk       : in  std_logic;
        pix_rst_n     : in  std_logic;
        start_fetch_pix : in  std_logic;
        line_num_pix    : in  unsigned(7 downto 0);

        -- Wishbone master, port B of sdram_arbiter. Read-only.
        wb_adr_o : out std_logic_vector(31 downto 0);
        wb_dat_i : in  std_logic_vector(31 downto 0);
        wb_sel_o : out std_logic_vector(3 downto 0);
        wb_we_o  : out std_logic;
        wb_stb_o : out std_logic;
        wb_cyc_o : out std_logic;
        wb_ack_i : in  std_logic;

        -- To vga_line_buffer's write port, sys clk domain.
        buf_wr_en   : out std_logic;
        buf_wr_bank : out std_logic;
        buf_wr_col  : out unsigned(8 downto 0);
        buf_wr_data : out std_logic_vector(7 downto 0);

        -- Which bank this module is (about to be) writing into, sys
        -- clk domain -- synchronized by vga_pixel_pipeline to derive
        -- which bank is safe to read from (the OTHER one). Changes at
        -- most once per scanline; safe to synchronize as a level, same
        -- reasoning as above.
        write_bank_o : out std_logic;

        -- TEMP DIAGNOSTIC (2026-08-27, remove once the SDRAM
        -- back-to-back read corruption is resolved): raw wb_dat_i as
        -- captured into word_reg for the first two words (col_word=0,
        -- col_word=1) of whichever scanline is currently being
        -- fetched. Free-running -- always holds the most recent
        -- fetch's values. With the framebuffer uniformly filled (as
        -- vga_smoke_test() does), a correct read means both read back
        -- as 0x01010101; firmware polls these to see the raw value
        -- this module actually received over the real SDRAM path,
        -- without needing a logic analyzer.
        dbg_word0_o : out std_logic_vector(31 downto 0);
        dbg_word1_o : out std_logic_vector(31 downto 0)
    );
end entity vga_line_fetch;

architecture rtl of vga_line_fetch is

    -- ---------------------------------------------------------------
    -- pix_clk-domain capture: toggle a bit and latch line_num_pix
    -- together on every start_fetch_pix pulse.
    -- ---------------------------------------------------------------
    signal pulse_toggle_pix  : std_logic := '0';
    signal captured_line_pix : unsigned(7 downto 0) := (others => '0');

    -- ---------------------------------------------------------------
    -- sys-clk-domain synchronizers.
    -- ---------------------------------------------------------------
    signal toggle_sync   : std_logic_vector(1 downto 0) := (others => '0');
    signal captured_line_sync : unsigned(7 downto 0) := (others => '0');
    signal fetch_pulse   : std_logic;  -- 1-cycle sys-clk pulse: new line ready to fetch

    type state_t is (ST_IDLE, ST_REQ, ST_WAIT, ST_UNPACK);
    signal state : state_t := ST_IDLE;

    signal target_line : unsigned(7 downto 0) := (others => '0');
    signal col_word     : unsigned(6 downto 0) := (others => '0');  -- 0..79 (320 bytes / 4)
    signal word_reg      : std_logic_vector(31 downto 0);

    -- TEMP DIAGNOSTIC (see dbg_word0_o/dbg_word1_o in the entity).
    signal dbg_word0 : std_logic_vector(31 downto 0) := (others => '0');
    signal dbg_word1 : std_logic_vector(31 downto 0) := (others => '0');
    signal byte_idx       : natural range 0 to 3 := 0;
    signal write_bank_r   : std_logic := '0';

begin

    -- -----------------------------------------------------------
    -- pix_clk domain: capture pulse + line value together.
    -- -----------------------------------------------------------
    process (pix_clk)
    begin
        if rising_edge(pix_clk) then
            if pix_rst_n = '0' then
                pulse_toggle_pix  <= '0';
                captured_line_pix <= (others => '0');
            elsif start_fetch_pix = '1' then
                captured_line_pix <= line_num_pix;
                pulse_toggle_pix  <= not pulse_toggle_pix;
            end if;
        end if;
    end process;

    -- -----------------------------------------------------------
    -- sys clk domain: 2-flop synchronize the toggle, edge-detect it
    -- into a 1-cycle pulse, and 2-flop synchronize the line value
    -- (see header for why a plain synchronizer is sufficient here).
    -- -----------------------------------------------------------
    process (clk)
    begin
        if rising_edge(clk) then
            if rst_n = '0' then
                toggle_sync        <= (others => '0');
                captured_line_sync <= (others => '0');
            else
                toggle_sync        <= toggle_sync(0) & pulse_toggle_pix;
                captured_line_sync <= captured_line_pix;
            end if;
        end if;
    end process;

    fetch_pulse <= toggle_sync(1) xor toggle_sync(0);

    -- -----------------------------------------------------------
    -- Fetch state machine.
    -- -----------------------------------------------------------
    process (clk)
    begin
        if rising_edge(clk) then
            if rst_n = '0' then
                state        <= ST_IDLE;
                wb_cyc_o     <= '0';
                wb_stb_o     <= '0';
                buf_wr_en    <= '0';
                write_bank_r <= '0';
                col_word     <= (others => '0');
            else
                buf_wr_en <= '0';  -- single-cycle pulse, default low

                case state is

                    when ST_IDLE =>
                        col_word <= (others => '0');
                        if fetch_pulse = '1' then
                            -- Fetch the line AFTER the one just
                            -- observed on screen, wrapping at
                            -- FB_HEIGHT.
                            if captured_line_sync = FB_HEIGHT - 1 then
                                target_line <= (others => '0');
                            else
                                target_line <= captured_line_sync + 1;
                            end if;
                            state <= ST_REQ;
                        end if;

                    when ST_REQ =>
                        -- NOTE: unsigned * natural (numeric_std) returns
                        -- a result L'length+L'length wide, not L'length
                        -- -- e.g. a 32-bit operand multiplied this way
                        -- yields 64 bits. Left unresized, the later
                        -- std_logic_vector(...) assignment to the
                        -- 32-bit wb_adr_o compiled fine (GHDL treats a
                        -- function-call-derived length as dynamic) but
                        -- failed at elaboration with a bound-check
                        -- error the first time this state actually ran
                        -- -- caught by sim/ghdl/tb_vga_line_fetch.vhd.
                        -- Each product is now explicitly resized to 32
                        -- bits before the addition.
                        wb_adr_o <= std_logic_vector(
                            unsigned(FB_BASE_ADDR)
                            + resize(target_line * to_unsigned(FB_WIDTH, 9), 32)
                            + resize(col_word * to_unsigned(4, 3), 32)
                        );
                        wb_sel_o <= "1111";
                        wb_we_o  <= '0';
                        wb_stb_o <= '1';
                        wb_cyc_o <= '1';
                        state    <= ST_WAIT;

                    when ST_WAIT =>
                        if wb_ack_i = '1' then
                            wb_stb_o  <= '0';
                            wb_cyc_o  <= '0';
                            word_reg  <= wb_dat_i;
                            byte_idx  <= 0;
                            state     <= ST_UNPACK;

                            -- TEMP DIAGNOSTIC: capture the raw word as
                            -- received, for word positions 0 and 1 of
                            -- whichever line is currently being
                            -- fetched. See dbg_word0_o/dbg_word1_o.
                            if col_word = 0 then
                                dbg_word0 <= wb_dat_i;
                            elsif col_word = 1 then
                                dbg_word1 <= wb_dat_i;
                            end if;
                        end if;

                    when ST_UNPACK =>
                        buf_wr_en   <= '1';
                        buf_wr_bank <= write_bank_r;
                        buf_wr_col  <= shift_left(resize(col_word, 9), 2)
                                       + to_unsigned(byte_idx, 9);
                        case byte_idx is
                            when 0 => buf_wr_data <= word_reg(7 downto 0);
                            when 1 => buf_wr_data <= word_reg(15 downto 8);
                            when 2 => buf_wr_data <= word_reg(23 downto 16);
                            when others => buf_wr_data <= word_reg(31 downto 24);
                        end case;

                        if byte_idx = 3 then
                            if col_word = 79 then
                                -- Line complete: flip the write bank
                                -- so vga_pixel_pipeline's synchronized
                                -- copy will start reading the row we
                                -- just filled once it flips too.
                                write_bank_r <= not write_bank_r;
                                state        <= ST_IDLE;
                            else
                                col_word <= col_word + 1;
                                state    <= ST_REQ;
                            end if;
                        else
                            byte_idx <= byte_idx + 1;
                        end if;

                end case;
            end if;
        end if;
    end process;

    write_bank_o <= write_bank_r;

    -- TEMP DIAGNOSTIC.
    dbg_word0_o <= dbg_word0;
    dbg_word1_o <= dbg_word1;

end architecture rtl;
