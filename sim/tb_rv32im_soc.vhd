library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;
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
        rst_n <= '0';
        wait for 100 ns;
        rst_n <= '1';
        
        -- Run for 2 ms to allow C firmware execution and UART output
        wait for 2 ms;
        report "Simulation run completed." severity note;
        wait;
    end process;

    -- 4. Behavioral UART Terminal Console Output
    uart_monitor_process : process
        variable rx_byte : std_logic_vector(7 downto 0);
        variable l       : line;
    begin
        loop
            -- Wait for UART Start Bit (Falling Edge)
            wait until falling_edge(uart_tx);
            wait for BIT_PERIOD / 2; -- Align sample point to center of start bit
            
            -- Sample 8 Data Bits (LSB First)
            for i in 0 to 7 loop
                wait for BIT_PERIOD;
                rx_byte(i) := uart_tx;
            end loop;
            
            -- Wait for Stop Bit
            wait for BIT_PERIOD;
            
            -- Print decoded ASCII character to ModelSim transcript window
            write(l, character'val(to_integer(unsigned(rx_byte))));
            writeline(output, l);
        end loop;
    end process;

end architecture Behavioral;