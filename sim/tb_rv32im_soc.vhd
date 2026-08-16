library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;
use IEEE.STD_LOGIC_TEXTIO.all;
use STD.TEXTIO.all;

entity tb_rv32im_soc is
end entity tb_rv32im_soc;

architecture Behavioral of tb_rv32im_soc is

    -- Clock & Reset Signals
    signal clk       : std_logic := '0';
    signal rst_n     : std_logic := '0';
    
    -- Physical Hardware Interfaces
    signal uart_rx   : std_logic := '1';
    signal uart_tx   : std_logic;
    signal gpio_keys : std_logic_vector(3 downto 0) := "1111";
    signal gpio_leds : std_logic_vector(3 downto 0);

    -- Simulation Constants
    constant CLK_PERIOD : time := 20 ns;      -- 50 MHz Clock Period
    constant BIT_PERIOD : time := 8.68 us;    -- 115200 Baud Bit Duration

begin

    -- 1. Unit Under Test (UUT)
    UUT : entity work.rv32im_soc(Structural)
        port map (
            clk       => clk,
            rst_n     => rst_n,
            uart_rx   => uart_rx,
            gpio_keys => gpio_keys,
            uart_tx   => uart_tx,
            gpio_leds => gpio_leds
        );

    -- 2. Clock Generator Process
    clk_process : process
    begin
        clk <= '0';
        wait for CLK_PERIOD / 2;
        clk <= '1';
        wait for CLK_PERIOD / 2;
    end process;

    -- 3. Reset Sequence & Simulation Timeout Guard
    stimulus_process : process
    begin
        rst_n <= '0'; -- Ensure reset is asserted low at start
        wait for 100 ns;
        rst_n <= '1'; -- De-assert reset
        wait for 15 ms;
        report "Simulation run completed." severity note;
        wait;
    end process;

       -- 4. UART 8-N-1 Decoder / Checker
    uart_monitor_process : process
        variable rx_byte    : std_logic_vector(7 downto 0);
        variable char_line  : line;
        variable hex_line   : line;
        variable stop_bit   : std_logic;
    begin
        loop
            -- Wait for an idle-to-low transition: UART start bit.
            wait until falling_edge(uart_tx);

            -- Verify that the line remains low at the start-bit centre.
            wait for BIT_PERIOD / 2;
            assert uart_tx = '0'
                report "UART decode error: start bit is not low at its centre."
                severity error;

            -- Sample D0 through D7 in the centre of every data-bit period.
            for i in 0 to 7 loop
                wait for BIT_PERIOD;
                rx_byte(i) := uart_tx;
            end loop;

            -- Sample the stop bit.
            wait for BIT_PERIOD;
            stop_bit := uart_tx;

            assert stop_bit = '1'
                report "UART decode error: stop bit is not high."
                severity error;

            -- Human-readable transcript output.
            write(char_line, string'("UART RX: '"));

            if to_integer(unsigned(rx_byte)) >= 32 and
               to_integer(unsigned(rx_byte)) <= 126 then
                write(char_line, character'val(to_integer(unsigned(rx_byte))));
            elsif rx_byte = x"0A" then
                write(char_line, string'("\n"));
            elsif rx_byte = x"0D" then
                write(char_line, string'("\r"));
            else
                write(char_line, string'("."));
            end if;

            write(char_line, string'("'  hex=0x"));
            hwrite(char_line, rx_byte);
            writeline(output, char_line);

            -- Assert that no unknown state was sampled.
            assert not is_x(rx_byte)
                report "UART decode error: received byte contains X, U, W, or Z."
                severity error;

        end loop;
    end process;

end architecture Behavioral;