-- SPDX-License-Identifier: Apache-2.0
--
-- vga_line_buffer.vhd -- ping-pong (double-buffered) scanline store.
-- Two 320-byte banks so vga_line_fetch can be filling one bank from
-- SDRAM while vga_pixel_pipeline reads the other bank for display --
-- without that, a fetch landing mid-scanline would tear the row
-- currently on screen.
--
-- Simple dual port, dual clock: written by vga_line_fetch in the sys
-- clk domain, read by vga_pixel_pipeline in the pix_clk domain, one
-- cycle of read latency. wr_bank and rd_bank are expected to always
-- point at opposite banks; that invariant is enforced by the caller
-- (vga_pixel_pipeline drives rd_bank from a synchronized copy of the
-- bank vga_line_fetch is NOT currently writing -- see
-- vga_pixel_pipeline.vhd), not by this module.
--
-- WHY altsyncram IS INSTANTIATED DIRECTLY HERE, rather than written as
-- an inferred array like vga_palette.vhd's:
--
-- This module was originally a plain `array` signal with one clocked
-- write process and one clocked read process -- the same shape as
-- vga_palette.vhd, which Quartus infers correctly into a single M9K
-- block (0 ALUTs, 768 memory bits, confirmed in the RAM Summary table
-- of output_files/CPU_FPGA.map.rpt). Here, inference failed instead,
-- and the array became 640 discrete byte registers plus thousands of
-- ALUTs of read/write multiplexing -- 4112 combinational ALUTs against
-- a whole-device budget of 6272, which by itself made the design
-- unfittable (Error (170011): 9017 blocks needed, 6272 available).
--
-- Four separate source forms were tried, and every one produced
-- Info (276007): RAM logic "vga_line_buffer:u_vga_line_buffer|ram" is
-- uninferred due to asynchronous read logic -- despite the array only
-- ever being read inside "if rising_edge(rd_clk)":
--
--   1. two ram(...) references picked by if/else on the bank bit;
--   2. one ram(addr) reference, addr a process-local variable assigned
--      by that same if/else;
--   3. one ram(addr) reference, addr a signal driven by a separate
--      concurrent "addr <= bank & col" outside the clocked processes
--      (this one also widened the array 640 -> 1024 so the bank bit
--      could be the plain MSB; it made things worse, 11434 ALUTs);
--   4. the concatenation moved inline into the ram(...) index itself,
--      i.e. textually as close to vga_palette's shape as the extra
--      bank bit allows.
--
-- At that point the remaining difference from the working example is
-- not something the source can express away: vga_palette's index is a
-- plain port fed straight into to_integer(unsigned(...)), and this
-- module's cannot be, because the address is inherently bank & column.
-- Guessing at further syntactic variants costs a full Quartus compile
-- per attempt and had already failed four times.
--
-- So this follows the precedent bram_4kb.vhd set in Phase 2, for
-- exactly the same class of problem -- see its header, which records a
-- different inference misfire (a 32-bit memory silently split into
-- eight 8-bit primitives, none of which kept the .mif) resolved the
-- same way. Instantiating the primitive removes the ambiguity rather
-- than negotiating with it: the mapping is now stated, not inferred,
-- and cannot silently regress into logic again if a later edit or a
-- different Quartus version shifts what the template matcher accepts.
--
-- Parameters below mirror what Quartus itself chose for the palette's
-- successfully inferred instance (report section "Parameter Settings
-- for Inferred Entity Instance: vga_palette:u_vga_palette|altsyncram"),
-- with the widths changed: OPERATION_MODE DUAL_PORT, port B's address
-- register on CLOCK1, OUTDATA_REG_B UNREGISTERED. That combination is
-- what makes q_b appear exactly one rd_clk after the address -- the
-- same one-cycle latency the array version had, so
-- vga_pixel_pipeline.vhd's latency matching is unchanged.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.vga_pkg.all;

library altera_mf;
use altera_mf.altera_mf_components.all;

entity vga_line_buffer is
    port (
        -- Write side: vga_line_fetch, sys clk domain.
        wr_clk  : in  std_logic;
        wr_en   : in  std_logic;
        wr_bank : in  std_logic;
        wr_col  : in  unsigned(8 downto 0);  -- 0..319
        wr_data : in  std_logic_vector(7 downto 0);

        -- Read side: vga_pixel_pipeline, pix_clk domain. One cycle of
        -- read latency.
        rd_clk  : in  std_logic;
        rd_bank : in  std_logic;
        rd_col  : in  unsigned(8 downto 0);  -- 0..319
        rd_data : out std_logic_vector(7 downto 0)
    );
end entity vga_line_buffer;

architecture rtl of vga_line_buffer is

    -- 10-bit address: bank in the MSB, column in the low 9 bits. Bank 0
    -- occupies 0..319 and bank 1 occupies 512..831, with the gaps either
    -- side simply unused -- nothing outside this module assumes any
    -- particular numeric relationship between the two banks' addresses,
    -- and a power-of-2 depth is the natural fit for one M9K
    -- (1024 x 8 = 8192 bits, inside a single block's 9216).
    signal wr_addr : std_logic_vector(9 downto 0);
    signal rd_addr : std_logic_vector(9 downto 0);

begin

    wr_addr <= wr_bank & std_logic_vector(wr_col);
    rd_addr <= rd_bank & std_logic_vector(rd_col);

    u_altsyncram : altsyncram
        generic map (
            operation_mode         => "DUAL_PORT",
            intended_device_family => "Cyclone IV E",

            -- Port A: write-only, sys clk (clock0).
            width_a    => 8,
            widthad_a  => 10,
            numwords_a => 1024,

            -- Port B: read-only, pix_clk (clock1). Address registered
            -- on clock1, output NOT separately registered -- one cycle
            -- of latency total, matching the behavioural array this
            -- replaced. A second output register here would put
            -- rd_data two cycles behind rd_col and shift every pixel
            -- one position right on screen, the same class of mistake
            -- bram_4kb.vhd's header documents for the CPU's ports.
            width_b       => 8,
            widthad_b     => 10,
            numwords_b    => 1024,
            address_reg_b => "CLOCK1",
            outdata_reg_b => "UNREGISTERED",

            -- The two ports are in unrelated clock domains and the
            -- caller guarantees they never address the same bank, so
            -- there is no meaningful read-during-write case to define.
            read_during_write_mode_mixed_ports => "DONT_CARE"
        )
        port map (
            -- Write side.
            clock0    => wr_clk,
            address_a => wr_addr,
            data_a    => wr_data,
            wren_a    => wr_en,
            q_a       => open,

            -- Read side.
            clock1    => rd_clk,
            address_b => rd_addr,
            data_b    => (others => '0'),
            wren_b    => '0',
            q_b       => rd_data
        );

end architecture rtl;
