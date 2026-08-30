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

-- UART transmitter: 8 data bits, no parity, 1 stop bit, driven by a
-- 4-state FSM (IDLE -> START -> DATA -> STOP) with a per-bit clock
-- divider derived from CLK_FREQ / BAUD_RATE. tx_start latches tx_data
-- and begins transmission; tx_busy stays asserted for the whole frame.
entity uart_tx is
    generic (
        -- System clock frequency in Hz, used to derive the per-bit
        -- clock divider (CLKS_PER_BIT).
        CLK_FREQ  : positive := 50000000;
        -- Target UART baud rate.
        BAUD_RATE : positive := 115200
    );
    port (
        clk      : in  std_logic;
        -- Active-low synchronous reset.
        rst_n    : in  std_logic;
        -- Byte to transmit; latched when tx_start is asserted in IDLE.
        tx_data  : in  std_logic_vector(7 downto 0);
        -- Pulse to begin transmitting tx_data; ignored while busy.
        tx_start : in  std_logic;
        -- Asserted for the duration of a frame (start/data/stop bits).
        tx_busy  : out std_logic;
        -- Serial output line (idles high).
        tx_out   : out std_logic
    );
end entity uart_tx;

architecture rtl of uart_tx is

    -- 50 MHz / 115200 = 434 clocks per UART bit.
    constant CLKS_PER_BIT : positive := CLK_FREQ / BAUD_RATE;

    type state_t is (
        STATE_IDLE,
        STATE_START,
        STATE_DATA,
        STATE_STOP
    );

    signal state     : state_t := STATE_IDLE;
    signal clk_count : natural range 0 to CLKS_PER_BIT - 1 := 0;
    signal bit_index : natural range 0 to 7 := 0;
    signal tx_shift  : std_logic_vector(7 downto 0) := (others => '0');
    signal tx_reg    : std_logic := '1';
    signal busy_reg  : std_logic := '0';
    signal tx_start_prev : std_logic := '0';

begin

    assert CLK_FREQ >= BAUD_RATE
        report "uart_tx: CLK_FREQ must be greater than or equal to BAUD_RATE"
        severity failure;

    tx_out  <= tx_reg;
    tx_busy <= busy_reg;

    process (clk)
    begin
        if rising_edge(clk) then
            if rst_n = '0' then
                state     <= STATE_IDLE;
                clk_count <= 0;
                bit_index <= 0;
                tx_shift  <= (others => '0');
                tx_reg    <= '1';
                busy_reg  <= '0';
                tx_start_prev <= '0';

            else
                 tx_start_prev <= '0';

                -- pragma translate_off
                if tx_start = '1' then
                    report "uart_tx: tx_start seen, state=" & state_t'image(state) &
                           " busy_reg=" & std_logic'image(busy_reg) &
                           " tx_data=" & to_hstring(tx_data) &
                           " @ " & time'image(now);
                end if;
                -- pragma translate_on
                case state is

                    when STATE_IDLE =>
                        tx_reg    <= '1';
                        clk_count <= 0;
                        bit_index <= 0;
                        busy_reg  <= '0';

                        if tx_start = '1' and tx_start_prev = '0' then
                            tx_shift  <= tx_data;
                            tx_reg    <= '0';
                            busy_reg  <= '1';
                            state     <= STATE_START;
                            -- pragma translate_off
                            report "uart_tx: ACCEPT -> STATE_START, latching tx_data=" &
                                   to_hstring(tx_data) & " @ " & time'image(now);
                            -- pragma translate_on
                        end if;

                    when STATE_START =>
                        tx_reg   <= '0';
                        busy_reg <= '1';

                        if clk_count = CLKS_PER_BIT - 1 then
                            clk_count <= 0;
                            bit_index <= 0;
                            state     <= STATE_DATA;
                        else
                            clk_count <= clk_count + 1;
                        end if;

                    when STATE_DATA =>
                        tx_reg   <= tx_shift(bit_index);
                        busy_reg <= '1';

                        if clk_count = CLKS_PER_BIT - 1 then
                            clk_count <= 0;

                            if bit_index = 7 then
                                bit_index <= 0;
                                state     <= STATE_STOP;
                            else
                                bit_index <= bit_index + 1;
                            end if;
                        else
                            clk_count <= clk_count + 1;
                        end if;

                    when STATE_STOP =>
                        tx_reg   <= '1';
                        busy_reg <= '1';

                        if clk_count = CLKS_PER_BIT - 1 then
                            clk_count <= 0;
                            busy_reg  <= '0';
                            state     <= STATE_IDLE;
                            -- pragma translate_off
                            report "uart_tx: STOP done -> STATE_IDLE, busy_reg -> 0 @ " &
                                   time'image(now);
                            -- pragma translate_on
                        else
                            clk_count <= clk_count + 1;
                        end if;

                end case;
            end if;
        end if;
    end process;

end architecture rtl;