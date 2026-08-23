-- SPDX-License-Identifier: Apache-2.0
--
-- rst_sync.vhd -- reset synchronizer.
--
-- Purpose: rst_n on this board comes straight from a raw mechanical
-- pushbutton with no debounce circuitry, and rv32im_soc.vhd currently
-- fans that raw signal out directly to every register in the design
-- (CPU pipeline, bus, BRAM, all peripherals). Mechanical switches
-- bounce on release -- the signal chatters between high and low
-- several times over a few milliseconds before settling -- and with
-- no synchronization, different flip-flops scattered across the die
-- (different routing delays) can end up sampling that bounce at
-- slightly different effective moments. That leaves the pipeline in
-- an inconsistent state from one reset press to the next, which
-- matches exactly what was observed on hardware: cpu_debug_top5
-- produced a different LED pattern on nearly every single reset
-- press with the identical bitstream still programmed -- a hardware
-- race, not a logic bug (logic is deterministic; only physical
-- timing varies press to press).
--
-- This is a standard async-assert / sync-release reset synchronizer:
--   - Reset ASSERTS immediately and asynchronously the instant
--     rst_n_async goes low (any bounce toward '0' safely re-arms it;
--     asserting reset an extra time or two never causes harm).
--   - Reset only DEASSERTS (rst_n_sync goes high) after rst_n_async
--     has been continuously high for 2 full clock cycles, cleanly
--     registered. Every register in the design that uses rst_n_sync
--     instead of the raw pin now sees the exact same single,
--     glitch-free release edge, in lockstep with the clock --
--     regardless of how many times the button bounced beforehand.
--     Only the LAST bounce matters; the synchronizer just waits it
--     out.
--
-- This does not fix bounce at the source -- it makes bounce
-- irrelevant, by guaranteeing every consumer of reset agrees on
-- exactly when it ended.

library ieee;
use ieee.std_logic_1164.all;

entity rst_sync is
    port (
        clk         : in  std_logic;
        rst_n_async : in  std_logic;  -- raw external pin, may bounce/glitch
        rst_n_sync  : out std_logic   -- clean, synchronized release
    );
end entity rst_sync;

architecture rtl of rst_sync is
    -- 2-flip-flop synchronizer chain. Reset (both flops to '0') is
    -- asynchronous on rst_n_async; release is synchronous, so
    -- rst_n_sync only ever changes right at a clock edge.
    signal sync_ff : std_logic_vector(1 downto 0) := "00";
begin

    process (clk, rst_n_async)
    begin
        if rst_n_async = '0' then
            sync_ff <= "00";
        elsif rising_edge(clk) then
            sync_ff <= sync_ff(0) & '1';
        end if;
    end process;

    rst_n_sync <= sync_ff(1);

end architecture rtl;
