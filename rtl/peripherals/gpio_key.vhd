-- SPDX-License-Identifier: Apache-2.0
-- Copyright 2026 Ozan Akgül
--
-- Licensed under the Apache License, Version 2.0 (the "License");
-- you may not use this file except in compliance with the License.
-- You may obtain a copy of the License at
--
--     http://www.apache.org/licenses/LICENSE-2.0
--
-- Unless required by applicable law or agreed to in writing, software
-- distributed under the License is distributed on an "AS IS" BASIS,
-- WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
-- See the License for the specific language governing permissions and
-- limitations under the License.

library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;

-- 4-button GPIO input peripheral. Double-flops the raw asynchronous key
-- inputs onto the system clock (a standard 2-stage synchronizer) to
-- avoid metastability, then debounces each line independently before
-- exposing the result zero-extended to a 32-bit MMIO read word.
--
-- Debounce added 2026-08-28: main.c's gpio_key_test() (Phase 6.1
-- bring-up) confirmed all four buttons work end to end once it polled
-- fast enough to catch a quick tap, but the synchronizer alone passes
-- raw mechanical contact bounce straight through -- every physical
-- press/release can chatter across the debounced-vs-not boundary for a
-- few milliseconds, which would register as several presses instead of
-- one to anything actually using the buttons for input (Doom, eventually).
-- The synchronizer stays for metastability; this only additionally
-- requires the synchronized value to be stable for DEBOUNCE_CYCLES
-- straight cycles before key_rdata accepts the change, same "counter
-- races a threshold, resets on any wobble" shape as the other debounce
-- functions in this project (see rv32im_soc.vhd's
-- get_boot_done_debounce/get_rst_stretch_bits) and the same
-- simulation/hardware split, so GHDL doesn't need to simulate a real
-- ~10ms settle time to prove the mechanism.
entity gpio_key is

	generic (
		-- When true, selects a debounce window short enough for GHDL to
		-- simulate quickly while still exercising the real logic (see
		-- get_key_debounce_cycles below). Real hardware always leaves
		-- this at its default.
		simulation : boolean := false
	);

	port(
		clk 	:	in std_logic;
		-- Active-low synchronous reset.
		rst_n	:	in std_logic;
		-- Raw, asynchronous button inputs.
		key_in:	in std_logic_vector(3 downto 0);

		-- Debounced, synchronized key state, zero-extended to 32 bits.
		key_rdata	: out std_logic_vector(31 downto 0)


	);
end entity;


architecture Behavioral of gpio_key is

	-- ~10ms at 50MHz for real hardware -- comfortably longer than
	-- typical tactile-switch bounce (usually settled within a few ms),
	-- short enough that even a deliberately quick tap (well over 10ms
	-- for a human finger) is still caught. Fast_simulation only needs
	-- enough cycles to prove a bouncing input gets rejected and a
	-- stable one gets accepted -- not to model real switch physics.
	function get_key_debounce_cycles(
		fast_simulation : boolean
	) return natural is
	begin
		if fast_simulation then
			return 15;
		else
			return 499999;
		end if;
	end function;

	constant DEBOUNCE_CYCLES : natural := get_key_debounce_cycles(simulation);

	signal key_sync1	: std_logic_vector(3 downto 0);
	signal key_sync2	: std_logic_vector(3 downto 0);
	signal key_debounced	: std_logic_vector(3 downto 0);

	type debounce_counter_array is
		array (0 to 3) of natural range 0 to DEBOUNCE_CYCLES;
	signal debounce_cnt : debounce_counter_array;

begin

process(clk)

begin

	if rising_edge(clk) then
		if rst_n = '0' then
			key_sync1 <= (others => '0');--da vedere i valori rispetto ai pulsanti
			key_sync2 <= (others => '0');
			key_debounced <= (others => '0');
			debounce_cnt <= (others => 0);
		else
			key_sync1 <= key_in;
			key_sync2 <= key_sync1;

			-- Per-bit debounce: while a synchronized input disagrees
			-- with the currently-accepted (debounced) value, count
			-- consecutive cycles of that disagreement. Any cycle where
			-- it matches again (a real value settling back, or bounce
			-- flipping the other way) resets the count to zero, so only
			-- a change that holds steady for the full window ever gets
			-- accepted -- exactly what rejects contact bounce.
			for i in 0 to 3 loop
				if key_sync2(i) /= key_debounced(i) then
					if debounce_cnt(i) = DEBOUNCE_CYCLES then
						key_debounced(i) <= key_sync2(i);
						debounce_cnt(i)  <= 0;
					else
						debounce_cnt(i) <= debounce_cnt(i) + 1;
					end if;
				else
					debounce_cnt(i) <= 0;
				end if;
			end loop;
		end if;
	end if;


end process;

key_rdata <= (31 downto 4 => '0') & key_debounced;

end architecture Behavioral;
