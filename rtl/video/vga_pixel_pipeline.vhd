-- SPDX-License-Identifier: Apache-2.0
--
-- vga_pixel_pipeline.vhd -- final Phase 4.2 stage: for every pix_clk
-- cycle in the visible/letterboxed region, turns the current pixel_x
-- into a framebuffer column (halved, for 2x horizontal doubling), reads
-- the palette index for that column out of vga_line_buffer, looks up
-- its RGB value in vga_palette, and drives the board's physical VGA
-- pins. Outside the letterboxed active area, RGB is forced to black
-- (all-zero) rather than showing whatever the line buffer/palette
-- happen to hold.
--
-- PIPELINE LATENCY: vga_line_buffer's read and vga_palette's read are
-- each one synchronous cycle (see their own headers). Chained
-- back-to-back that's 2 cycles from pixel_x to the resulting RGB value,
-- so hsync/vsync/display_en are carried through a matching 2-stage
-- shift register below -- without that, the sync signals would lead
-- the pixel data they're supposed to line up with by 2 pix_clk cycles
-- (80 ns at 25 MHz), visibly shifting the image.
--
-- BANK SELECTION: write_bank_i comes from vga_line_fetch in the sys
-- clk domain. It's synchronized here with a plain 2-flop synchronizer
-- (safe: it changes at most once per ~1600-cycle scanline period, see
-- vga_line_fetch.vhd's header for the same reasoning applied the other
-- direction). This module always reads the bank vga_line_fetch is NOT
-- currently writing.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.vga_pkg.all;

entity vga_pixel_pipeline is
    port (
        pix_clk   : in  std_logic;
        pix_rst_n : in  std_logic;

        -- From vga_timing_gen.
        hsync_i         : in  std_logic;
        vsync_i         : in  std_logic;
        hblank_i        : in  std_logic;
        active_region_i : in  std_logic;
        pixel_x_i       : in  unsigned(9 downto 0);

        -- From vga_line_fetch, sys clk domain (synchronized inside).
        write_bank_i : in std_logic;

        -- To vga_line_buffer's read port.
        buf_rd_bank : out std_logic;
        buf_rd_col  : out unsigned(8 downto 0);
        buf_rd_data : in  std_logic_vector(7 downto 0);

        -- To vga_palette's read port.
        pal_rd_index : out std_logic_vector(7 downto 0);
        pal_rd_data  : in  std_logic_vector(PALETTE_BITS-1 downto 0);

        -- Physical VGA pins.
        vga_hsync : out std_logic;
        vga_vsync : out std_logic;
        vga_r     : out std_logic;
        vga_g     : out std_logic;
        vga_b     : out std_logic
    );
end entity vga_pixel_pipeline;

architecture rtl of vga_pixel_pipeline is

    signal write_bank_sync : std_logic_vector(1 downto 0) := (others => '0');
    signal read_bank       : std_logic;

    signal display_en : std_logic;  -- active_region and not hblank

    -- 2-stage matched-latency delay for the sync/blank signals.
    type delay2_t is array (1 downto 0) of std_logic;
    signal hsync_d, vsync_d, display_en_d : delay2_t := (others => '0');

begin

    -- Synchronize write_bank_i into pix_clk domain; read the opposite
    -- bank from the one currently (or about to be) written.
    process (pix_clk)
    begin
        if rising_edge(pix_clk) then
            if pix_rst_n = '0' then
                write_bank_sync <= (others => '0');
            else
                write_bank_sync <= write_bank_sync(0) & write_bank_i;
            end if;
        end if;
    end process;

    read_bank <= not write_bank_sync(1);

    display_en <= active_region_i and (not hblank_i);

    buf_rd_bank <= read_bank;
    buf_rd_col  <= pixel_x_i(9 downto 1);  -- /2: 320-wide source, 640-wide output
    pal_rd_index <= buf_rd_data;

    process (pix_clk)
    begin
        if rising_edge(pix_clk) then
            if pix_rst_n = '0' then
                hsync_d       <= (others => '0');
                vsync_d       <= (others => '0');
                display_en_d  <= (others => '0');
            else
                hsync_d      <= hsync_d(0)      & hsync_i;
                vsync_d      <= vsync_d(0)      & vsync_i;
                display_en_d <= display_en_d(0) & display_en;
            end if;
        end if;
    end process;

    vga_hsync <= hsync_d(1);
    vga_vsync <= vsync_d(1);

    -- Force black outside the letterboxed active area; PALETTE_BITS is
    -- fixed at 3 (1 bit each of R/G/B) for this board -- see vga_pkg.vhd.
    vga_r <= pal_rd_data(2) when display_en_d(1) = '1' else '0';
    vga_g <= pal_rd_data(1) when display_en_d(1) = '1' else '0';
    vga_b <= pal_rd_data(0) when display_en_d(1) = '1' else '0';

end architecture rtl;
