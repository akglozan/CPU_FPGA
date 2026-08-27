-- SPDX-License-Identifier: Apache-2.0
--
-- vga_palette.vhd -- 256-entry colour lookup table, mapping an 8-bit
-- framebuffer pixel (palette index) to a PALETTE_BITS-wide RGB value
-- for the board's VGA output (1 bit each of R/G/B by default -- see
-- vga_pkg.vhd).
--
-- True dual-port, dual-clock: the write side is driven directly by the
-- Wishbone slave-2 bus (sys clk, whatever rate the CPU runs at), the
-- read side by the pixel pipeline (pix_clk, 25 MHz). No CDC handshake
-- between them -- this is deliberate. A palette write landing on the
-- exact cycle a read targets the same index can make one pixel briefly
-- show the old or new colour depending on race, which is harmless and
-- self-corrects the very next frame (1/60th of a second later); adding
-- a synchronizer to avoid that would cost real complexity for a
-- one-frame cosmetic glitch that will essentially never be visible.
-- This is the same style of true-dual-port RAM Quartus already infers
-- elsewhere in this design (e.g. bram_4kb.vhd).
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.vga_pkg.all;

entity vga_palette is
    port (
        -- Write side: Wishbone slave-2 bus, sys clk domain. Word
        -- addressed (4 bytes/entry, only the low byte's low
        -- PALETTE_BITS bits are stored) so software can write a
        -- palette entry with a plain 32-bit store to
        -- VGA_PALETTE_BASE + 4*index.
        wr_clk   : in  std_logic;
        wr_en    : in  std_logic;
        wr_index : in  std_logic_vector(7 downto 0);
        wr_data  : in  std_logic_vector(PALETTE_BITS-1 downto 0);

        -- Read side: pixel pipeline, pix_clk domain. One cycle of
        -- read latency (synchronous RAM read) -- the pixel pipeline
        -- is responsible for matching that latency against hsync/
        -- vsync/blank via its own pipeline registers.
        rd_clk   : in  std_logic;
        rd_index : in  std_logic_vector(7 downto 0);
        rd_data  : out std_logic_vector(PALETTE_BITS-1 downto 0)
    );
end entity vga_palette;

architecture rtl of vga_palette is

    type palette_ram_t is array (0 to 255) of std_logic_vector(PALETTE_BITS-1 downto 0);
    signal ram : palette_ram_t := (others => (others => '0'));

begin

    process (wr_clk)
    begin
        if rising_edge(wr_clk) then
            if wr_en = '1' then
                ram(to_integer(unsigned(wr_index))) <= wr_data;
            end if;
        end if;
    end process;

    process (rd_clk)
    begin
        if rising_edge(rd_clk) then
            rd_data <= ram(to_integer(unsigned(rd_index)));
        end if;
    end process;

end architecture rtl;
