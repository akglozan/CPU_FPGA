library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_soc is
    generic (
        run_cycles : natural := 200000
    );
end entity tb_soc;

architecture sim of tb_soc is

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

    -- main() drives GPIO_LED = 0xF then 0x0, so a working boot produces
    -- at least two changes of the LED register after the power-on reset.
    signal led_edges : natural := 0;

begin

    clk <= not clk after 10 ns when not done else '0';   -- 50 MHz

    process
    begin
        rst_n <= '0';
        wait for 200 ns;
        wait until rising_edge(clk);
        rst_n <= '1';
        report "reset released";
        wait;
    end process;

    dut : entity work.rv32im_soc
        generic map (simulation => true)
        port map (
            clk         => clk,
            rst_n       => rst_n,
            uart_rx     => uart_rx,
            gpio_keys   => gpio_keys,
            uart_tx     => uart_tx,
            gpio_leds   => gpio_leds,
            sdram_cke   => sdram_cke,
            sdram_cs_n  => sdram_cs_n,
            sdram_ras_n => sdram_ras_n,
            sdram_cas_n => sdram_cas_n,
            sdram_we_n  => sdram_we_n,
            sdram_ba    => sdram_ba,
            sdram_addr  => sdram_addr,
            sdram_dqm   => sdram_dqm,
            sdram_dq    => sdram_dq
        );

    -- Report every LED register change.
    process (gpio_leds)
    begin
        if now > 1 ns then
            led_edges <= led_edges + 1;
        end if;
        report "LEDs -> " & to_string(gpio_leds);
    end process;

    process
    begin
        for i in 1 to run_cycles loop
            wait until rising_edge(clk);
        end loop;
        if led_edges >= 2 then
            report "=== ran " & integer'image(run_cycles) &
                   " cycles, LED register changed " &
                   integer'image(led_edges) & " times ===";
        else
            report "FAIL  LED register changed only " &
                   integer'image(led_edges) &
                   " times in " & integer'image(run_cycles) &
                   " cycles -- firmware did not reach main()"
                   severity warning;
        end if;
        done <= true;
        wait for 100 ns;
        std.env.stop;
    end process;

end architecture sim;
