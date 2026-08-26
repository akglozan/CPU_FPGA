-------------------------------------------------------------------------------
-- vga_timing_gen.vhd
--
-- Phase 4.1 -- VGA timing generator.
--
-- Generates standard 640x480 @ 60 Hz VESA timing from a 25 MHz pixel
-- clock (nominal -- the real VESA spec calls for 25.175 MHz; a 25 MHz
-- ALTPLL output is close enough that essentially all monitors sync to
-- it without issue, same assumption docs/README.md's Phase 4.1 task
-- already makes).
--
-- Also derives, from the same hcnt/vcnt counters, the mapping from
-- 480 physical output lines down to a 320x200 source framebuffer:
--   - 400 of the 480 visible lines show the doubled 200-line source
--     image (2 output lines per source line), centered with a 40-line
--     black letterbox top and bottom (480 - 400 = 80, split evenly).
--   - line_num/start_fetch expose that mapping to the (not yet built)
--     vga_line_fetch module, which bursts one source scanline out of
--     SDRAM into an on-chip line buffer per start_fetch pulse.
--
-- Design notes (see docs/README.md Phase 4 section for the full
-- writeup of the arbitration/line-buffer approach this feeds into):
--   - Every output is registered, one clock behind hcnt/vcnt. Only
--     hcnt/vcnt are explicitly reset; the rest are pure functions of
--     hcnt/vcnt and are deliberately left un-reset (Option B, decided
--     2026-08-25) -- they settle to correct values one cycle after
--     hcnt/vcnt do, which is fine since nothing downstream depends on
--     a defined value during the reset window itself, and it avoids
--     duplicating 9 reset-value assignments that would otherwise need
--     to be kept in sync with the constants below by hand.
--   - start_fetch is a single pix_clk-domain pulse. Whatever consumes
--     it (vga_line_fetch, on the system clock) needs its own 2-3 stage
--     synchronizer for this signal, same pattern already used for
--     spi_sclk/spi_mosi/spi_cs_n/boot_done in the boot-link RTL --
--     this module does not attempt that crossing itself.
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity vga_timing_gen is
    port (
        pix_clk        : in  std_logic;   -- 25 MHz pixel clock domain
        rst_n          : in  std_logic;

        hsync          : out std_logic;   -- active-low (VESA 640x480@60)
        vsync          : out std_logic;   -- active-low

        hblank         : out std_logic;   -- '0' while hcnt < H_VISIBLE
        vblank         : out std_logic;   -- '0' while vcnt < V_VISIBLE
        active_region  : out std_logic;   -- '1' while vcnt in the centered
                                           -- 400-line (letterboxed) window

        pixel_x        : out unsigned(9 downto 0);  -- 0..639 valid, else in hblank
        pixel_y        : out unsigned(9 downto 0);  -- 0..479 valid, else in vblank

        line_num       : out unsigned(7 downto 0);  -- 0..199, valid when active_region='1'
        start_fetch    : out std_logic               -- 1-cycle pulse, pix_clk domain,
                                                       -- once per SOURCE line (not per
                                                       -- doubled output line)
    );
end entity vga_timing_gen;

architecture rtl of vga_timing_gen is

    -- ---------------------------------------------------------------
    -- 640x480 @ 60 Hz VESA horizontal/vertical timing constants.
    -- ---------------------------------------------------------------
    constant H_VISIBLE : natural := 640;
    constant H_FRONT   : natural := 16;
    constant H_SYNC    : natural := 96;
    constant H_BACK    : natural := 48;
    constant H_TOTAL   : natural := H_VISIBLE + H_FRONT + H_SYNC + H_BACK; -- 800

    constant V_VISIBLE : natural := 480;
    constant V_FRONT   : natural := 10;
    constant V_SYNC    : natural := 2;
    constant V_BACK    : natural := 33;
    constant V_TOTAL   : natural := V_VISIBLE + V_FRONT + V_SYNC + V_BACK; -- 525

    -- 200 source lines doubled = 400 output lines, centered in 480:
    -- (480 - 400) / 2 = 40 blank lines top and bottom.
    constant LETTERBOX_TOP : natural := 40;
    constant LETTERBOX_BOT : natural := 440; -- LETTERBOX_TOP + 400

    -- ---------------------------------------------------------------
    -- Internal counters. Sized for 0..H_TOTAL-1 (799) / 0..V_TOTAL-1
    -- (524) -- both fit in 10 bits.
    -- ---------------------------------------------------------------
    signal hcnt : unsigned(9 downto 0) := (others => '0');
    signal vcnt : unsigned(9 downto 0) := (others => '0');

begin

    -- -----------------------------------------------------------------
    -- All timing/output logic in one clocked process (all of it is
    -- driven off the same pix_clk edge, so splitting it across several
    -- processes bought no simulation-semantics benefit -- see
    -- docs/README.md Phase 4 notes for the reasoning). Only the
    -- hcnt/vcnt reset is explicit; see the file header for why the
    -- rest is deliberately left un-reset (Option B).
    -- -----------------------------------------------------------------
    process(pix_clk)
        -- vy_off: "vertical y offset" -- vcnt - LETTERBOX_TOP, named so
        -- it can be indexed (see line_num/start_fetch below). Declared
        -- as a variable, not a signal: variables update immediately
        -- within a process, so vy_off reflects THIS cycle's vcnt when
        -- read further down, rather than lagging a cycle behind the
        -- way a signal assigned with <= would.
        variable vy_off : unsigned(9 downto 0);
    begin

        if rising_edge(pix_clk) then

            -- --------------------------------------------------------
            -- Horizontal / vertical counters.
            -- hcnt: 0..H_TOTAL-1 (800), wraps every line.
            -- vcnt: 0..V_TOTAL-1 (525), wraps every frame, advanced
            --       only on the cycle hcnt wraps.
            -- --------------------------------------------------------
            if rst_n = '0' then
                hcnt <= (others => '0');
                vcnt <= (others => '0');
            else
                hcnt <= hcnt + 1;

                if hcnt = H_TOTAL-1 then
                    hcnt <= (others => '0');
                    vcnt <= vcnt + 1;

                    if vcnt = V_TOTAL-1 then
                        vcnt <= (others => '0');
                    end if;
                end if;
            end if;

            -- --------------------------------------------------------
            -- Sync pulses. VESA 640x480@60 polarity: active-low.
            -- --------------------------------------------------------
            if hcnt >= (H_VISIBLE+H_FRONT) and hcnt < (H_VISIBLE+H_FRONT+H_SYNC) then
                hsync <= '0';
            else
                hsync <= '1';
            end if;

            if vcnt >= (V_VISIBLE+V_FRONT) and vcnt < (V_VISIBLE+V_FRONT+V_SYNC) then
                vsync <= '0';
            else
                vsync <= '1';
            end if;

            -- --------------------------------------------------------
            -- Blanking. '0' = in the visible region, '1' = blanked.
            -- --------------------------------------------------------
            if hcnt < H_VISIBLE then
                hblank <= '0';
            else
                hblank <= '1';
            end if;

            if vcnt < V_VISIBLE then
                vblank <= '0';
            else
                vblank <= '1';
            end if;

            -- --------------------------------------------------------
            -- Pixel coordinates -- direct pass-through of hcnt/vcnt,
            -- registered to stay aligned with hsync/hblank above (same
            -- one-cycle lag applied uniformly across every output).
            -- --------------------------------------------------------
            pixel_x <= hcnt;
            pixel_y <= vcnt;

            -- --------------------------------------------------------
            -- Letterbox / source-line mapping.
            --
            -- line_num = (vcnt - LETTERBOX_TOP) >> 1, via bit slice
            -- (8 downto 1) of the 9-bit difference (0..399) -- drops
            -- bit 0 (the remainder/evenness bit), keeps bits 8..1,
            -- giving exactly the 8 bits needed for 0..199. No resize
            -- or concatenation needed.
            --
            -- start_fetch pulses once per SOURCE line (not per output
            -- line): only on the first of each doubled pair (bit 0 of
            -- the difference = '0'), at hcnt = H_VISIBLE (start of
            -- front porch) -- giving vga_line_fetch the full blanking
            -- interval plus most of the next line as slack before the
            -- fetched data is needed (see docs/README.md Phase 4 for
            -- the full timing-budget writeup: an ~80-word SDRAM burst
            -- fits comfortably inside one ~31.5 us line period).
            -- Recomputes the raw range/parity check directly rather
            -- than reading the registered active_region signal, since
            -- a same-process, same-edge read of active_region would
            -- see its pre-this-edge (stale) value, not the value being
            -- computed this cycle.
            -- --------------------------------------------------------
            vy_off := vcnt - LETTERBOX_TOP;

            if vcnt >= LETTERBOX_TOP and vcnt < LETTERBOX_BOT then
                active_region <= '1';
                line_num <= vy_off(8 downto 1);
            else
                active_region <= '0';
            end if;

            if vcnt >= LETTERBOX_TOP and vcnt < LETTERBOX_BOT
               and vy_off(0) = '0'
               and hcnt = H_VISIBLE then
                start_fetch <= '1';
            else
                start_fetch <= '0';
            end if;

        end if;

    end process;

end architecture rtl;
