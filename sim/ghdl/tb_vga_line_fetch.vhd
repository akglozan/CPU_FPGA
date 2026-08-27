-------------------------------------------------------------------------------
-- tb_vga_line_fetch.vhd
--
-- Phase 4.2 regression test for the two riskiest new pieces: vga_line_fetch's
-- pix_clk -> sys_clk handshake (toggle + captured line_num, see that module's
-- header) and its SDRAM-word -> line-buffer-byte unpacking/addressing, wired
-- through a real vga_line_buffer DUT.
--
-- No CPU, no bus_interconnect, no real sdram_controller: a small fake
-- Wishbone slave stands in for SDRAM, always returning the WORD-ALIGNED
-- ADDRESS ITSELF as read data (after a fixed 3-cycle ack latency, loosely
-- modelling real SDRAM latency). That makes every fetched byte's expected
-- value fully predictable from address arithmetic alone, without needing a
-- backing memory array to pre-load.
--
-- Sequence:
--   1. Drive one start_fetch_pix pulse with line_num_pix = 5 (pix_clk
--      domain). Expected target line = 6 (fetch fetches the line AFTER the
--      one just shown). Wait for the fetch to finish, then read all 320
--      bytes back out of vga_line_buffer's bank 0 (the initial write bank)
--      and check each against the address arithmetic vga_line_fetch should
--      have used.
--   2. Drive a second pulse with line_num_pix = 199 (frame-wrap case:
--      target line must wrap to 0, not 200). Confirm write_bank_o has
--      flipped to '1' once this second fetch completes, and spot-check a
--      handful of bytes out of bank 1.
--   3. Drive a third pulse and confirm write_bank_o flips back to '0' --
--      the ping-pong toggling survives more than one cycle, not just the
--      first flip.
--
-- Self-terminating on a generous fixed timeout, same "run -all" discipline
-- as tb_vga_timing_gen.vhd and tb_boot_path.vhd -- not a guessed "run <time>".
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.vga_pkg.all;

entity tb_vga_line_fetch is
end entity;

architecture sim of tb_vga_line_fetch is

    constant SYS_PERIOD : time := 20 ns;  -- 50 MHz
    constant PIX_PERIOD : time := 40 ns;  -- 25 MHz
    constant ACK_LATENCY : natural := 3;  -- fake slave's fixed wait states

    signal clk, rst_n         : std_logic := '0';
    signal pix_clk, pix_rst_n : std_logic := '0';

    signal sim_finished : boolean := false;

    -- Stimulus into the DUT.
    signal start_fetch_pix : std_logic := '0';
    signal line_num_pix    : unsigned(7 downto 0) := (others => '0');

    -- DUT <-> fake SDRAM slave.
    signal wb_adr  : std_logic_vector(31 downto 0);
    signal wb_dat  : std_logic_vector(31 downto 0);
    signal wb_sel  : std_logic_vector(3 downto 0);
    signal wb_we   : std_logic;
    signal wb_stb  : std_logic;
    signal wb_cyc  : std_logic;
    signal wb_ack  : std_logic;

    -- DUT <-> line buffer.
    signal lb_wr_en, lb_wr_bank : std_logic;
    signal lb_wr_col            : unsigned(8 downto 0);
    signal lb_wr_data           : std_logic_vector(7 downto 0);
    signal write_bank           : std_logic;

    signal lb_rd_bank : std_logic := '0';
    signal lb_rd_col  : unsigned(8 downto 0) := (others => '0');
    signal lb_rd_data : std_logic_vector(7 downto 0);

    signal errors : natural := 0;

    -- Expected byte for (line, col): mirrors vga_line_fetch's own address
    -- arithmetic (FB_BASE_ADDR + line*FB_WIDTH + word_index*4), then picks
    -- out the byte lane the fake slave's "data = address" response puts
    -- there.
    function expected_byte(line : natural; col : natural) return std_logic_vector is
        variable word_addr : unsigned(31 downto 0);
        variable lane       : natural;
    begin
        word_addr := unsigned(FB_BASE_ADDR)
                     + to_unsigned(line * FB_WIDTH + (col - (col mod 4)), 32);
        lane := (col mod 4) * 8;
        return std_logic_vector(word_addr(lane + 7 downto lane));
    end function;

begin

    -- ---------------------------------------------------------------
    -- Clocks.
    -- ---------------------------------------------------------------
    clk_process : process
    begin
        while not sim_finished loop
            clk <= '0'; wait for SYS_PERIOD / 2;
            clk <= '1'; wait for SYS_PERIOD / 2;
        end loop;
        wait;
    end process;

    pix_clk_process : process
    begin
        while not sim_finished loop
            pix_clk <= '0'; wait for PIX_PERIOD / 2;
            pix_clk <= '1'; wait for PIX_PERIOD / 2;
        end loop;
        wait;
    end process;

    -- ---------------------------------------------------------------
    -- Fake SDRAM slave: acks ACK_LATENCY cycles after stb/cyc, always
    -- returning the word-aligned address as data.
    -- ---------------------------------------------------------------
    fake_slave : process (clk)
        variable wait_cnt : natural := 0;
        variable busy     : boolean := false;
    begin
        if rising_edge(clk) then
            if rst_n = '0' then
                wb_ack <= '0';
                busy   := false;
                wait_cnt := 0;
            else
                wb_ack <= '0';
                if not busy then
                    if wb_cyc = '1' and wb_stb = '1' then
                        busy     := true;
                        wait_cnt := ACK_LATENCY;
                    end if;
                else
                    if wait_cnt = 0 then
                        wb_dat <= wb_adr;
                        wb_ack <= '1';
                        busy   := false;
                    else
                        wait_cnt := wait_cnt - 1;
                    end if;
                end if;
            end if;
        end if;
    end process;

    -- ---------------------------------------------------------------
    -- DUTs.
    -- ---------------------------------------------------------------
    DUT_FETCH : entity work.vga_line_fetch
        port map (
            clk             => clk,
            rst_n           => rst_n,
            pix_clk         => pix_clk,
            pix_rst_n       => pix_rst_n,
            start_fetch_pix => start_fetch_pix,
            line_num_pix    => line_num_pix,

            wb_adr_o => wb_adr,
            wb_dat_i => wb_dat,
            wb_sel_o => wb_sel,
            wb_we_o  => wb_we,
            wb_stb_o => wb_stb,
            wb_cyc_o => wb_cyc,
            wb_ack_i => wb_ack,

            buf_wr_en    => lb_wr_en,
            buf_wr_bank  => lb_wr_bank,
            buf_wr_col   => lb_wr_col,
            buf_wr_data  => lb_wr_data,
            write_bank_o => write_bank
        );

    DUT_LINE_BUFFER : entity work.vga_line_buffer
        port map (
            wr_clk  => clk,
            wr_en   => lb_wr_en,
            wr_bank => lb_wr_bank,
            wr_col  => lb_wr_col,
            wr_data => lb_wr_data,

            rd_clk  => clk,  -- read from the sys-clk side in this tb; the
                              -- DUT itself is clock-domain-agnostic on its
                              -- read port (see vga_line_buffer.vhd)
            rd_bank => lb_rd_bank,
            rd_col  => lb_rd_col,
            rd_data => lb_rd_data
        );

    -- ---------------------------------------------------------------
    -- Stimulus + self-check.
    -- ---------------------------------------------------------------
    stim_process : process
        procedure pulse_start_fetch(line_val : natural) is
        begin
            wait until rising_edge(pix_clk);
            line_num_pix    <= to_unsigned(line_val, 8);
            start_fetch_pix <= '1';
            wait until rising_edge(pix_clk);
            start_fetch_pix <= '0';
        end procedure;

        -- Poll for write_bank to reach the expected value rather than
        -- sleeping a fixed guessed duration -- an earlier version of
        -- this testbench used a fixed "wait for" margin that turned out
        -- to be shorter than a real 80-word fetch actually takes (it
        -- fired right at the boundary, not because of a DUT bug), which
        -- is exactly the kind of guessed-timeout mistake
        -- tb_vga_timing_gen.vhd's own header warns against. TIMEOUT is
        -- still generous headroom over the ~800-900 sys-clk-cycle fetch
        -- this actually takes (80 words * ~10-11 cycles/word).
        constant BANK_TIMEOUT : time := 2000 * SYS_PERIOD;

        procedure wait_for_bank(expected : std_logic) is
            variable t0 : time := now;
        begin
            while write_bank /= expected and (now - t0) < BANK_TIMEOUT loop
                wait until rising_edge(clk);
            end loop;
            if write_bank /= expected then
                errors <= errors + 1;
                report "write_bank never reached '" & std_logic'image(expected) &
                       "' within " & time'image(BANK_TIMEOUT)
                    severity error;
            end if;
        end procedure;

        procedure check_line(bank_val : natural; line_val : natural) is
        begin
            for col in 0 to FB_WIDTH - 1 loop
                if bank_val = 1 then
                    lb_rd_bank <= '1';
                else
                    lb_rd_bank <= '0';
                end if;
                lb_rd_col <= to_unsigned(col, 9);
                wait until rising_edge(clk);  -- present address
                wait until rising_edge(clk);  -- 1-cycle RAM read latency
                if lb_rd_data /= expected_byte(line_val, col) then
                    errors <= errors + 1;
                    report "line_buffer mismatch: bank=" & integer'image(bank_val) &
                           " col=" & integer'image(col) &
                           " line=" & integer'image(line_val)
                        severity error;
                end if;
            end loop;
        end procedure;
    begin
        rst_n     <= '0';
        pix_rst_n <= '0';
        wait for 200 ns;
        rst_n     <= '1';
        pix_rst_n <= '1';
        wait for 200 ns;

        -- --- Fetch 1: line_num_pix = 5 -> target line 6, bank 0 -> 1 ---
        pulse_start_fetch(5);
        wait_for_bank('1');
        check_line(0, 6);

        -- --- Fetch 2: line_num_pix = 199 (frame wrap) -> target line 0,
        --     bank 1 -> 0 ---
        pulse_start_fetch(199);
        wait_for_bank('0');
        check_line(1, 0);

        -- --- Fetch 3: confirm ping-pong keeps alternating, not just once.
        pulse_start_fetch(10);
        wait_for_bank('1');
        check_line(0, 11);

        if errors = 0 then
            report "tb_vga_line_fetch: ALL CHECKS PASSED" severity note;
        else
            report "tb_vga_line_fetch: " & integer'image(errors) & " CHECK(S) FAILED"
                severity error;
        end if;

        sim_finished <= true;
        wait;
    end process;

end architecture sim;
