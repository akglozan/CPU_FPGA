library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Wishbone B4 slave bridging the system bus to the individual MMIO
-- peripherals (LED at offset 0x00, key input at 0x04, UART TX/busy at
-- 0x08/0x0C, timer at 0x10, bus-error flag at 0x14). Every access
-- acknowledges combinationally in the same cycle it is presented
-- (single-cycle peripheral latency), unlike the multi-cycle SDRAM slave.
entity periph_bridge is
    port (

        clk       : in  std_logic;
        rst_n     : in  std_logic;

        wb_addr_i : in  std_logic_vector(31 downto 0);
        -- Write data.
        wb_data_i : in  std_logic_vector(31 downto 0);
        -- Read data muxed from the selected peripheral.
        wb_data_o : out std_logic_vector(31 downto 0);
        wb_sel_i  : in  std_logic_vector(3 downto 0);
        wb_we_i   : in  std_logic;
        wb_stb_i  : in  std_logic;
        wb_cyc_i  : in  std_logic;
        -- Combinational single-cycle acknowledge.
        wb_ack_o  : out std_logic;

        -- Byte to transmit, latched from wb_data_i(7 downto 0) in the same
        -- cycle uart_tx_start pulses (see the write process below --
        -- wb_data_i is not held stable one cycle later, when the pulse
        -- actually reaches uart_tx).
        uart_tx_data  : out std_logic_vector(7 downto 0);
        -- Pulsed for one cycle on a write to offset 0x08.
        uart_tx_start : out std_logic;
        -- UART busy/status word, read at offset 0x0C.
        uart_status   : in  std_logic_vector(31 downto 0);

        -- Pulsed for one cycle on a write to offset 0x00.
        gpio_led_we   : out std_logic;
        -- Write data latched alongside gpio_led_we, for the same reason
        -- uart_tx_data is latched rather than left tied to wb_data_i: by
        -- the time gpio_led samples gpio_led_we (itself a registered,
        -- one-cycle-delayed pulse), wb_data_i may already reflect a
        -- later, unrelated bus transaction.
        gpio_led_data : out std_logic_vector(31 downto 0);
        -- Synchronized key input word, read at offset 0x04.
        gpio_key_data : in  std_logic_vector(31 downto 0);

        -- Free-running counter value, read at offset 0x10.
        timer_data : in std_logic_vector(31 downto 0);

        -- Sticky bus-timeout flag from bus_interconnect, read at offset
        -- 0x14 in bit 0. Set when a slave failed to acknowledge and the
        -- watchdog had to synthesise an ack; any read that returned zero
        -- while this is set should be treated as invalid.
        bus_error  : in std_logic
    );
end entity periph_bridge;

architecture rtl of periph_bridge is
    signal bus_active : std_logic;
begin

    bus_active <= wb_cyc_i and wb_stb_i;

    -- One-cycle response for every peripheral access.
    wb_ack_o <= bus_active;

    

process (clk)
    begin
        if rising_edge(clk) then
            if rst_n = '0' then
                uart_tx_start <= '0';
                uart_tx_data  <= (others => '0');
                gpio_led_we   <= '0';
                gpio_led_data <= (others => '0');
            else
                uart_tx_start <= '0';
                gpio_led_we   <= '0';

                if bus_active = '1' and wb_we_i = '1' and wb_sel_i /= "0000" then
                    case wb_addr_i(7 downto 0) is
                        when x"00" =>
                            gpio_led_data <= wb_data_i; -- LATCH DATA WITH WE
                            gpio_led_we   <= '1';
                        when x"08" =>
                            uart_tx_data  <= wb_data_i(7 downto 0); -- LATCH DATA WITH START
                            uart_tx_start <= '1';
                        when others =>
                            null;
                    end case;
                end if;
            end if;
        end if;
    end process;

    process (
        wb_addr_i,
        gpio_key_data,
        uart_status,
        timer_data,
        bus_error
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

            when x"14" =>
                wb_data_o <= (0 => bus_error, others => '0');

            when others =>
                wb_data_o <= (others => '0');
        end case;
    end process;

end architecture rtl;