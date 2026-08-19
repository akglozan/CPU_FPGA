-- SPDX-License-Identifier: Apache-2.0
-- Copyright 2026 Ozan Akgül

library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;
use std.textio.all;

entity tb_rv32im_soc is
end entity tb_rv32im_soc;

architecture sim of tb_rv32im_soc is

    constant CLK_PERIOD : time := 20 ns; -- 50 MHz

    signal clk         : std_logic := '0';
    signal rst_n       : std_logic := '0';
    signal uart_rx     : std_logic := '1';
    signal uart_tx     : std_logic;
    signal gpio_keys   : std_logic_vector(3 downto 0) := (others => '1');
    signal gpio_leds   : std_logic_vector(3 downto 0);

    -- SDRAM Physical Bus
    signal sdram_cke   : std_logic;
    signal sdram_cs_n  : std_logic;
    signal sdram_ras_n : std_logic;
    signal sdram_cas_n : std_logic;
    signal sdram_we_n  : std_logic;
    signal sdram_ba    : std_logic_vector(1 downto 0);
    signal sdram_addr  : std_logic_vector(11 downto 0);
    signal sdram_dqm   : std_logic_vector(1 downto 0);
    signal sdram_dq    : std_logic_vector(15 downto 0) := (others => 'Z');

begin

    -- 50 MHz Clock Generation
    clk <= not clk after CLK_PERIOD / 2;

    -- Reset Sequence
    process
    begin
        rst_n <= '0';
        wait for 100 ns;
        rst_n <= '1';
        wait;
    end process;

    -- Device Under Test (DUT)
    DUT : entity work.rv32im_soc
			generic map (
            SIMULATION => true
        )
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

    -- Behavioral SDRAM Chip Model
    U_SDRAM_CHIP : entity work.sdram_model
        port map (
            clk   => clk,
            cke   => sdram_cke,
            cs_n  => sdram_cs_n,
            ras_n => sdram_ras_n,
            cas_n => sdram_cas_n,
            we_n  => sdram_we_n,
            ba    => sdram_ba,
            addr  => sdram_addr,
            dqm   => sdram_dqm,
            dq    => sdram_dq
        );

    -- UART Output Monitor (Decodes 115200 Baud TX into text output)
    process
        constant BIT_TIME : time := 8.68 us; -- 1 / 115200
        variable char_byte : std_logic_vector(7 downto 0);
        variable l : line;
    begin
        loop
            wait until falling_edge(uart_tx); -- Start bit
            wait for BIT_TIME / 2;
            
            if uart_tx = '0' then
                wait for BIT_TIME;
                for i in 0 to 7 loop
                    char_byte(i) := uart_tx;
                    wait for BIT_TIME;
                end loop;
                
                -- Print decoded ASCII character to console
                write(l, character'val(to_integer(unsigned(char_byte))));
                if character'val(to_integer(unsigned(char_byte))) = LF then
                    writeline(output, l);
                end if;
            end if;
        end loop;
    end process;

end architecture sim;