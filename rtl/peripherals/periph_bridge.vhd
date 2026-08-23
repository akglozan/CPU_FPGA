library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Wishbone B4 slave bridging the system bus to the individual MMIO
-- peripherals (LED at offset 0x00, key input at 0x04, UART TX/busy at
-- 0x08/0x0C, timer at 0x10). Every access acknowledges combinationally
-- in the same cycle it is presented (single-cycle peripheral latency),
-- unlike the multi-cycle SDRAM slave.
entity periph_bridge is
    port (
        wb_addr_i : in  std_logic_vector(31 downto 0);
        -- Write data; low byte is also routed directly to uart_tx_data.
        wb_data_i : in  std_logic_vector(31 downto 0);
        -- Read data muxed from the selected peripheral.
        wb_data_o : out std_logic_vector(31 downto 0);
        wb_sel_i  : in  std_logic_vector(3 downto 0);
        wb_we_i   : in  std_logic;
        wb_stb_i  : in  std_logic;
        wb_cyc_i  : in  std_logic;
        -- Combinational single-cycle acknowledge.
        wb_ack_o  : out std_logic;

        -- Byte to transmit, driven straight from wb_data_i(7 downto 0).
        uart_tx_data  : out std_logic_vector(7 downto 0);
        -- Pulsed for one cycle on a write to offset 0x08.
        uart_tx_start : out std_logic;
        -- UART busy/status word, read at offset 0x0C.
        uart_status   : in  std_logic_vector(31 downto 0);

        -- Pulsed for one cycle on a write to offset 0x00.
        gpio_led_we   : out std_logic;
        -- Synchronized key input word, read at offset 0x04.
        gpio_key_data : in  std_logic_vector(31 downto 0);

        -- Free-running counter value, read at offset 0x10.
        timer_data : in std_logic_vector(31 downto 0)
    );
end entity periph_bridge;

architecture rtl of periph_bridge is
    signal bus_active : std_logic;
begin

    bus_active <= wb_cyc_i and wb_stb_i;

    -- One-cycle response for every peripheral access.
    wb_ack_o <= bus_active;

    uart_tx_data <= wb_data_i(7 downto 0);

    process (
        wb_addr_i,
        wb_sel_i,
        wb_we_i,
        bus_active
    )
    begin
        uart_tx_start <= '0';
        gpio_led_we   <= '0';

        if bus_active = '1' and wb_we_i = '1'
           and wb_sel_i /= "0000" then

            case wb_addr_i(7 downto 0) is
                when x"00" =>
                    gpio_led_we <= '1';

                when x"08" =>
                    uart_tx_start <= '1';

                when others =>
                    null;
            end case;
        end if;
    end process;

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