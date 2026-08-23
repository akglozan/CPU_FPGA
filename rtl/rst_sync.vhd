-- SPDX-License-Identifier: Apache-2.0
--
-- rst_sync.vhd -- reset synchronizer and debouncer.
--
-- Purpose: rst_n on this board comes straight from a raw mechanical
-- pushbutton with no debounce circuitry, and rv32im_soc.vhd fans that
-- signal out to every register in the design (CPU pipeline, bus, all
-- peripherals). This block turns that raw, bouncy, asynchronous pin
-- into a single clean reset pulse that changes only in response to a
-- clock edge.
--
-- WHY THIS IS NOT AN ASYNC-ASSERT / SYNC-RELEASE SYNCHRONIZER
--
-- The previous version was the textbook async-assert / sync-release
-- pattern: rst_n_sync dropped combinationally the instant the pin went
-- low, and only the RELEASE was registered. That pattern is correct --
-- but only for consumers that use an ASYNCHRONOUS reset, i.e. flops
-- declared as "process (clk, rst_n) ... if rst_n = '0' then".
--
-- Every register in this design uses a SYNCHRONOUS reset instead:
--
--     process (clk)
--     begin
--         if rising_edge(clk) then
--             if rst_n = '0' then ...
--
-- For those flops rst_n_sync is not a reset pin at all -- it is an
-- ordinary DATA input, sampled at the clock edge like any other, and
-- it must therefore meet setup and hold. An asynchronously-asserted
-- rst_n_sync does not: it changes at whatever instant the button
-- happens to bounce, which lands inside the setup/hold window of some
-- clock edge on a random fraction of presses. When that happens,
-- different flops on this high-fanout net capture DIFFERENT values on
-- the same edge -- some reset, some not.
--
-- That is not theoretical here, and it has a specific fatal outcome.
-- In EX_MEM_Register, if the mem_addr flops capture the reset (going
-- to 0x00000000, which bus_interconnect decodes as slave_bram) while
-- the mem_write flop misses it and stays '1', then bram_web goes
-- active and the BRAM writes mem_write_data into WORD 0 -- clobbering
-- "auipc sp,0x1", the first instruction of crt0. The M9K's own wren_b
-- register has no reset at all; it simply samples whatever bram_web is
-- at that edge.
--
-- The damage then survives every subsequent reset, because BRAM
-- contents are only restored by reconfiguring the FPGA. With word 0
-- gone, sp is never initialized: sp = 0, "addi sp,sp,-16" gives
-- 0xFFFFFFF0, every stack access lands in the unmapped range where
-- bus_interconnect's slave_none acks with data 0, so "lw a5,12(sp)"
-- always reads 0, "bgeu a4,a5" is always true, and main() spins
-- forever in the inner delay loop with the LEDs stuck on. Verified in
-- simulation: clobbering word 0 reproduces exactly that behaviour.
--
-- The fix is to remove the asynchronous path entirely. rst_n_sync is
-- now driven by an ordinary flop, so it changes only just after a
-- clock edge and every downstream synchronous-reset flop gets a full
-- clock period of setup. The reset net also becomes a normal
-- register-to-register path that the Timing Analyzer actually
-- constrains, instead of an unconstrained asynchronous input.
--
-- Losing the async assert costs nothing here: no consumer uses an
-- asynchronous reset, and the 50 MHz clock is a free-running
-- oscillator that is always present.
--
-- DEBOUNCE / STRETCH
--
-- The counter holds reset asserted until rst_n_async has been
-- continuously high for 2**stretch_bits clock cycles (~1.3 ms at
-- 50 MHz with the default 16). Any low sample restarts it, so an
-- entire bounce burst -- press and release -- collapses into one clean
-- reset pulse with exactly one release edge, instead of the dozens of
-- partial restarts a raw button produces.
--
-- All state powers up at '0', so FPGA configuration is followed by a
-- clean ~1.3 ms power-on reset before the CPU is released.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity rst_sync is
    generic (
        -- Reset is held until the pin has been stable high for
        -- 2**stretch_bits clocks. 16 => ~1.3 ms at 50 MHz.
        stretch_bits : natural := 16
    );
    port (
        clk         : in  std_logic;
        rst_n_async : in  std_logic;  -- raw external pin, may bounce/glitch
        rst_n_sync  : out std_logic   -- clean, fully synchronous reset
    );
end entity rst_sync;

architecture rtl of rst_sync is

    -- Two-flop synchronizer for the raw pin. meta_ff is the only flop
    -- allowed to go metastable; sync_ff is clean.
    signal meta_ff : std_logic := '0';
    signal sync_ff : std_logic := '0';

    signal count   : unsigned(stretch_bits - 1 downto 0) := (others => '0');
    signal rst_n_q : std_logic := '0';

begin

    process (clk)
    begin
        if rising_edge(clk) then
            meta_ff <= rst_n_async;
            sync_ff <= meta_ff;

            if sync_ff = '0' then
                -- Button down (or bouncing low): re-arm.
                count   <= (others => '0');
                rst_n_q <= '0';
            elsif count /= (count'range => '1') then
                -- Stable high, but not yet long enough.
                count   <= count + 1;
                rst_n_q <= '0';
            else
                -- Stable high for the full stretch interval.
                rst_n_q <= '1';
            end if;
        end if;
    end process;

    rst_n_sync <= rst_n_q;

end architecture rtl;
