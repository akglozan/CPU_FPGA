-- Reset-stress testbench: run the real firmware, then assert rst_n at a
-- range of offsets (deliberately NOT clock-aligned, like a real button)
-- and check the SoC still blinks afterwards.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_rst is
    generic (
        n_resets   : natural := 4;
        step_ns    : natural := 137;   -- non-multiple of the 20 ns period
        settle_ns  : natural := 1500000
    );
end entity tb_rst;

architecture sim of tb_rst is

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

    signal done       : boolean := false;
    signal led_edges  : natural := 0;

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

    -- Count LED transitions; "blinking" == this keeps increasing.
    process (gpio_leds)
    begin
        if now > 1 ns then
            led_edges <= led_edges + 1;
        end if;
    end process;

    stim : process
        variable before_cnt : natural;
        variable hold       : time;
    begin
        rst_n <= '0';
        wait for 200 ns;
        rst_n <= '1';
        wait for settle_ns * 1 ns;
        report "baseline LED edges after power-on: " & integer'image(led_edges);

        for k in 1 to n_resets loop
            before_cnt := led_edges;

            -- Press: assert asynchronously at a deliberately odd offset.
            wait for (k * step_ns) * 1 ns;
            rst_n <= '0';
            hold := (500 + k * step_ns) * 1 ns;
            wait for hold;
            rst_n <= '1';

            wait for settle_ns * 1 ns;

            if led_edges = before_cnt then
                report "RESET #" & integer'image(k) &
                       " -> DEAD (no LED activity in " &
                       integer'image(settle_ns) & " ns after release), leds=" &
                       to_string(gpio_leds)
                       severity failure;
            else
                report "reset #" & integer'image(k) & " ok, edges=" &
                       integer'image(led_edges - before_cnt);
            end if;
        end loop;

        report "=== survived " & integer'image(n_resets) & " resets ===";
        done <= true;
        wait for 100 ns;
        std.env.stop;
    end process;

end architecture sim;
