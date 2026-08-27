-- SPDX-License-Identifier: Apache-2.0
--
-- vga_pkg.vhd -- shared constants for the Phase 4.2 framebuffer/palette
-- pipeline (vga_line_fetch, vga_line_buffer, vga_palette,
-- vga_pixel_pipeline, sdram_arbiter). Centralised so the framebuffer
-- base address and dimensions are defined exactly once.
--
-- FB_BASE_ADDR -- confirmed clear of the boot payload (2026-08-26)
--
-- The last 64 KB of the 8 MB SDRAM chip (0x807F_0000 through
-- 0x807F_FFFF; the 320x200 framebuffer is 64,000 bytes, leaving 1,536
-- bytes of slack). docs/README.md's Phase 3 closeout (hardware-verified
-- 2026-08-25) documents exactly where the ESP32 loader places both boot
-- payloads: FIRMWARE.BIN at 0x8000_0000 and DOOM1.WAD (4,207,819 bytes)
-- at 0x8010_0000, ending around 0x8050_33CB. FB_BASE_ADDR sits a good
-- ~3 MB above that with room to spare, so no collision with either
-- payload. Not yet cross-checked against whatever heap/stack layout
-- Phase 5's linker script ends up using, though -- worth another look
-- once that script exists. Kept as a single constant here specifically
-- so moving it, if it ever needs to, stays cheap.
library ieee;
use ieee.std_logic_1164.all;

package vga_pkg is

    -- Source (pre-doubling) framebuffer dimensions.
    constant FB_WIDTH  : natural := 320;
    constant FB_HEIGHT : natural := 200;

    -- Byte address of pixel (0,0) within the flat 32-bit SDRAM address
    -- space (i.e. the same address space as slave 1 in
    -- bus_interconnect.vhd). One byte per pixel (8-bit palette index).
    -- See placeholder note above.
    constant FB_BASE_ADDR : std_logic_vector(31 downto 0) := x"807F0000";

    -- Palette: 256 entries, PALETTE_BITS wide. Matches this board's
    -- VGA output, which is 1 bit each of R/G/B (8 discrete colours,
    -- no resistor-ladder DAC) -- established directly against the
    -- board's schematic earlier in this project. Kept as a generic
    -- constant (rather than hardcoding "3" everywhere) so a future
    -- board revision with a real multi-bit DAC only needs this
    -- changed in one place.
    constant PALETTE_BITS : natural := 3;

end package vga_pkg;
