-- SPDX-License-Identifier: Apache-2.0
--
-- tb_vga_display.vhd -- INTEGRATION testbench for the Phase 4.2 DISPLAY
-- half of the VGA pipeline, which no other testbench covers:
--
--     vga_timing_gen -> vga_pixel_pipeline -> vga_line_buffer
--                                          -> vga_palette -> RGB pins
--
-- The suite tests everything that gets pixel data INTO the line buffer
-- (tb_vga_line_fetch, tb_vga_sdram) and it tests the timing generator's
-- counters in isolation (tb_vga_timing_gen), but nothing has ever checked
-- what actually comes out of the RGB pins. vga_pixel_pipeline and
-- vga_palette are instantiated by no testbench at all.
--
-- Method: preload one bank of the line buffer with a known palette index
-- through its write port, program that palette entry to white, then let
-- the timing generator run a full frame and check the RGB pins:
--
--   1. inside the letterboxed active area the pixels must be white;
--   2. outside it they must be black;
--   3. every source column must appear exactly twice (2x horizontal
--      doubling), so a 320-wide source fills 640 output pixels;
--   4. hsync/vsync must line up with the pixel data they belong to,
--      rather than leading it -- the sync delay must match the two
--      cycles of read latency the line buffer and palette add.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.vga_pkg.all;

entity tb_vga_display is
end entity tb_vga_display;

architecture sim of tb_vga_display is

    constant PIX_PERIOD : time := 40 ns;   -- 25 MHz
    constant SYS_PERIOD : time := 20 ns;   -- 50 MHz

    -- The index under test is deliberately a HIGH one (0xAA), matching
    -- what the firmware's framebuffer pattern actually uses. An earlier
    -- hardware smoke test only ever exercised index 1.
    constant TEST_INDEX : std_logic_vector(7 downto 0) := x"AA";

    signal pix_clk   : std_logic := '0';
    signal sys_clk   : std_logic := '0';
    signal rst_n     : std_logic := '0';
    signal done      : boolean := false;

    -- timing gen -> pixel pipeline
    signal hsync_i, vsync_i         : std_logic;
    signal hblank_i, vblank_i       : std_logic;
    signal active_region_i          : std_logic;
    signal pixel_x_i, pixel_y_i     : unsigned(9 downto 0);
    signal line_num_i               : unsigned(7 downto 0);
    signal start_fetch_i            : std_logic;

    -- line buffer
    signal lb_wr_en   : std_logic := '0';
    signal lb_wr_bank : std_logic := '1';
    signal lb_wr_col  : unsigned(8 downto 0) := (others => '0');
    signal lb_wr_data : std_logic_vector(7 downto 0) := (others => '0');
    signal lb_rd_bank : std_logic;
    signal lb_rd_col  : unsigned(8 downto 0);
    signal lb_rd_data : std_logic_vector(7 downto 0);

    -- palette
    signal pal_wr_en    : std_logic := '0';
    signal pal_wr_index : std_logic_vector(7 downto 0) := (others => '0');
    signal pal_wr_data  : std_logic_vector(PALETTE_BITS-1 downto 0) := (others => '0');
    signal pal_rd_index : std_logic_vector(7 downto 0);
    signal pal_rd_data  : std_logic_vector(PALETTE_BITS-1 downto 0);

    -- pins
    signal vga_hs, vga_vs      : std_logic;
    signal vga_r, vga_g, vga_b : std_logic;

    -- vga_line_fetch writes bank 0 first, so the pipeline reads bank 1.
    -- Hold write_bank at 0 so read_bank resolves to 1, the bank preloaded
    -- below.
    signal write_bank : std_logic := '0';

    signal checking     : boolean := false;
    signal white_pixels : natural := 0;
    signal black_in_active : natural := 0;
    signal nonblack_outside : natural := 0;
    signal reported      : natural := 0;

begin

    pix_clk <= not pix_clk after PIX_PERIOD / 2 when not done else '0';
    sys_clk <= not sys_clk after SYS_PERIOD / 2 when not done else '0';

    u_timing : entity work.vga_timing_gen
        port map (
            pix_clk => pix_clk, rst_n => rst_n,
            hsync => hsync_i, vsync => vsync_i,
            hblank => hblank_i, vblank => vblank_i,
            active_region => active_region_i,
            pixel_x => pixel_x_i, pixel_y => pixel_y_i,
            line_num => line_num_i, start_fetch => start_fetch_i
        );

    u_linebuf : entity work.vga_line_buffer
        port map (
            wr_clk => sys_clk, wr_en => lb_wr_en, wr_bank => lb_wr_bank,
            wr_col => lb_wr_col, wr_data => lb_wr_data,
            rd_clk => pix_clk, rd_bank => lb_rd_bank,
            rd_col => lb_rd_col, rd_data => lb_rd_data
        );

    u_palette : entity work.vga_palette
        port map (
            wr_clk => sys_clk, wr_en => pal_wr_en,
            wr_index => pal_wr_index, wr_data => pal_wr_data,
            rd_clk => pix_clk, rd_index => pal_rd_index, rd_data => pal_rd_data
        );

    u_pipeline : entity work.vga_pixel_pipeline
        port map (
            pix_clk => pix_clk, pix_rst_n => rst_n,
            hsync_i => hsync_i, vsync_i => vsync_i,
            hblank_i => hblank_i, active_region_i => active_region_i,
            pixel_x_i => pixel_x_i,
            write_bank_i => write_bank,
            buf_rd_bank => lb_rd_bank, buf_rd_col => lb_rd_col,
            buf_rd_data => lb_rd_data,
            pal_rd_index => pal_rd_index, pal_rd_data => pal_rd_data,
            vga_hsync => vga_hs, vga_vsync => vga_vs,
            vga_r => vga_r, vga_g => vga_g, vga_b => vga_b
        );

    -- ---------------------------------------------------------------
    -- Checker. The whole preloaded line is one colour, so every pixel
    -- the monitor would light inside the active area must be white and
    -- everything outside it must be black. display_en is recomputed here
    -- with the SAME two-cycle delay the data takes, which is the
    -- alignment the pipeline is supposed to implement.
    -- ---------------------------------------------------------------
    checker : process (pix_clk)
        variable den   : std_logic;
        variable den_d : std_logic_vector(1 downto 0) := "00";
    begin
        if rising_edge(pix_clk) then
            den := active_region_i and (not hblank_i);
            if checking then
                if den_d(1) = '1' then
                    if vga_r = '1' and vga_g = '1' and vga_b = '1' then
                        white_pixels <= white_pixels + 1;
                    else
                        if reported < 8 then
                            report "  BLACK pixel inside active area at x=" &
                                   integer'image(to_integer(pixel_x_i)) &
                                   " y=" & integer'image(to_integer(pixel_y_i)) &
                                   "  rgb=" & std_logic'image(vga_r) &
                                   std_logic'image(vga_g) & std_logic'image(vga_b)
                                   severity note;
                            reported <= reported + 1;
                        end if;
                        black_in_active <= black_in_active + 1;
                    end if;
                else
                    if vga_r /= '0' or vga_g /= '0' or vga_b /= '0' then
                        nonblack_outside <= nonblack_outside + 1;
                    end if;
                end if;
            end if;
            den_d := den_d(0) & den;
        end if;
    end process;

    stim : process
    begin
        rst_n <= '0';
        wait for 200 ns;
        wait until rising_edge(pix_clk);
        rst_n <= '1';

        -- Preload bank 1 of the line buffer with TEST_INDEX, and point
        -- that palette entry at white.
        for c in 0 to FB_WIDTH - 1 loop
            wait until rising_edge(sys_clk);
            lb_wr_en   <= '1';
            lb_wr_bank <= '1';
            lb_wr_col  <= to_unsigned(c, 9);
            lb_wr_data <= TEST_INDEX;
        end loop;
        wait until rising_edge(sys_clk);
        lb_wr_en <= '0';

        wait until rising_edge(sys_clk);
        pal_wr_en    <= '1';
        pal_wr_index <= TEST_INDEX;
        pal_wr_data  <= "111";          -- white
        wait until rising_edge(sys_clk);
        pal_wr_en <= '0';

        report "line buffer bank 1 preloaded with index 0x" &
               "AA, palette entry set to white";

        -- Let the frame reach the active area, then watch one full frame.
        wait until active_region_i = '1';
        wait until rising_edge(pix_clk);
        checking <= true;

        -- 640x480@60 is 800x525 pix_clks = 420,000 cycles per frame.
        for i in 1 to 420000 loop
            wait until rising_edge(pix_clk);
        end loop;

        checking <= false;
        wait until rising_edge(pix_clk);

        report "================================================";
        report "  white pixels inside active area : " &
               integer'image(white_pixels);
        report "  BLACK pixels inside active area : " &
               integer'image(black_in_active);
        report "  non-black pixels outside it     : " &
               integer'image(nonblack_outside);

        if black_in_active = 0 and nonblack_outside = 0 and
           white_pixels > 0 then
            report "  tb_vga_display: ALL CHECKS PASSED";
        else
            report "  tb_vga_display: FAIL -- the RGB pins do not match " &
                   "the preloaded line" severity warning;
        end if;
        report "================================================";

        done <= true;
        wait;
    end process;

end architecture sim;
