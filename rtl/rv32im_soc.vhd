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
        simulation : boolean := false;
        -- Path to the BRAM .mif memory-init file, forwarded to
        -- bram_4kb's hex_file generic. Defaults to the path Quartus
        -- resolves against the project root at synthesis time.
        -- Overridden by testbenches whose working directory differs
        -- (e.g. tb_rv32im_soc.vhd, run from sim/, passes
        -- "../sw/boot_bram.mif" so the relative path still resolves
        -- without needing a duplicate copy of the file).
        hex_file   : string  := "sw/boot_bram.mif"
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
        sdram_dq    : inout std_logic_vector(15 downto 0);
        -- Clock to the physical SDRAM chip. See sdram_controller.vhd.
        sdram_clk   : out   std_logic;

        -- ESP32 boot-loader SPI slave link (see spi_slave.vhd,
        -- boot_loader.vhd). Physically separate from the SD card link
        -- on the ESP32 side -- these are dedicated free GPIOs there,
        -- not the SDMMC pins. Defaulted so existing instantiations
        -- (e.g. tb_rv32im_soc.vhd) that don't connect these ports
        -- keep compiling unchanged; spi_cs_n defaults idle-high.
        spi_sclk    : in    std_logic := '0';
        spi_mosi    : in    std_logic := '0';
        spi_cs_n    : in    std_logic := '1';

        -- Asserted by the ESP32 once it has finished streaming the
        -- firmware and WAD into SDRAM over the SPI link above, telling
        -- this SoC it's safe to release the CPU from reset and hand it
        -- the bus. Async to clk, like the SPI signals; synchronized
        -- and latched below. Defaults '0' (not done) so existing
        -- instantiations that don't connect it keep compiling, and the
        -- CPU simply never comes out of reset if nothing drives it --
        -- a safe default, not a silent misconfiguration.
        boot_done   : in    std_logic := '0'
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

    -- spi_slave/boot_loader: assembles the ESP32's SPI byte stream and
    -- drives its own Wishbone master to DMA it into SDRAM.
    signal spi_rx_byte    : std_logic_vector(7 downto 0);
    signal spi_rx_valid   : std_logic;

    signal bl_adr         : std_logic_vector(31 downto 0);
    signal bl_dat         : std_logic_vector(31 downto 0);
    signal bl_sel         : std_logic_vector(3 downto 0);
    signal bl_we          : std_logic;
    signal bl_stb         : std_logic;
    signal bl_cyc         : std_logic;
    signal bl_ack         : std_logic;

    -- Selects which master drives bus_interconnect: '1' = boot_loader
    -- (DMA-loading SDRAM at boot), '0' = CPU (normal operation).
    -- Starts '1' out of reset and permanently flips to '0' the first
    -- time boot_done is observed asserted -- see the boot_done
    -- synchronizer/latch process below.
    signal boot_active    : std_logic;

    -- boot_done arrives async (its own oscillator on the ESP32 side,
    -- same reasoning as spi_sclk/mosi/cs_n), so it's synchronized here
    -- before any logic acts on it. boot_done_latched is sticky --
    -- once set it stays set until the next reset, so a brief pulse
    -- from the ESP32 is enough; it doesn't need to hold the pin high.
    -- boot_done_latched_d1 delays the CPU's own reset release by one
    -- extra cycle behind boot_active's flip, so the bus mux has
    -- already switched to the CPU by the time the CPU can issue its
    -- first bus request -- otherwise there'd be a one-cycle window
    -- where the CPU is out of reset but the mux still points at
    -- boot_loader.
    --
    -- boot_done_debounce_cnt guards against a real hardware failure the
    -- original single-cycle-latch version had no defense against:
    -- confirmed on hardware during Phase 3.3 bring-up (with a temporary
    -- SPI byte counter, since removed) that boot_done_latched could trip
    -- while the ESP32 was still visibly
    -- mid-transfer -- most likely the pin floating before the ESP32
    -- actively drove it, or noise/crosstalk from the adjacent
    -- actively-toggling SPI lines, either way a transient the old
    -- 2-cycle synchronizer alone couldn't distinguish from a real
    -- assertion. boot_done_sync(1) must now stay continuously high for
    -- BOOT_DONE_DEBOUNCE_CYCLES before boot_done_latched sets; any low
    -- cycle resets the counter to 0. Same debounce duration
    -- (2**16 =~ 1.3 ms at 50 MHz) already proven reliable against real
    -- electrical noise for the mechanical reset button in rst_sync.vhd
    -- -- negligible against the real multi-second/minute boot transfer,
    -- but far longer than any realistic glitch.
    constant BOOT_DONE_DEBOUNCE_CYCLES : natural := 65535;
    signal boot_done_sync      : std_logic_vector(1 downto 0) := (others => '0');
    signal boot_done_debounce_cnt : natural range 0 to BOOT_DONE_DEBOUNCE_CYCLES := 0;
    signal boot_done_latched   : std_logic := '0';
    signal boot_done_latched_d1 : std_logic := '0';

    -- Boot-progress display: sticky latches, set the first time each
    -- stage of the boot write path is ever observed to complete and
    -- never cleared until reset, driven onto gpio_leds while the boot
    -- loader owns the bus (see the mux further down). This makes the
    -- whole SPI -> boot_loader -> sdram_controller chain observable on
    -- the board's LEDs during the real multi-second transfer, without
    -- depending on the CPU or UART -- which is how the Phase 3.3 boot
    -- bugs were localised, and is cheap enough (four flops and a mux)
    -- to keep permanently for future bring-up.
    signal diag_byte_seen   : std_logic := '0';  -- spi_slave produced >=1 byte
    signal diag_write_seen  : std_logic := '0';  -- boot_loader started >=1 bus write
    signal diag_write_acked : std_logic := '0';  -- sdram_controller acked >=1 write

    -- u_gpio_led's normal output, muxed with the diagnostic bits above
    -- onto the physical gpio_leds port -- see the mux below.
    signal led_out_cpu : std_logic_vector(3 downto 0);


    -- Holds the CPU in reset until one cycle after boot_active has
    -- released the bus back to it. Every other module in this design
    -- keeps using rst_n_sync directly and is unaffected by this.
    signal cpu_rst_n      : std_logic;

    -- Muxed master signals actually presented to bus_interconnect.
    signal mux_adr         : std_logic_vector(31 downto 0);
    signal mux_dat_wr      : std_logic_vector(31 downto 0);
    signal mux_dat_rd      : std_logic_vector(31 downto 0);
    signal mux_sel         : std_logic_vector(3 downto 0);
    signal mux_we          : std_logic;
    signal mux_stb         : std_logic;
    signal mux_cyc         : std_logic;
    signal mux_ack         : std_logic;

    signal s0_addr        : std_logic_vector(31 downto 0);
    signal s0_wdata       : std_logic_vector(31 downto 0);
    signal s0_rdata       : std_logic_vector(31 downto 0);
    signal s0_sel         : std_logic_vector(3 downto 0);
    signal s0_we          : std_logic;
    signal s0_stb         : std_logic;
    signal s0_cyc         : std_logic;
    signal s0_ack         : std_logic;
    signal s0_ack_r       : std_logic := '0';
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

    -- Sticky bus-timeout flag from the interconnect watchdog, surfaced to
    -- software at BUS_ERR (0xE000_0014).
    signal bus_error      : std_logic;

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

    -- rst_sync's debounce stretch defaults to 2**16 = 65536 clocks
    -- (~1.3 ms at 50 MHz), timed for a real mechanical pushbutton.
    -- tb_rv32im_soc.vhd's whole scripted run is ~640 us -- shorter than
    -- that stretch -- so without this, rst_n_sync (and everything else
    -- gated by it, including the boot_done latch) never leaves reset
    -- and the CPU never executes a single instruction in simulation.
    -- Confirmed via waveform: rst_n_sync and cpu_rst_n still both '0'
    -- at 5 us into a run. A fast_simulation testbench doesn't need to
    -- model real button-bounce timing, so shrink the stretch the same
    -- way get_baud_rate above shrinks the UART bit time.
    function get_rst_stretch_bits(
        fast_simulation : boolean
    ) return natural is
    begin
        if fast_simulation then
            return 6;   -- 64 clocks, ~1.28 us at 50 MHz
        else
            return 16;  -- ~1.3 ms, real debounce timing
        end if;
    end function;

    constant rst_stretch_bits : natural :=
        get_rst_stretch_bits(simulation);

begin

    u_rst_sync : entity work.rst_sync
        generic map (
            stretch_bits => rst_stretch_bits
        )
        port map (
            clk         => clk,
            rst_n_async => rst_n,
            rst_n_sync  => rst_n_sync
        );

    u_cpu : entity work.cpu_fpga
        port map (
            clk          => clk,
            rst_n        => cpu_rst_n,

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

    u_spi_slave : entity work.spi_slave
        port map (
            clk      => clk,
            rst_n    => rst_n_sync,
            spi_sclk => spi_sclk,
            spi_mosi => spi_mosi,
            spi_cs_n => spi_cs_n,
            rx_byte  => spi_rx_byte,
            rx_valid => spi_rx_valid
        );

    u_boot_loader : entity work.boot_loader
        port map (
            clk      => clk,
            rst_n    => rst_n_sync,
            rx_byte  => spi_rx_byte,
            rx_valid => spi_rx_valid,
            wb_adr_o => bl_adr,
            wb_dat_o => bl_dat,
            wb_sel_o => bl_sel,
            wb_we_o  => bl_we,
            wb_stb_o => bl_stb,
            wb_cyc_o => bl_cyc,
            wb_ack_i => bl_ack
        );

    -- boot_done synchronizer + sticky latch. See the signal comments
    -- above for why each stage exists.
    process (clk)
    begin
        if rising_edge(clk) then
            if rst_n_sync = '0' then
                boot_done_sync <= (others => '0');
            else
                boot_done_sync <= boot_done_sync(0) & boot_done;
            end if;
        end if;
    end process;

    process (clk)
    begin
        if rising_edge(clk) then
            if rst_n_sync = '0' then
                boot_done_debounce_cnt <= 0;
                boot_done_latched      <= '0';
                boot_done_latched_d1   <= '0';
            else
                if boot_done_sync(1) = '1' then
                    if boot_done_debounce_cnt = BOOT_DONE_DEBOUNCE_CYCLES then
                        boot_done_latched <= '1';
                    else
                        boot_done_debounce_cnt <= boot_done_debounce_cnt + 1;
                    end if;
                else
                    boot_done_debounce_cnt <= 0;
                end if;
                boot_done_latched_d1 <= boot_done_latched;
            end if;
        end if;
    end process;

    -- Diagnostic sticky latches (see signal comments above).
    process (clk)
    begin
        if rising_edge(clk) then
            if rst_n_sync = '0' then
                diag_byte_seen   <= '0';
                diag_write_seen  <= '0';
                diag_write_acked <= '0';
            else
                if spi_rx_valid = '1' then
                    diag_byte_seen <= '1';
                end if;
                if bl_cyc = '1' then
                    diag_write_seen <= '1';
                end if;
                if bl_ack = '1' then
                    diag_write_acked <= '1';
                end if;
            end if;
        end if;
    end process;


    boot_active <= not boot_done_latched;

    -- The CPU comes out of reset one cycle after boot_active has
    -- already released the bus (see the signal comment above).
    cpu_rst_n <= rst_n_sync and boot_done_latched_d1;

    -- Bus master mux: routes either the CPU or boot_loader onto
    -- bus_interconnect's single master port, selected by boot_active.
    -- The two are never active at the same time by construction (the
    -- CPU is held in reset via cpu_rst_n for as long as boot_active
    -- = '1'), so a plain mux is sufficient here -- no arbiter needed.
    mux_adr    <= bl_adr    when boot_active = '1' else wb_cpu_addr;
    mux_dat_wr <= bl_dat    when boot_active = '1' else wb_cpu_wdata;
    mux_sel    <= bl_sel    when boot_active = '1' else wb_cpu_sel;
    mux_we     <= bl_we     when boot_active = '1' else wb_cpu_we;
    mux_stb    <= bl_stb    when boot_active = '1' else wb_cpu_stb;
    mux_cyc    <= bl_cyc    when boot_active = '1' else wb_cpu_cyc;

    -- Route the shared ack/read-data back to whichever master is
    -- currently selected. boot_loader never reads, so it only needs
    -- the ack half.
    bl_ack       <= mux_ack when boot_active = '1' else '0';
    wb_cpu_ack   <= mux_ack when boot_active = '0' else '0';
    wb_cpu_rdata <= mux_dat_rd;

    u_interconnect : entity work.bus_interconnect
    port map (
        clk   => clk,
        rst_n => rst_n_sync,

        m_adr_i => mux_adr,
        m_dat_i => mux_dat_wr,
        m_dat_o => mux_dat_rd,
        m_we_i  => mux_we,
        m_sel_i => mux_sel,
        m_stb_i => mux_stb,
        m_cyc_i => mux_cyc,
        m_ack_o => mux_ack,
        bus_error_o => bus_error,

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

    -- Belt-and-braces: never let a write reach the BRAM while reset is
    -- asserted. A stray write here is uniquely expensive -- BRAM holds
    -- the firmware, its contents survive every reset, and only
    -- reconfiguring the FPGA restores them, so one bad write bricks the
    -- board until it is reprogrammed. rst_sync.vhd now guarantees a
    -- clean synchronous reset, which is the real fix; this qualifier
    -- just makes the failure mode structurally impossible rather than
    -- merely unlikely, for the cost of one gate.
    bram_web <= s0_sel
        when s0_we = '1' and s0_stb = '1' and s0_cyc = '1'
             and rst_n_sync = '1'
        else (others => '0');

    -- bram_4kb (altsyncram) needs one full clock between the address
    -- being presented and rdata_b being valid. The previous
    -- combinational ack (s0_ack <= s0_stb and s0_cyc) acknowledged in
    -- the same cycle the request was issued, so MEM_Stage saw no bus
    -- stall and MEM_WB_Register latched wb_data_i before the BRAM had
    -- produced it -- every load from BRAM returned the word left over
    -- from the PREVIOUS access. main()'s delay loop is built entirely
    -- on lw/bltu/bgeu against a stack slot, so its loop condition was
    -- garbage.
    --
    -- Delaying the ack by one cycle makes MEM_Stage assert bus_stall_o
    -- for exactly that one cycle (bus_access and not wb_ack_i), which
    -- freezes the pipeline and holds addr_b stable, so rdata_b is valid
    -- in the cycle the ack finally arrives and MEM_WB_Register latches
    -- the right word. The "and not s0_ack_r" term keeps it a
    -- single-cycle pulse, so back-to-back memory instructions each get
    -- their own ack instead of the second one being acknowledged early
    -- by a still-high ack left over from the first.
    process (clk)
    begin
        if rising_edge(clk) then
            if rst_n_sync = '0' then
                s0_ack_r <= '0';
            else
                s0_ack_r <= s0_stb and s0_cyc and not s0_ack_r;
            end if;
        end if;
    end process;

    s0_ack <= s0_ack_r;

    u_bram : entity work.bram_4kb
        generic map (
            hex_file => hex_file
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
            sdram_dq     => sdram_dq,
            sdram_clk    => sdram_clk
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

            timer_data    => timer_data,
            bus_error     => bus_error
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
            led_out => led_out_cpu
        );

    -- gpio_leds mux: while boot_active='1' (still streaming, CPU not yet
    -- released), show the boot-progress display above; once
    -- boot_active='0' the CPU has been running for a cycle and
    -- led_out_cpu takes over, so software LED control behaves exactly as
    -- if this mux weren't here. LEDs are active-low (see main.c's
    -- GPIO_LED comment), so each bit is inverted: '0' (lit) once that
    -- stage has ever been observed, '1' (off) until then. Bit layout:
    -- LED0=diag_byte_seen, LED1=diag_write_seen,
    -- LED2=diag_write_acked, LED3=boot_done_latched. Watching these come
    -- up in order during a real boot shows how far the
    -- SPI -> boot_loader -> SDRAM chain got, with no instrumentation.
    gpio_leds <= (not boot_done_latched) & (not diag_write_acked) &
                 (not diag_write_seen) & (not diag_byte_seen)
                 when boot_active = '1' else led_out_cpu;

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
