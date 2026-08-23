library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Top-level RV32IM SoC: wires the CPU_FPGA core, bus_interconnect,
-- internal bram_4kb, external sdram_controller, and the peripheral
-- bridge (UART TX, GPIO LEDs/keys, timer) into a single Wishbone B4
-- system, with rst_sync synchronizing the raw external reset pin
-- before it fans out to every register below (see rst_sync.vhd).
-- This is the synthesis top level targeted at the physical board.
entity rv32im_soc is
    generic (
        -- When true, selects fast simulation-only timing (shorter
        -- SDRAM power-on wait, higher UART baud) so testbenches don't
        -- have to model real-time power-up delays.
        simulation : boolean := false
    );
    port (
        clk         : in    std_logic;
        -- Raw external reset pin (mechanical pushbutton, may bounce);
        -- synchronized internally by rst_sync before use.
        rst_n       : in    std_logic;

        -- Reserved for a future UART receiver; not yet connected to
        -- any peripheral in this architecture.
        uart_rx     : in    std_logic;
        -- Raw, unsynchronized button inputs, synchronized by gpio_key.
        gpio_keys   : in    std_logic_vector(3 downto 0);

        -- UART serial transmit line.
        uart_tx     : out   std_logic;
        -- Board LED outputs.
        gpio_leds   : out   std_logic_vector(3 downto 0);

        -- Physical SDRAM pins, forwarded to sdram_controller.
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

architecture structural of rv32im_soc is

    signal pc             : std_logic_vector(31 downto 0);
    signal instruction    : std_logic_vector(31 downto 0);

    -- rst_n arrives directly from a raw mechanical pushbutton with no
    -- debounce circuitry. rst_n_sync is the synchronized, glitch-free
    -- version distributed to every register in the design below, so
    -- switch bounce on release can't cause different flip-flops to
    -- come out of reset at different effective moments. See
    -- rst_sync.vhd for details.
    signal rst_n_sync     : std_logic;

    signal wb_cpu_addr    : std_logic_vector(31 downto 0);
    signal wb_cpu_wdata   : std_logic_vector(31 downto 0);
    signal wb_cpu_rdata   : std_logic_vector(31 downto 0);
    signal wb_cpu_sel     : std_logic_vector(3 downto 0);
    signal wb_cpu_we      : std_logic;
    signal wb_cpu_stb     : std_logic;
    signal wb_cpu_cyc     : std_logic;
    signal wb_cpu_ack     : std_logic;

    signal s0_addr        : std_logic_vector(31 downto 0);
    signal s0_wdata       : std_logic_vector(31 downto 0);
    signal s0_rdata       : std_logic_vector(31 downto 0);
    signal s0_sel         : std_logic_vector(3 downto 0);
    signal s0_we          : std_logic;
    signal s0_stb         : std_logic;
    signal s0_cyc         : std_logic;
    signal s0_ack         : std_logic;
    signal bram_web       : std_logic_vector(3 downto 0);

    signal s1_addr        : std_logic_vector(31 downto 0);
    signal s1_wdata       : std_logic_vector(31 downto 0);
    signal s1_rdata       : std_logic_vector(31 downto 0);
    signal s1_sel         : std_logic_vector(3 downto 0);
    signal s1_we          : std_logic;
    signal s1_stb         : std_logic;
    signal s1_cyc         : std_logic;
    signal s1_ack         : std_logic;

    signal s2_rdata       : std_logic_vector(31 downto 0);
    signal s2_ack         : std_logic;

    signal s3_addr        : std_logic_vector(31 downto 0);
    signal s3_wdata       : std_logic_vector(31 downto 0);
    signal s3_rdata       : std_logic_vector(31 downto 0);
    signal s3_sel         : std_logic_vector(3 downto 0);
    signal s3_we          : std_logic;
    signal s3_stb         : std_logic;
    signal s3_cyc         : std_logic;
    signal s3_ack         : std_logic;

    signal uart_tx_data   : std_logic_vector(7 downto 0);
    signal uart_tx_start  : std_logic;
    signal uart_tx_busy   : std_logic;
    signal uart_status    : std_logic_vector(31 downto 0);

    signal gpio_led_we    : std_logic;
    signal gpio_key_data  : std_logic_vector(31 downto 0);

    signal timer_data     : std_logic_vector(31 downto 0);

    function get_baud_rate(
        fast_simulation : boolean
    ) return positive is
    begin
        if fast_simulation then
            return 12_500_000;
        else
            return 115_200;
        end if;
    end function;

    constant uart_baud_rate : positive :=
        get_baud_rate(simulation);

begin

    u_rst_sync : entity work.rst_sync
        port map (
            clk         => clk,
            rst_n_async => rst_n,
            rst_n_sync  => rst_n_sync
        );

    u_cpu : entity work.cpu_fpga
        port map (
            clk          => clk,
            rst_n        => rst_n_sync,

            imem_addr_o  => pc,
            imem_rdata_i => instruction,

            pc_debug     => open,
            instr_debug  => open,
            rs1_debug    => open,
            rs2_debug    => open,

            wb_addr_o    => wb_cpu_addr,
            wb_data_o    => wb_cpu_wdata,
            wb_data_i    => wb_cpu_rdata,
            wb_sel_o     => wb_cpu_sel,
            wb_we_o      => wb_cpu_we,
            wb_stb_o     => wb_cpu_stb,
            wb_cyc_o     => wb_cpu_cyc,
            wb_ack_i     => wb_cpu_ack
        );

    u_interconnect : entity work.bus_interconnect
    port map (
        m_adr_i => wb_cpu_addr,
        m_dat_i => wb_cpu_wdata,
        m_dat_o => wb_cpu_rdata,
        m_we_i  => wb_cpu_we,
        m_sel_i => wb_cpu_sel,
        m_stb_i => wb_cpu_stb,
        m_cyc_i => wb_cpu_cyc,
        m_ack_o => wb_cpu_ack,

        s0_adr_o => s0_addr,
        s0_dat_o => s0_wdata,
        s0_dat_i => s0_rdata,
        s0_sel_o => s0_sel,
        s0_we_o  => s0_we,
        s0_stb_o => s0_stb,
        s0_cyc_o => s0_cyc,
        s0_ack_i => s0_ack,

        s1_adr_o => s1_addr,
        s1_dat_o => s1_wdata,
        s1_dat_i => s1_rdata,
        s1_sel_o => s1_sel,
        s1_we_o  => s1_we,
        s1_stb_o => s1_stb,
        s1_cyc_o => s1_cyc,
        s1_ack_i => s1_ack,

        s2_adr_o => open,
        s2_dat_o => open,
        s2_dat_i => (others => '0'),
        s2_sel_o => open,
        s2_we_o  => open,
        s2_stb_o => open,
        s2_cyc_o => open,
        s2_ack_i => '0',

        s3_adr_o => s3_addr,
        s3_dat_o => s3_wdata,
        s3_dat_i => s3_rdata,
        s3_sel_o => s3_sel,
        s3_we_o  => s3_we,
        s3_stb_o => s3_stb,
        s3_cyc_o => s3_cyc,
        s3_ack_i => s3_ack
    );

    bram_web <= s0_sel
        when s0_we = '1' and s0_stb = '1' and s0_cyc = '1'
        else (others => '0');

    s0_ack <= s0_stb and s0_cyc;

    u_bram : entity work.bram_4kb
        generic map (
            hex_file => "boot_bram.mif"
        )
        port map (
            clk    => clk,
            addr_a => pc(11 downto 2),
            rdata_a => instruction,
            addr_b => s0_addr(11 downto 2),
            wdata_b => s0_wdata,
            we_b    => bram_web,
            rdata_b => s0_rdata
        );

    u_sdram : entity work.sdram_controller
        generic map (
            clk_freq_mhz => 50,
            simulation    => simulation
        )
        port map (
            clk          => clk,
            reset_n      => rst_n_sync,
            wb_adr_i     => s1_addr,
            wb_dat_i     => s1_wdata,
            wb_dat_o     => s1_rdata,
            wb_sel_i     => s1_sel,
            wb_we_i      => s1_we,
            wb_stb_i     => s1_stb,
            wb_cyc_i     => s1_cyc,
            wb_ack_o     => s1_ack,

            sdram_cke    => sdram_cke,
            sdram_cs_n   => sdram_cs_n,
            sdram_ras_n => sdram_ras_n,
            sdram_cas_n => sdram_cas_n,
            sdram_we_n  => sdram_we_n,
            sdram_ba     => sdram_ba,
            sdram_addr   => sdram_addr,
            sdram_dqm    => sdram_dqm,
            sdram_dq     => sdram_dq
        );

    s2_rdata <= (others => '0');
    s2_ack   <= '0';

    uart_status <= (0 => uart_tx_busy, others => '0');

    u_periph_bridge : entity work.periph_bridge
        port map (
            wb_addr_i     => s3_addr,
            wb_data_i     => s3_wdata,
            wb_data_o     => s3_rdata,
            wb_sel_i      => s3_sel,
            wb_we_i       => s3_we,
            wb_stb_i      => s3_stb,
            wb_cyc_i      => s3_cyc,
            wb_ack_o      => s3_ack,

            uart_tx_data  => uart_tx_data,
            uart_tx_start => uart_tx_start,
            uart_status   => uart_status,

            gpio_led_we   => gpio_led_we,
            gpio_key_data => gpio_key_data,

            timer_data    => timer_data
        );

    u_uart_tx : entity work.uart_tx
        generic map (
            CLK_FREQ  => 50_000_000,
            BAUD_RATE => uart_baud_rate
        )
        port map (
            clk       => clk,
            rst_n     => rst_n_sync,
            tx_data   => uart_tx_data,
            tx_start  => uart_tx_start,
            tx_busy   => uart_tx_busy,
            tx_out    => uart_tx
        );

    u_gpio_led : entity work.gpio_led
        port map (
            clk     => clk,
            rst_n   => rst_n_sync,
            we      => gpio_led_we,
            wdata   => s3_wdata,
            led_out => gpio_leds
        );

    u_gpio_key : entity work.gpio_key
        port map (
            clk        => clk,
            rst_n      => rst_n_sync,
            key_in     => gpio_keys,
            key_rdata  => gpio_key_data
        );

    u_timer : entity work.timer
        port map (
            clk         => clk,
            rst_n       => rst_n_sync,
            timer_rdata => timer_data
        );

end architecture structural;