-- SPDX-License-Identifier: Apache-2.0
-- Copyright 2026 Ozan Akgül

library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;

entity rv32im_soc is
	generic (
        SIMULATION : boolean := false
    );
    port (
        -- Clock and System Controls
        clk         : in    std_logic;
        rst_n       : in    std_logic;
        
        -- Physical Board Peripherals
        uart_rx     : in    std_logic;
        gpio_keys   : in    std_logic_vector(3 downto 0);
        uart_tx     : out   std_logic;
        gpio_leds   : out   std_logic_vector(3 downto 0);

        -- External SDRAM Chip Pins
        sdram_cke   : out   std_logic;
        sdram_cs_n  : out   std_logic;
        sdram_ras_n : out   std_logic;
        sdram_cas_n : out   std_logic;
        sdram_we_n  : out   std_logic;
        sdram_ba    : out   std_logic_vector(1 downto 0);
        sdram_addr  : out   std_logic_vector(11 downto 0);
        sdram_dqm   : out   std_logic_vector(1 downto 0);
        sdram_dq    : inout std_logic_vector(15 downto 0)
    );
end entity rv32im_soc;

architecture Structural of rv32im_soc is

    -- Instruction Fetch Bus (CPU IF <-> BRAM Port A)
    signal pc          : std_logic_vector(31 downto 0);
    signal instr       : std_logic_vector(31 downto 0);

    -- Wishbone Master Bus (CPU MEM -> Interconnect)
    signal wb_cpu_adr  : std_logic_vector(31 downto 0);
    signal wb_cpu_wdat : std_logic_vector(31 downto 0);
    signal wb_cpu_rdat : std_logic_vector(31 downto 0);
    signal wb_cpu_sel  : std_logic_vector(3 downto 0);
    signal wb_cpu_we   : std_logic;
    signal wb_cpu_stb  : std_logic;
    signal wb_cpu_cyc  : std_logic;
    signal wb_cpu_ack  : std_logic;

    -- Wishbone Slave 0: Internal BRAM (Port B)
    signal s0_adr      : std_logic_vector(31 downto 0);
    signal s0_wdat     : std_logic_vector(31 downto 0);
    signal s0_rdat     : std_logic_vector(31 downto 0);
    signal s0_sel      : std_logic_vector(3 downto 0);
    signal s0_we       : std_logic;
    signal s0_stb      : std_logic;
    signal s0_cyc      : std_logic;
    signal s0_ack      : std_logic;
    signal bram_we_b   : std_logic_vector(3 downto 0);

    -- Wishbone Slave 1: Main SDRAM
    signal s1_adr      : std_logic_vector(31 downto 0);
    signal s1_wdat     : std_logic_vector(31 downto 0);
    signal s1_rdat     : std_logic_vector(31 downto 0);
    signal s1_sel      : std_logic_vector(3 downto 0);
    signal s1_we       : std_logic;
    signal s1_stb      : std_logic;
    signal s1_cyc      : std_logic;
    signal s1_ack      : std_logic;

    -- Wishbone Slave 2: VGA (Placeholder / Terminated)
    signal s2_adr      : std_logic_vector(31 downto 0);
    signal s2_wdat     : std_logic_vector(31 downto 0);
    signal s2_rdat     : std_logic_vector(31 downto 0);
    signal s2_sel      : std_logic_vector(3 downto 0);
    signal s2_we       : std_logic;
    signal s2_stb      : std_logic;
    signal s2_cyc      : std_logic;
    signal s2_ack      : std_logic;

    -- Wishbone Slave 3: Peripheral Bridge
    signal s3_adr      : std_logic_vector(31 downto 0);
    signal s3_wdat     : std_logic_vector(31 downto 0);
    signal s3_rdat     : std_logic_vector(31 downto 0);
    signal s3_sel      : std_logic_vector(3 downto 0);
    signal s3_we       : std_logic;
    signal s3_stb      : std_logic;
    signal s3_cyc      : std_logic;
    signal s3_ack      : std_logic;

    -- Legacy Peripheral Signals (Connected through periph_bridge)
    signal uart_tx_data  : std_logic_vector(7 downto 0);
    signal uart_tx_start : std_logic;
    signal uart_tx_busy  : std_logic;
    signal uart_rdata    : std_logic_vector(31 downto 0);
    signal gpio_we       : std_logic;
    signal gpio_rdata    : std_logic_vector(31 downto 0);
    signal timer_we      : std_logic;
    signal timer_rdata   : std_logic_vector(31 downto 0);

begin

   
    U_CPU : entity work.CPU_FPGA(Structural)
        port map (
            clk           => clk,
            rst_n         => rst_n,
            imem_addr_out => pc,
            imem_rdata_in => instr,
            pc_debug      => open,
            instr_debug   => open,
            rs1_debug     => open,
            rs2_debug     => open,
            wb_adr_o      => wb_cpu_adr,
            wb_dat_o      => wb_cpu_wdat,
            wb_dat_i      => wb_cpu_rdat,
            wb_sel_o      => wb_cpu_sel,
            wb_we_o       => wb_cpu_we,
            wb_stb_o      => wb_cpu_stb,
            wb_cyc_o      => wb_cpu_cyc,
            wb_ack_i      => wb_cpu_ack
        );

    -- 2. Central Wishbone B4 Interconnect
    U_INTERCONNECT : entity work.bus_interconnect(rtl)
        port map (
            m_adr_i  => wb_cpu_adr,
            m_dat_i  => wb_cpu_wdat,
            m_dat_o  => wb_cpu_rdat,
            m_we_i   => wb_cpu_we,
            m_sel_i  => wb_cpu_sel,
            m_stb_i  => wb_cpu_stb,
            m_cyc_i  => wb_cpu_cyc,
            m_ack_o  => wb_cpu_ack,

            -- Slave 0: BRAM (0x0000_0000)
            s0_adr_o => s0_adr,
            s0_dat_o => s0_wdat,
            s0_dat_i => s0_rdat,
            s0_sel_o => s0_sel,
            s0_we_o  => s0_we,
            s0_stb_o => s0_stb,
            s0_cyc_o => s0_cyc,
            s0_ack_i => s0_ack,

            -- Slave 1: SDRAM (0x8000_0000)
            s1_adr_o => s1_adr,
            s1_dat_o => s1_wdat,
            s1_dat_i => s1_rdat,
            s1_sel_o => s1_sel,
            s1_we_o  => s1_we,
            s1_stb_o => s1_stb,
            s1_cyc_o => s1_cyc,
            s1_ack_i => s1_ack,

            -- Slave 2: VGA (0xC000_0000)
            s2_adr_o => s2_adr,
            s2_dat_o => s2_wdat,
            s2_dat_i => s2_rdat,
            s2_sel_o => s2_sel,
            s2_we_o  => s2_we,
            s2_stb_o => s2_stb,
            s2_cyc_o => s2_cyc,
            s2_ack_i => s2_ack,

            -- Slave 3: Peripherals (0xE000_0000)
            s3_adr_o => s3_adr,
            s3_dat_o => s3_wdat,
            s3_dat_i => s3_rdat,
            s3_sel_o => s3_sel,
            s3_we_o  => s3_we,
            s3_stb_o => s3_stb,
            s3_cyc_o => s3_cyc,
            s3_ack_i => s3_ack
        );

    -- 3. Dual-Port 4 KB BRAM Wrapper (Port A: Fetch, Port B: Data)
    bram_we_b <= s0_sel when (s0_we = '1' and s0_stb = '1' and s0_cyc = '1') else (others => '0');
    s0_ack    <= s0_stb and s0_cyc; -- 0-wait-state ack

    U_BRAM : entity work.bram_4kb(rtl)
        generic map (
            HEX_FILE => "boot_bram.hex"
        )
        port map (
            clk     => clk,
            addr_a  => pc(11 downto 2),
            rdata_a => instr,
            addr_b  => s0_adr(11 downto 2),
            wdata_b => s0_wdat,
            we_b    => bram_we_b,
            rdata_b => s0_rdat
        );

    -- 4. SDRAM Controller (Slave 1)
    U_SDRAM : entity work.sdram_controller(rtl)
        generic map (
            CLK_FREQ_MHZ => 50,
            SIMULATION   => SIMULATION
        )
        port map (
            clk         => clk,
            reset_n     => rst_n,
            wb_adr_i    => s1_adr,
            wb_dat_i    => s1_wdat,
            wb_dat_o    => s1_rdat,
            wb_sel_i    => s1_sel,
            wb_we_i     => s1_we,
            wb_stb_i    => s1_stb,
            wb_cyc_i    => s1_cyc,
            wb_ack_o    => s1_ack,
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

    -- 5. VGA Framebuffer Port Termination (Placeholder)
    s2_rdat <= (others => '0');
    s2_ack  <= s2_stb and s2_cyc;

    -- 6. Peripheral Sub-Bus Bridge (Slave 3)
    U_PERIPH_BRIDGE : entity work.periph_bridge(rtl)
        port map (
            wb_adr_i    => s3_adr,
            wb_dat_i    => s3_wdat,
            wb_dat_o    => s3_rdat,
            wb_we_i     => s3_we,
            wb_stb_i    => s3_stb,
            wb_cyc_i    => s3_cyc,
            wb_ack_o    => s3_ack,
            uart_data   => uart_tx_data,
            uart_we     => uart_tx_start,
            uart_rdata  => uart_rdata,
            gpio_we     => gpio_we,
            gpio_rdata  => gpio_rdata,
            timer_we    => timer_we,
            timer_rdata => timer_rdata
        );

    -- 7. UART Transmitter Peripheral
    uart_rdata <= (31 downto 1 => '0') & uart_tx_busy;

    U_UART : entity work.uart_tx
        generic map (
            CLK_FREQ  => 50000000,
            BAUD_RATE => 115200
        )
        port map (
            clk      => clk,
            rst_n    => rst_n,
            tx_data  => uart_tx_data,
            tx_start => uart_tx_start,
            tx_busy  => uart_tx_busy,
            tx_out   => uart_tx
        );

    -- 8. GPIO Subsystem
    U_GPIO_LED : entity work.gpio_led(Behavioral)
        port map (
            clk     => clk,
            rst_n   => rst_n,
            we      => gpio_we,
            wdata   => s3_wdat,
            led_out => gpio_leds
        );

    U_GPIO_KEY : entity work.gpio_key(Behavioral)
        port map (
            clk       => clk,
            rst_n     => rst_n,
            key_in    => gpio_keys,
            key_rdata => gpio_rdata
        );

    -- 9. Cycle Timer
    U_TIMER : entity work.timer(Behavioral)
        port map (
            clk         => clk,
            rst_n       => rst_n,
            timer_rdata => timer_rdata
        );

end architecture Structural;