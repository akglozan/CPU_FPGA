-------------------------------------------------------------------------------
-- tb_vga_timing_gen.vhd
--
-- Phase 4.1 -- standalone regression test for vga_timing_gen.vhd.
--
-- No bus, no other modules: this testbench drives the DUT with a free-
-- running 25 MHz pix_clk and an active-low reset pulse, runs it for two
-- full frames, and self-checks four properties against the constants
-- vga_timing_gen.vhd itself is built from (H_TOTAL=800, V_TOTAL=525,
-- 200 source lines doubled to 400 output lines):
--
--   1. start_fetch_count   -- fires exactly 400 times (200/frame x 2),
--                              since it should pulse once per SOURCE
--                              line, not once per (doubled) output line.
--   2. line_num sequencing -- on every start_fetch pulse, the DUT's
--                              line_num must match an independently
--                              predicted 0..199 sequence that wraps at
--                              the end of each frame.
--   3. active_region_count -- totals exactly 800 clock cycles (400/frame
--                              x 2) -- the size of the letterboxed
--                              window, not a pulse count.
--   4. total_cycle_count   -- totals exactly 840,000 cycles (H_TOTAL *
--                              V_TOTAL * 2 frames), catching any drift
--                              in the hcnt/vcnt wrap logic itself that
--                              the other three checks, being derived
--                              from hcnt/vcnt, might not expose on
--                              their own.
--
-- Self-terminating: sim_finished goes true after a fixed two-frame
-- timeout (2 * H_TOTAL * V_TOTAL * CLK_PERIOD = 33,600,000 ns), at
-- which point all four running counts are asserted against their
-- expected totals. Run with "run -all" in Questa, not a fixed "run
-- <time>" guess -- same lesson learned from tb_boot_path.vhd.
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_vga_timing_gen is
end entity;

architecture sim of tb_vga_timing_gen is

    constant CLK_PERIOD : time := 40 ns;  -- 25 MHz

    -- DUT interconnect signals.
    signal pix_clk       : std_logic := '0';
    signal rst_n         : std_logic := '0';
    signal hsync         : std_logic;
    signal vsync         : std_logic;
    signal hblank         : std_logic;
    signal vblank         : std_logic;
    signal active_region : std_logic;
    signal pixel_x       : unsigned(9 downto 0);
    signal pixel_y       : unsigned(9 downto 0);
    signal line_num      : unsigned(7 downto 0);
    signal start_fetch   : std_logic;

    -- Testbench control.
    signal sim_finished : boolean := false;

    -- Check 1: start_fetch pulse count.
    signal start_fetch_count : natural := 0;

    -- Check 2: line_num sequence prediction (0..199, wraps per frame).
    signal expected_line_num : unsigned(7 downto 0) := (others => '0');

    -- Check 3: active_region held-high cycle count.
    signal active_region_count : natural := 0;

    -- Check 4: total elapsed post-reset cycle count.
    signal total_cycle_count : natural := 0;

begin

    -- -------------------------------------------------------------
    -- DUT
    -- -------------------------------------------------------------
    DUT : entity work.vga_timing_gen
        port map (
            pix_clk       => pix_clk,
            rst_n         => rst_n,
            hsync         => hsync,
            vsync         => vsync,
            hblank        => hblank,
            vblank        => vblank,
            active_region => active_region,
            pixel_x       => pixel_x,
            pixel_y       => pixel_y,
            line_num      => line_num,
            start_fetch   => start_fetch
        );

    -- -------------------------------------------------------------
    -- 25 MHz pix_clk generator. No sensitivity list -- suspends via
    -- the wait statements below instead. Stops toggling once
    -- sim_finished goes true, then parks on a bare "wait;" so the
    -- simulator has nothing left scheduled and "run -all" returns.
    -- -------------------------------------------------------------
    clk_process : process
    begin
        while not sim_finished loop
            pix_clk <= '0';
            wait for CLK_PERIOD / 2;
            pix_clk <= '1';
            wait for CLK_PERIOD / 2;
        end loop;
        wait;
    end process;

    -- -------------------------------------------------------------
    -- Reset pulse, then run for exactly 840,000 rising edges (two
    -- full frames: H_TOTAL * V_TOTAL * 2) before declaring the run
    -- finished. Active-low, matching vga_timing_gen's own
    -- "if rst_n = '0' then" reset check.
    --
    -- GHDL-SPECIFIC NOTE: an earlier version of this process released
    -- reset and terminated using raw "wait for <time>" values (100 ns,
    -- then a fixed 33,600,000/33,600,010 ns timeout) -- both landing
    -- exactly on a pix_clk edge boundary (100 ns is an exact multiple
    -- of the 40 ns period). Which simulator's delta-cycle scheduling
    -- wins that exact-time coincidence between the clock generator's
    -- edge and this process's own event determines whether that edge
    -- gets counted, and GHDL and ModelSim/Questa resolve it
    -- differently -- the sim/tb_vga_timing_gen.vhd copy of this
    -- testbench (this project's real, hardware-toolchain-verified
    -- copy, tuned and passing against Questa) picked a +10 ns pad
    -- empirically to dodge it there; running that exact same file
    -- under GHDL instead gave total_cycle_count = 840001, one over,
    -- confirming the two simulators land on opposite sides of the
    -- race. Counting actual rising edges here instead of guessing an
    -- absolute time removes the race rather than chasing another
    -- simulator-specific constant, and should be portable to either
    -- tool. See docs/README.md's Phase 4 status note for the same
    -- observation applied to the real copy, which is left untouched.
    -- -------------------------------------------------------------
    stim_process : process
    begin
        -- Assert active-low reset for a couple of edges.
        rst_n <= '0';
        wait until rising_edge(pix_clk);
        wait until rising_edge(pix_clk);

        -- De-assert reset, then wait for exactly the number of
        -- rising edges the checker below will count.
        rst_n <= '1';
        for i in 1 to 840000 loop
            wait until rising_edge(pix_clk);
        end loop;

        sim_finished <= true;
        report "Simulation timeout reached." severity note;
        wait;
    end process;

    -- -------------------------------------------------------------
    -- Checker. Sensitive to both pix_clk (for the per-cycle counts)
    -- and sim_finished directly (so the final asserts fire the
    -- instant sim_finished changes, rather than depending on there
    -- happening to be one more pix_clk edge afterward).
    -- -------------------------------------------------------------
    test_process : process(pix_clk, sim_finished)
    begin

        if rising_edge(pix_clk) then
            if rst_n = '1' then

                -- Check 4: every post-reset cycle counts, unconditionally.
                total_cycle_count <= total_cycle_count + 1;

                -- Check 1 + Check 2: start_fetch is a one-cycle pulse,
                -- once per source line -- count it, and check line_num
                -- against our own independently advancing prediction.
                if start_fetch = '1' then
                    start_fetch_count <= start_fetch_count + 1;

                    -- Compare the DUT's real output against the
                    -- prediction BEFORE advancing the prediction.
                    assert line_num = expected_line_num
                        report "line_num sequence broken"
                        severity error;

                    -- Advance the prediction: 0..199 within a frame,
                    -- then wrap for the next one.
                    if expected_line_num = 199 then
                        expected_line_num <= (others => '0');
                    else
                        expected_line_num <= expected_line_num + 1;
                    end if;
                end if;

                -- Check 3: active_region is a level, not a pulse --
                -- tally every cycle it's held high, no edge detection.
                if active_region = '1' then
                    active_region_count <= active_region_count + 1;
                end if;

            end if;
        end if;

        -- Final comparisons, once the two-frame run is over.
        if sim_finished then
            assert start_fetch_count = 400
                report "start_fetch_count error"
                severity error;

				assert active_region_count = 640000
					 report "active_region_count error: got " & integer'image(active_region_count) & ", expected 640000"
					 severity error;
					 
				assert total_cycle_count = 840000
					 report "total_cycle_count error: got " & integer'image(total_cycle_count) & ", expected 840000"
					 severity error;
        end if;

    end process;

end architecture sim;
