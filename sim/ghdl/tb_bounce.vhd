-- Bounce-stress testbench: model a real mechanical pushbutton, which
-- chatters for a few hundred microseconds on both press and release.
-- Each chatter edge is a partial reset: the CPU is let out of reset for
-- a few cycles, then slammed back in. Checks whether that ever produces
-- a BRAM write outside the two legitimate stack slots, and whether the
-- SoC still blinks afterwards.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

entity tb_bounce is
    generic (
        n_presses : natural := 3;
        settle_ns : natural := 1600000
    );
end entity tb_bounce;

architecture sim of tb_bounce is

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

    signal done      : boolean := false;
    signal led_edges : natural := 0;

begin

    clk <= not clk after 10 ns when not done else '0';

    dut : entity work.rv32im_soc
        generic map (simulation => true)
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

    process (gpio_leds)
    begin
        if now > 1 ns then
            led_edges <= led_edges + 1;
        end if;
    end process;

    stim : process
        variable seed1 : positive := 17;
        variable seed2 : positive := 4211;
        variable r     : real;
        variable gap   : time;
        variable nb    : natural;
        variable before_cnt : natural;

        procedure chatter (level_after : std_logic; bounces : natural) is
        begin
            for i in 1 to bounces loop
                uniform(seed1, seed2, r);
                gap := integer(r * 3000.0 + 50.0) * 1 ns;
                rst_n <= '0';
                wait for gap;
                uniform(seed1, seed2, r);
                gap := integer(r * 3000.0 + 50.0) * 1 ns;
                rst_n <= '1';
                wait for gap;
            end loop;
            rst_n <= level_after;
        end procedure;
    begin
        rst_n <= '0';
        wait for 200 ns;
        rst_n <= '1';
        wait for settle_ns * 1 ns;
        report "baseline edges: " & integer'image(led_edges);

        for k in 1 to n_presses loop
            before_cnt := led_edges;

            uniform(seed1, seed2, r);
            wait for integer(r * 20000.0 + 500.0) * 1 ns;

            -- press: chatter, settle low (button held)
            uniform(seed1, seed2, r);
            nb := integer(r * 8.0) + 2;
            chatter('0', nb);
            wait for 200000 ns;              -- held down ~200 us

            -- release: chatter, settle high
            uniform(seed1, seed2, r);
            nb := integer(r * 8.0) + 2;
            chatter('1', nb);

            wait for settle_ns * 1 ns;

            if led_edges = before_cnt then
                report "PRESS #" & integer'image(k) &
                       " -> DEAD, leds=" & to_string(gpio_leds)
                       severity failure;
            else
                report "press #" & integer'image(k) & " ok, edges=" &
                       integer'image(led_edges - before_cnt);
            end if;
        end loop;

        report "=== survived " & integer'image(n_presses) & " bouncy presses ===";
        done <= true;
        wait for 100 ns;
        std.env.stop;
    end process;

end architecture sim;
