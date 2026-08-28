-- Unit test for gpio_key's debounce logic (added 2026-08-28 alongside
-- the debounce itself -- see rtl/peripherals/gpio_key.vhd's header for
-- the bring-up story: main.c's gpio_key_test() proved the raw
-- synchronizer path works end to end on real hardware, but a bare
-- synchronizer passes mechanical contact bounce straight through, which
-- would register as multiple presses to anything actually consuming
-- the buttons as input.
--
-- Instantiates gpio_key directly (not the whole SoC) with
-- generic simulation => true, which shrinks DEBOUNCE_CYCLES from the
-- real ~10ms (499999 cycles @ 50MHz) down to 15 -- enough to prove the
-- counter-races-a-threshold mechanism without GHDL having to simulate
-- a real debounce window cycle by cycle.
--
-- Three things checked:
--   1. A bouncing input (toggling every cycle) never reaches key_rdata
--      at all while the bounce continues.
--   2. Once an input holds steady, key_rdata eventually settles to it
--      -- but not suspiciously early (proving the delay is real, not
--      an accidental pass-through).
--   3. Two bits debounce independently: bouncing one must not disturb
--      an already-settled, unrelated bit.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_gpio_key is
end entity tb_gpio_key;

architecture sim of tb_gpio_key is

    signal clk       : std_logic := '0';
    signal rst_n     : std_logic := '0';
    signal key_in    : std_logic_vector(3 downto 0) := (others => '0');
    signal key_rdata : std_logic_vector(31 downto 0);

    signal done  : boolean := false;
    signal fails : natural := 0;

begin

    clk <= not clk after 10 ns when not done else '0';

    dut : entity work.gpio_key
        generic map (simulation => true)
        port map (
            clk => clk, rst_n => rst_n,
            key_in => key_in, key_rdata => key_rdata
        );

    stim : process
        procedure step (n : natural := 1) is
        begin
            for i in 1 to n loop
                wait until rising_edge(clk);
            end loop;
            wait for 1 ns;
        end procedure;

        procedure check (
            name : string;
            got, expect : std_logic
        ) is
        begin
            if got = expect then
                report "PASS  " & name;
            else
                fails <= fails + 1;
                report "FAIL  " & name & "  got " & std_logic'image(got) &
                       " expected " & std_logic'image(expect)
                       severity warning;
            end if;
        end procedure;
    begin
        rst_n <= '0';
        step(4);
        rst_n <= '1';
        step(4);

        check("all bits idle low after reset", key_rdata(0), '0');

        report "--- bit0: bouncing input must never reach key_rdata ---";
        -- Toggle every single cycle -- as hostile a bounce as possible,
        -- far faster than any real switch, for DEBOUNCE_CYCLES-worth of
        -- cycles. debounce_cnt keeps getting reset by the very next
        -- disagreement/agreement flip, so it should never reach the
        -- 15-cycle threshold.
        for i in 1 to 20 loop
            key_in(0) <= not key_in(0);
            step(1);
            check("key_rdata(0) unchanged during bounce, cycle " &
                  integer'image(i), key_rdata(0), '0');
        end loop;

        report "--- bit0: settling to '1' cleanly must eventually latch ---";
        key_in(0) <= '1';
        -- Too early: synchronizer (2 cycles) alone can't have cleared
        -- the debounce threshold (15 more) yet.
        step(5);
        check("key_rdata(0) still 0 shortly after settle begins",
              key_rdata(0), '0');

        -- Comfortably past sync (2) + DEBOUNCE_CYCLES (15): give it a
        -- healthy margin rather than an exact cycle count, since this
        -- test only needs to prove debounce happens, not its precise
        -- latency.
        step(25);
        check("key_rdata(0) latched high once settled", key_rdata(0), '1');

        report "--- bit1: bouncing must not disturb bit0's settled state ---";
        for i in 1 to 20 loop
            key_in(1) <= not key_in(1);
            step(1);
            check("key_rdata(0) still 1 while bit1 bounces, cycle " &
                  integer'image(i), key_rdata(0), '1');
            check("key_rdata(1) unchanged during its own bounce, cycle " &
                  integer'image(i), key_rdata(1), '0');
        end loop;

        report "--- bit0: clean release back to '0' must also latch ---";
        key_in(0) <= '0';
        step(5);
        check("key_rdata(0) still 1 shortly after release begins",
              key_rdata(0), '1');
        step(25);
        check("key_rdata(0) latched low once released", key_rdata(0), '0');

        report "--- upper bits of key_rdata always zero-extended ---";
        check("key_rdata(31) is 0", key_rdata(31), '0');
        check("key_rdata(4) is 0", key_rdata(4), '0');

        report "================ FAILURES: " & integer'image(fails) &
               " ================";
        done <= true;
        wait for 100 ns;
        std.env.stop;
    end process;

end architecture sim;
