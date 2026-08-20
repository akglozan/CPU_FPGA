-- SPDX-License-Identifier: Apache-2.0
-- Copyright 2026 Ozan Akgül

library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;
use STD.TEXTIO.all;

entity tb_rv32im_soc is
end entity tb_rv32im_soc;

architecture sim of tb_rv32im_soc is

    -------------------------------------------------------------------
    -- Clock & Timing Parameters
    -------------------------------------------------------------------
    constant CLK_PERIOD : time := 20 ns;   -- 50 MHz Master Clock
    constant BIT_TIME   : time := 80 ns;   -- 12.5 Mbps Accelerated Simulation Baud Rate

    -------------------------------------------------------------------
    -- Simulation Interconnect & Control Signals
    -------------------------------------------------------------------
    signal clk         : std_logic := '0';
    signal rst_n       : std_logic := '0';
    signal uart_rx     : std_logic := '1';
    signal uart_tx     : std_logic;
    signal gpio_keys   : std_logic_vector(3 downto 0) := "1111";
    signal gpio_leds   : std_logic_vector(3 downto 0);

    -------------------------------------------------------------------
    -- Physical SDRAM Bus Interface
    -------------------------------------------------------------------
    signal sdram_cke   : std_logic;
    signal sdram_cs_n  : std_logic;
    signal sdram_ras_n : std_logic;
    signal sdram_cas_n : std_logic;
    signal sdram_we_n  : std_logic;
    signal sdram_ba    : std_logic_vector(1 downto 0);
    signal sdram_addr  : std_logic_vector(11 downto 0);
    signal sdram_dqm   : std_logic_vector(1 downto 0);
    signal sdram_dq    : std_logic_vector(15 downto 0);

    signal sim_finished : boolean := false;

begin

    -------------------------------------------------------------------
    -- 1. Device Under Test (DUT) - SoC Top-Level
    -------------------------------------------------------------------
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

    -------------------------------------------------------------------
    -- 2. Behavioral SDRAM Memory Model
    -------------------------------------------------------------------
    U_SDRAM_MODEL : entity work.sdram_model
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

    -------------------------------------------------------------------
    -- 3. Clock Generation Process (50 MHz)
    -------------------------------------------------------------------
    clk_process : process
    begin
        while not sim_finished loop
            clk <= '0';
            wait for CLK_PERIOD / 2;
            clk <= '1';
            wait for CLK_PERIOD / 2;
        end loop;
        wait;
    end process;

	 -------------------------------------------------------------------
    -- Diagnostic PC Tracer
    -------------------------------------------------------------------
    pc_tracer_process : process(clk)
    begin
        if rising_edge(clk) then
            if rst_n = '1' then
                -- Report any jump backwards to 0x00000000 after boot
                if <<signal DUT.pc : std_logic_vector>> = x"00000000" then
                    report "CRITICAL: CPU Crashed and jumped to 0x00000000!" severity warning;
                end if;
            end if;
        end if;
    end process;
    -------------------------------------------------------------------
    -- 4. Reset & Interactive Key Stimulus Process
    -------------------------------------------------------------------
    stim_process : process
    begin
        -- Assert Active-Low Reset
        rst_n     <= '0';
        gpio_keys <= "1111";
        wait for 100 ns;
        
        -- Deassert Reset
        rst_n <= '1';

        -- Allow memory tests and initial boot reporting to execute
        wait for 100 us;

        -- Stimulate Key Press 0
        gpio_keys <= "1110";
        wait for 20 us;

        -- Stimulate Key Press 1
        gpio_keys <= "1101";
        wait for 20 us;

        -- Release All Keys
        gpio_keys <= "1111";

        -- Let simulation settle
        wait for 160 us;

        sim_finished <= true;
        report "Simulation completed successfully." severity note;
        wait;
    end process;

  --------------------------------------------------------------------
    -- 5. Unbuffered Diagnostic UART Monitor
    -------------------------------------------------------------------
    uart_monitor_process : process
        variable rx_byte : std_logic_vector(7 downto 0);
        variable c       : character;
        variable val     : integer;
    begin
        -- Wait for start bit falling edge
        wait until falling_edge(uart_tx);
        wait for BIT_TIME / 2; 

        if uart_tx = '0' then
            -- Sample 8 data bits (LSB first)
            for i in 0 to 7 loop
                wait for BIT_TIME;
                rx_byte(i) := uart_tx;
            end loop;

            -- Wait for stop bit
            wait for BIT_TIME;
            
            val := to_integer(unsigned(rx_byte));
            c := character'val(val);

            -- Print every byte instantly to the transcript
            if val >= 32 and val <= 126 then
                report "UART: '" & c & "'" severity note;
            elsif val = 10 then
                report "UART: [LF / Newline]" severity note;
            elsif val = 13 then
                report "UART: [CR]" severity note;
            else
                report "UART: [Raw Byte " & integer'image(val) & "]" severity note;
            end if;
        end if;
    end process;
	 
end architecture sim;