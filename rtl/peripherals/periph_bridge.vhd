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
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity periph_bridge is
    port (
        -- Wishbone Slave Port
        wb_adr_i    : in  std_logic_vector(31 downto 0);
        wb_dat_i    : in  std_logic_vector(31 downto 0);
        wb_dat_o    : out std_logic_vector(31 downto 0);
        wb_we_i     : in  std_logic;
        wb_stb_i    : in  std_logic;
        wb_cyc_i    : in  std_logic;
        wb_ack_o    : out std_logic;

        -- Legacy Peripheral Signals
        uart_data   : out std_logic_vector(7 downto 0);
        uart_we     : out std_logic;
        uart_rdata  : in  std_logic_vector(31 downto 0);

        gpio_we     : out std_logic;
        gpio_rdata  : in  std_logic_vector(31 downto 0);

        timer_we    : out std_logic;
        timer_rdata : in  std_logic_vector(31 downto 0)
    );
end entity periph_bridge;

architecture rtl of periph_bridge is
    signal is_active : std_logic;
begin
    is_active <= wb_stb_i and wb_cyc_i;
    
    -- 0-cycle combinatorial ACK for low-speed peripherals
    wb_ack_o  <= is_active;

    uart_data <= wb_dat_i(7 downto 0);

    process(is_active, wb_adr_i, wb_we_i, uart_rdata, gpio_rdata, timer_rdata)
    begin
        uart_we   <= '0';
        gpio_we   <= '0';
        timer_we  <= '0';
        wb_dat_o  <= (others => '0');

        if is_active = '1' then
            case wb_adr_i(7 downto 0) is
                -- 0xE000_0000 : UART TX Data
                when x"00" =>
                    uart_we  <= wb_we_i;
                    wb_dat_o <= (others => '0');

                -- 0xE000_0004 : UART Status
                when x"04" =>
                    wb_dat_o <= uart_rdata;

                -- 0xE000_0010 : GPIO
                when x"10" =>
                    gpio_we  <= wb_we_i;
                    wb_dat_o <= gpio_rdata;

                -- 0xE000_0020 : Hardware Cycle Timer
                when x"20" =>
                    timer_we <= wb_we_i;
                    wb_dat_o <= timer_rdata;

                when others =>
                    wb_dat_o <= (others => '0');
            end case;
        end if;
    end process;

end architecture rtl;