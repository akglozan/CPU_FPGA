-- SPDX-License-Identifier: Apache-2.0
-- Copyright 2026 Ozan Akgül

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity periph_bridge is
    port (
        -- Wishbone B4 slave interface
        wb_addr_i : in  std_logic_vector(31 downto 0);
        wb_data_i : in  std_logic_vector(31 downto 0);
        wb_data_o : out std_logic_vector(31 downto 0);
        wb_sel_i  : in  std_logic_vector(3 downto 0);
        wb_we_i   : in  std_logic;
        wb_stb_i  : in  std_logic;
        wb_cyc_i  : in  std_logic;
        wb_ack_o  : out std_logic;

        -- UART interface
        uart_tx_data  : out std_logic_vector(7 downto 0);
        uart_tx_start : out std_logic;
        uart_status   : in  std_logic_vector(31 downto 0);

        -- GPIO interface
        gpio_led_we   : out std_logic;
        gpio_key_data : in  std_logic_vector(31 downto 0);

        -- Timer interface
        timer_data : in std_logic_vector(31 downto 0)
    );
end entity periph_bridge;

architecture rtl of periph_bridge is

    signal bus_active : std_logic;

begin

    bus_active <= wb_cyc_i and wb_stb_i;

    --------------------------------------------------------------------
    -- Wishbone acknowledgement
    --
    -- The peripheral bridge responds in one cycle to every active
    -- transaction. Unmapped reads return zero and unmapped writes are
    -- ignored, but neither can lock the CPU.
    --------------------------------------------------------------------
    wb_ack_o <= bus_active;

    --------------------------------------------------------------------
    -- Write strobes and UART data
    --
    -- Register offsets:
    --   0x00 : GPIO LED write
    --   0x08 : UART TX write
    --------------------------------------------------------------------
    process (
        wb_addr_i,
        wb_data_i,
        wb_sel_i,
        wb_we_i,
        bus_active
    )
    begin
        uart_tx_data  <= wb_data_i(7 downto 0);
        uart_tx_start <= '0';
        gpio_led_we   <= '0';

        if bus_active = '1' and wb_we_i = '1' then
            case wb_addr_i(7 downto 0) is

                when x"00" =>
                    if wb_sel_i /= "0000" then
                        gpio_led_we <= '1';
                    end if;

                when x"08" =>
                    if wb_sel_i /= "0000" then
                        uart_tx_start <= '1';
                    end if;

                when others =>
                    null;

            end case;
        end if;
    end process;

    --------------------------------------------------------------------
    -- Read-data multiplexer
    --
    -- Register offsets:
    --   0x04 : GPIO keys
    --   0x0C : UART status
    --   0x10 : timer
    --
    -- All unimplemented registers read as zero.
    --------------------------------------------------------------------
    process (
        wb_addr_i,
        gpio_key_data,
        uart_status,
        timer_data
    )
    begin
        wb_data_o <= (others => '0');

        case wb_addr_i(7 downto 0) is

            when x"04" =>
                wb_data_o <= gpio_key_data;

            when x"0C" =>
                wb_data_o <= uart_status;

            when x"10" =>
                wb_data_o <= timer_data;

            when others =>
                wb_data_o <= (others => '0');

        end case;
    end process;

end architecture rtl;