-- Decodes whatever the SoC actually drives on uart_tx at 115200 8N1.
-- Uses simulation => false so the real baud divider is exercised.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_uart is
    -- Long enough to clear the real (simulation => false) power-on path
    -- before a single byte can appear: rst_sync's 2**16-cycle debounce
    -- stretch is ~1.31 ms and the boot_done debounce is another ~1.31 ms,
    -- so the CPU does not execute its first instruction until ~2.62 ms.
    -- The five bytes then take 5 * 10 bits / 115200 = ~434 us. At the old
    -- 2000 us this testbench could never have passed -- it ended before
    -- the CPU had started.
    generic ( run_us : natural := 4000 );
end entity tb_uart;

architecture sim of tb_uart is

    constant bit_time : time := 8680 ns;   -- 115200 baud

    signal clk       : std_logic := '0';
    signal rst_n     : std_logic := '0';
    signal uart_rx   : std_logic := '1';
    signal gpio_keys : std_logic_vector(3 downto 0) := (others => '1');
    signal uart_tx   : std_logic;
    signal gpio_leds : std_logic_vector(3 downto 0);

    signal sdram_cke   : std_logic;
    signal sdram_cs_n  : std_logic;
    signal sdram_ras_n : std_logic;
    signal sdram_cas_n : std_logic;
    signal sdram_we_n  : std_logic;
    signal sdram_ba    : std_logic_vector(1 downto 0);
    signal sdram_addr  : std_logic_vector(11 downto 0);
    signal sdram_dqm   : std_logic_vector(1 downto 0);
    signal sdram_dq    : std_logic_vector(15 downto 0) := (others => 'Z');

    signal done : boolean := false;

    -- Expected output of main(): uart_putc('A','B','C','\r','\n').
    type byte_seq is array (natural range <>) of integer;
    constant expected : byte_seq := (65, 66, 67, 13, 10);

    signal rx_count : natural := 0;
    signal rx_bad   : natural := 0;

begin

    clk <= not clk after 10 ns when not done else '0';

    process
    begin
        rst_n <= '0';
        wait for 300 ns;
        rst_n <= '1';
        wait;
    end process;

    dut : entity work.rv32im_soc
        generic map (simulation => false)          -- real 115200 divider
        port map (
            -- Tied high: these testbenches don't model the ESP32 SPI
            -- transfer, so "the boot loader has already finished" is the
            -- correct precondition for what they actually test. Without
            -- this the port defaults to '0', boot_done_latched never
            -- sets, cpu_rst_n never releases and the CPU runs no
            -- instructions at all -- which is why this testbench used to
            -- report a dead SoC.
            boot_done => '1',
            clk => clk, rst_n => rst_n, uart_rx => uart_rx,
            gpio_keys => gpio_keys, uart_tx => uart_tx, gpio_leds => gpio_leds,
            sdram_cke => sdram_cke, sdram_cs_n => sdram_cs_n,
            sdram_ras_n => sdram_ras_n, sdram_cas_n => sdram_cas_n,
            sdram_we_n => sdram_we_n, sdram_ba => sdram_ba,
            sdram_addr => sdram_addr, sdram_dqm => sdram_dqm,
            sdram_dq => sdram_dq
        );

    -- Plain 8N1 receiver on the pin.
    rx : process
        variable b  : std_logic_vector(7 downto 0);
        variable v  : integer;
        variable pc : character;
    begin
        loop
            wait until falling_edge(uart_tx);
            wait for bit_time / 2;
            if uart_tx = '0' then                 -- valid start bit
                for i in 0 to 7 loop
                    wait for bit_time;
                    b(i) := uart_tx;
                end loop;
                wait for bit_time;
                v := to_integer(unsigned(b));
                if rx_count < expected'length then
                    if v /= expected(rx_count) then
                        rx_bad <= rx_bad + 1;
                        report "FAIL  byte " & integer'image(rx_count) &
                               " is " & integer'image(v) &
                               ", expected " & integer'image(expected(rx_count))
                               severity warning;
                    end if;
                end if;
                -- Bytes past the greeting are the rest of the firmware's
                -- boot log (FW[0], WAD[0], BUS_ERR, the VGA smoke test
                -- and readback). They used to be counted as failures,
                -- back when main() printed nothing else. Their framing is
                -- still checked by the stop-bit test below -- which is
                -- what this testbench is really for, since it is the only
                -- one running the real 115200 divider.
                if uart_tx /= '1' then
                    rx_bad <= rx_bad + 1;
                    report "FAIL  missing stop bit" severity warning;
                end if;
                rx_count <= rx_count + 1;
                if v >= 32 and v < 127 then
                    pc := character'val(v);
                else
                    pc := '.';
                end if;
                report "UART byte: " & integer'image(v) &
                       "  char='" & pc &
                       "'  stop=" & std_logic'image(uart_tx) &
                       "  @ " & time'image(now);
            end if;
        end loop;
    end process;

    process (gpio_leds)
    begin
        report "LEDs -> " & to_string(gpio_leds) & " @ " & time'image(now);
    end process;

    process
    begin
        wait for run_us * 1 us;
        if rx_count >= expected'length and rx_bad = 0 then
            report "=== end of run: greeting correct, " &
                   integer'image(rx_count) &
                   " well-framed bytes received in total ===";
        else
            report "FAIL  received " & integer'image(rx_count) &
                   " bytes (need at least " &
                   integer'image(expected'length) & "), " &
                   integer'image(rx_bad) & " bad"
                   severity warning;
        end if;
        done <= true;
        wait for 100 ns;
        std.env.stop;
    end process;

end architecture sim;
