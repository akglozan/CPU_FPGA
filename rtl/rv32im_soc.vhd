library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.vga_pkg.all;

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
        boot_done   : in    std_logic := '0';

        -- Physical VGA pins (Phase 4.2). 1 bit each of R/G/B -- this
        -- board has no resistor-ladder DAC, so 8 discrete colours is
        -- the real hardware ceiling. See vga_pkg.vhd (PALETTE_BITS).
        vga_hs_pin : out std_logic;
        vga_vs_pin : out std_logic;
        vga_r_pin  : out std_logic;
        vga_g_pin  : out std_logic;
        vga_b_pin  : out std_logic
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
    -- Shortened under `simulation` for the same reason get_baud_rate and
    -- get_rst_stretch_bits below are: at the real 65535 cycles this
    -- debounce alone is ~1.31 ms, which lands AFTER the end of a typical
    -- testbench run. Every testbench that instantiates this SoC was
    -- silently dead because of it -- boot_done never latched, so
    -- cpu_rst_n never released and the CPU executed nothing, which reads
    -- exactly like a hung design. Hardware behaviour is unchanged.
    function get_boot_done_debounce (
        fast_simulation : boolean
    ) return natural is
    begin
        if fast_simulation then
            return 63;      -- ~1.26 us at 50 MHz
        else
            return 65535;   -- ~1.31 ms, real anti-glitch timing
        end if;
    end function;

    constant BOOT_DONE_DEBOUNCE_CYCLES : natural :=
        get_boot_done_debounce(simulation);
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

    -- --------------------------------------------------------------
    -- VGA clock/reset infrastructure (Phase 4.1).
    --
    -- vga_pll (ALTPLL) derives a 25 MHz pix_clk from the board's
    -- 50 MHz clk. pix_clk is a separate clock domain from clk, so its
    -- reset can't just reuse rst_n_sync directly -- that would be an
    -- un-synchronized clock-domain crossing, the same class of bug
    -- this project has already hit (and fixed) for spi_sclk/mosi/
    -- cs_n/boot_done. Instead, a second rst_sync instance (the same
    -- reusable synchronizer already used for clk/rst_n_sync above)
    -- re-synchronizes into the pix_clk domain, fed from rst_n_sync
    -- ANDed with vga_pll_locked -- so vga_timing_gen stays in reset
    -- until BOTH the system reset has cleared AND the PLL has
    -- actually achieved lock (c0 can be unstable/glitchy before
    -- lock). stretch_bits is much smaller here than the default 16:
    -- the input is already clean/debounced upstream, so this instance
    -- only needs to perform the domain crossing itself, not another
    -- ~1.3 ms mechanical-debounce stretch.
    -- --------------------------------------------------------------
    signal pix_clk         : std_logic;  -- 25 MHz, from vga_pll's c0
    signal vga_pll_locked  : std_logic;
    signal pix_rst_n_async : std_logic;  -- rst_n_sync AND vga_pll_locked
    signal pix_rst_n_sync  : std_logic;  -- clean reset, in the pix_clk domain

    -- SDRAM forwarded-clock phase shift (added 2026-08-27 -- see
    -- sdram_pll.vhd's header for the full reasoning). Unlike pix_clk,
    -- this does NOT create a new clock domain for any logic -- every
    -- register in sdram_controller and everything else still runs on
    -- the plain board clk. Only the physical SD_CLK pin is driven from
    -- sdram_clk_shifted (sdram_pll's c0, same 50 MHz frequency as clk,
    -- phase-advanced) instead of a raw copy of clk, to give the chip's
    -- read response more setup margin before the FPGA's own clk-edge
    -- capture. sdram_controller's reset is gated with sdram_pll_locked
    -- (same pattern as pix_rst_n_async below) so its power-on command
    -- sequence -- which the physical chip must see over a stable clock
    -- -- can't start before the shifted clock has actually locked.
    signal sdram_clk_shifted : std_logic;  -- from sdram_pll's c0
    signal sdram_pll_locked  : std_logic;

    -- vga_timing_gen outputs, consumed by vga_line_fetch and
    -- vga_pixel_pipeline below (Phase 4.2).
    signal vga_hsync         : std_logic;
    signal vga_vsync         : std_logic;
    signal vga_hblank        : std_logic;
    signal vga_vblank        : std_logic;
    signal vga_active_region : std_logic;
    signal vga_pixel_x       : unsigned(9 downto 0);
    signal vga_pixel_y       : unsigned(9 downto 0);
    signal vga_line_num      : unsigned(7 downto 0);
    signal vga_start_fetch   : std_logic;

    -- -------------------------------------------------------------
    -- Phase 4.2: framebuffer/palette/pixel-output stage.
    -- -------------------------------------------------------------

    -- vga_line_fetch's Wishbone master (sys clk domain), port B into
    -- sdram_arbiter.
    signal vf_adr   : std_logic_vector(31 downto 0);
    signal vf_rdata : std_logic_vector(31 downto 0);
    signal vf_sel   : std_logic_vector(3 downto 0);
    signal vf_we    : std_logic;
    signal vf_stb   : std_logic;
    signal vf_cyc   : std_logic;
    signal vf_ack   : std_logic;

    -- TEMP DIAGNOSTIC (2026-08-27, remove once resolved): real hardware
    -- shows 80 clean, static vertical stripes with a uniformly-filled
    -- framebuffer -- 80 is exactly vga_line_fetch's word count per line
    -- (320 bytes / 4), which points at the SDRAM read path rather than
    -- at vga_line_fetch's own unpacking (already GHDL-verified against
    -- a fake slave, all checks passing). This constant, when true,
    -- disconnects vga_line_fetch's Wishbone request from the real
    -- sdram_arbiter/sdram_controller entirely (b_stb_i/b_cyc_i forced
    -- to '0', so the real SDRAM machinery never sees these requests at
    -- all -- CPU/boot_loader traffic on port A is unaffected) and
    -- answers every request itself, same cycle, with a fixed
    -- 0x01010101 word -- i.e. every unpacked byte is palette index 1,
    -- which the current firmware has already set to white. If the
    -- screen goes solid white with this set, the bug is in the real
    -- SDRAM controller/timing, not in this module or anything
    -- downstream of it. If stripes persist even with SDRAM fully out
    -- of the loop, the bug is here or downstream instead.
    -- 2026-08-27 update: confirmed solid white (with the expected
    -- letterbox bars) when this was true -- everything downstream of
    -- vga_line_fetch's own Wishbone request is correct. Set back to
    -- false to restore the real SDRAM path while the actual read-path
    -- issue is investigated; flip back to true for a quick re-check
    -- if a candidate fix doesn't resolve it.
    constant DEBUG_VGA_FETCH_BYPASS : boolean := false;
    signal vf_stb_gated  : std_logic;
    signal vf_cyc_gated  : std_logic;
    signal vf_ack_used   : std_logic;
    signal vf_rdata_used : std_logic_vector(31 downto 0);

    -- sdram_arbiter's downstream port, replacing the direct s1_* ->
    -- sdram_controller wiring Phase 4.1 left in place.
    signal sdram_m_addr  : std_logic_vector(31 downto 0);
    signal sdram_m_wdata : std_logic_vector(31 downto 0);
    signal sdram_m_rdata : std_logic_vector(31 downto 0);
    signal sdram_m_sel   : std_logic_vector(3 downto 0);
    signal sdram_m_we    : std_logic;
    signal sdram_m_stb   : std_logic;
    signal sdram_m_cyc   : std_logic;
    signal sdram_m_ack   : std_logic;

    -- vga_line_buffer <-> vga_line_fetch (write side, sys clk) and
    -- vga_line_buffer <-> vga_pixel_pipeline (read side, pix_clk).
    signal lb_wr_en   : std_logic;
    signal lb_wr_bank : std_logic;
    signal lb_wr_col  : unsigned(8 downto 0);
    signal lb_wr_data : std_logic_vector(7 downto 0);
    signal lb_rd_bank : std_logic;
    signal lb_rd_col  : unsigned(8 downto 0);
    signal lb_rd_data : std_logic_vector(7 downto 0);

    signal vf_write_bank : std_logic;

    -- vga_palette: write side from the s2_* CPU bus window, read side
    -- from vga_pixel_pipeline.
    signal pal_wr_en    : std_logic;
    signal pal_wr_index : std_logic_vector(7 downto 0);
    signal pal_wr_data  : std_logic_vector(PALETTE_BITS-1 downto 0);
    signal pal_rd_index : std_logic_vector(7 downto 0);
    signal pal_rd_data  : std_logic_vector(PALETTE_BITS-1 downto 0);

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

    -- Phase 5: instruction-fetch path to SDRAM. pc_raw is IF_Stage's
    -- undelayed PC (wired below via pc_debug => pc_current_out =>
    -- pc_wire) -- unlike pc (imem_addr_o/pc_fetch_out, which has the
    -- if_id_stall/pc_delayed mux applied), it does not depend on
    -- if_id_stall, so this decode can't loop back through the stall
    -- it's about to produce.
    signal pc_raw         : std_logic_vector(31 downto 0);
    signal if_is_sdram    : std_logic;
    signal if_fetch_adr   : std_logic_vector(31 downto 0);
    signal if_fetch_rdata : std_logic_vector(31 downto 0);
    signal if_fetch_stb   : std_logic;
    signal if_fetch_cyc   : std_logic;
    signal if_fetch_ack   : std_logic;
    -- One-cycle-delayed if_fetch_ack: forces if_fetch_stb/if_fetch_cyc
    -- low for exactly the bubble cycle sdram_controller's own ST_IDLE
    -- already burns after every ack, so fetch_arbiter (and, one level
    -- up, sdram_arbiter) actually see the bus go idle and can
    -- re-arbitrate -- see the fetch-request assignments below for the
    -- full bug writeup.
    signal if_fetch_bubble : std_logic := '0';
    signal if_bus_stall   : std_logic;
    signal if_sdram_ack   : std_logic;
    signal cpu_imem_rdata : std_logic_vector(31 downto 0);

    -- fetch_arbiter <-> sdram_arbiter. The CPU-data path (s1_*, from
    -- bus_interconnect's slave-1 port) now goes through fetch_arbiter
    -- first, arbitrated against the new CPU-fetch path, before reaching
    -- sdram_arbiter's existing port A -- sdram_arbiter itself is
    -- unchanged.
    signal fa_addr        : std_logic_vector(31 downto 0);
    signal fa_wdata       : std_logic_vector(31 downto 0);
    signal fa_rdata       : std_logic_vector(31 downto 0);
    signal fa_sel         : std_logic_vector(3 downto 0);
    signal fa_we          : std_logic;
    signal fa_stb         : std_logic;
    signal fa_cyc         : std_logic;
    signal fa_ack         : std_logic;

    signal bus_error_ic    : std_logic;  -- bus_interconnect's own bus_error_o
    signal fetch_bus_error : std_logic;  -- fetch_arbiter's watchdog

    signal s2_addr        : std_logic_vector(31 downto 0);
    signal s2_wdata       : std_logic_vector(31 downto 0);
    signal s2_rdata       : std_logic_vector(31 downto 0);
    signal s2_sel         : std_logic_vector(3 downto 0);
    signal s2_we          : std_logic;
    signal s2_stb         : std_logic;
    signal s2_cyc         : std_logic;
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

    -- SDRAM read capture alignment. See the NOTE ON READ CAPTURE
    -- ALIGNMENT header in rtl/memory/sdram_controller.vhd: the
    -- behavioural SDRAM model captures a command one cycle later than
    -- the real chip does (the chip runs off a forwarded copy of clk on
    -- SD_CLK, so it sees a command essentially as it is launched), which
    -- makes the correct beat-1 sample point differ by one cycle between
    -- simulation and hardware. Same shape as get_baud_rate and
    -- get_rst_stretch_bits above.
    function get_read_cas_wait (
        fast_simulation : boolean
    ) return natural is
    begin
        -- REVERTED TO 1 FOR HARDWARE (2026-08-27). Shipping 0 was an
        -- experiment and it disproved its own hypothesis: reads that had
        -- always been correct (FW[0], WAD[0] -- both written by the
        -- ESP32 boot DMA as full 32-bit words) came back with burst beat
        -- 1 shifted up into the high half, exactly the overshoot
        -- signature. That can only happen if the window had been
        -- correctly aligned at 1 to begin with, so the read path was
        -- never the fault. Kept as a generic because the sweep was worth
        -- having and may be again.
        if fast_simulation then
            return 1;   -- sim/sdram_model.vhd's alignment
        else
            return 1;   -- real hardware: confirmed correct by the 0 experiment
        end if;
    end function;

    constant sdram_read_cas_wait : natural :=
        get_read_cas_wait(simulation);

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
            imem_rdata_i => cpu_imem_rdata,

            if_bus_stall_i => if_bus_stall,
            if_sdram_ack_i => if_sdram_ack,

            pc_debug     => pc_raw,
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


    -- Phase 5: fetch_arbiter's own watchdog (protects the new
    -- instruction-fetch path; see its header) OR'd into the same
    -- BUS_ERR bit bus_interconnect's watchdog already drives.
    bus_error <= bus_error_ic or fetch_bus_error;

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
        bus_error_o => bus_error_ic,

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

        s2_adr_o => s2_addr,
        s2_dat_o => s2_wdata,
        s2_dat_i => s2_rdata,
        s2_sel_o => s2_sel,
        s2_we_o  => s2_we,
        s2_stb_o => s2_stb,
        s2_cyc_o => s2_cyc,
        s2_ack_i => s2_ack,

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

    -- Phase 5: instruction fetch from SDRAM -- resolves the
    -- fetch-hardwired-to-BRAM blocker from the Phase 3 closeout. pc_raw
    -- in the SDRAM range (0x8000_0000-0x87FF_FFFF, same decode
    -- bus_interconnect uses for data accesses) routes the fetch through
    -- fetch_arbiter/sdram_arbiter instead of bram_4kb's port A. See
    -- fetch_arbiter.vhd, Hazard_Unit.vhd's dedicated fetch-stall case,
    -- IF_Stage.vhd's pc_in_to_ifid mux, and CPU_FPGA.vhd's
    -- pending_branch/pending_target latch for the rest of this design.
    if_is_sdram  <= '1' when pc_raw(31 downto 27) = "10000" else '0';

    -- BUG FOUND 2026-08-28 (GHDL reproduction of the Phase 5.1 hardware
    -- bring-up failure -- see docs/README.md): if_fetch_stb/if_fetch_cyc
    -- used to be driven as a bare level, "asserted for as long as PC
    -- happens to sit in the SDRAM range" -- true across every fetch,
    -- back to back, with no gap, for the entire time the CPU runs code
    -- resident in SDRAM. fetch_arbiter's grant only ever re-arbitrates
    -- when its m_cyc_o goes idle ('0'); with fetch's own request never
    -- dropping, m_cyc_o never went idle once FETCH first won the grant,
    -- so DATA (CPU stores/loads, including every stack push/pop once
    -- linker_sdram.ld put the stack in SDRAM, and every .rodata read)
    -- could never win the bus again -- despite fetch_arbiter's header
    -- comment promising "DATA always wins". The only thing that ever
    -- unstuck a pending DATA access was bus_interconnect's own watchdog
    -- (meant for genuine unanswered-slave faults) timing out after
    -- 65536 cycles and force-acking it -- reproduced in simulation as
    -- the CPU parking at a single pc for ~1.3 ms at a time, sticky
    -- BUS_ERR permanently latched, and (very plausibly, given a forced
    -- ack is not a real completed transaction) the "ABC" prints fine
    -- but everything .rodata-sourced after it comes out garbled symptom
    -- seen on real hardware. The same starvation risk exists one level
    -- up too: fa_cyc (this arbiter's own combined output) would have
    -- been just as continuously asserted whenever FETCH is running,
    -- which could in principle have starved vga_line_fetch out of
    -- sdram_arbiter's port A the same way -- never observed yet only
    -- because nothing got far enough to draw a frame.
    --
    -- Fix: hold the fetch request low for exactly the one bubble cycle
    -- that already exists right after every ack -- sdram_controller's
    -- own ST_IDLE already burns that cycle unconditionally (see its
    -- wait_cnt<=1 comment in ST_READ_DATA2/ST_WRITE_REC) before it looks
    -- at wb_cyc_i/wb_stb_i again, so this costs no additional latency;
    -- it just makes that already-existing idle cycle visible to
    -- fetch_arbiter (and, transitively, sdram_arbiter) as a genuine
    -- m_cyc_o='0' moment, restoring their ability to actually
    -- re-arbitrate in DATA's (or VGA's) favour instead of latching
    -- FETCH's grant forever. if_bus_stall below is deliberately left
    -- keyed off if_fetch_ack alone, unchanged -- the pipeline-freeze
    -- window is exactly as long as before; only the request signal
    -- fetch_arbiter sees gets this one-cycle gap.
    process (clk)
    begin
        if rising_edge(clk) then
            if rst_n_sync = '0' then
                if_fetch_bubble <= '0';
            else
                if_fetch_bubble <= if_fetch_ack;
            end if;
        end if;
    end process;

    if_fetch_adr <= pc_raw;
    if_fetch_stb <= if_is_sdram and not if_fetch_bubble;
    if_fetch_cyc <= if_is_sdram and not if_fetch_bubble;

    -- Mirrors MEM_Stage's own bus_stall_o (bus_access and not ack):
    -- held high for as long as this fetch is outstanding, however many
    -- cycles that takes.
    if_bus_stall <= if_is_sdram and not if_fetch_ack;
    if_sdram_ack <= if_is_sdram and if_fetch_ack;

    cpu_imem_rdata <= if_fetch_rdata when if_is_sdram = '1' else instruction;

    u_fetch_arbiter : entity work.fetch_arbiter
        port map (
            clk   => clk,
            rst_n => rst_n_sync,

            data_adr_i => s1_addr,
            data_dat_i => s1_wdata,
            data_dat_o => s1_rdata,
            data_sel_i => s1_sel,
            data_we_i  => s1_we,
            data_stb_i => s1_stb,
            data_cyc_i => s1_cyc,
            data_ack_o => s1_ack,

            fetch_adr_i => if_fetch_adr,
            fetch_dat_o => if_fetch_rdata,
            fetch_sel_i => "1111",
            fetch_stb_i => if_fetch_stb,
            fetch_cyc_i => if_fetch_cyc,
            fetch_ack_o => if_fetch_ack,

            m_adr_o => fa_addr,
            m_dat_o => fa_wdata,
            m_dat_i => fa_rdata,
            m_sel_o => fa_sel,
            m_we_o  => fa_we,
            m_stb_o => fa_stb,
            m_cyc_o => fa_cyc,
            m_ack_i => fa_ack,

            bus_error_o => fetch_bus_error
        );

    -- Phase 4.2: sdram_arbiter sits between the CPU-data path (now via
    -- fetch_arbiter above, port A) and sdram_controller, with
    -- vga_line_fetch as port B. See sdram_arbiter.vhd for why this is a
    -- separate arbiter rather than a third leg on the boot_active mux
    -- above. Unchanged since Phase 4.2 -- only what feeds its port A
    -- changed (fa_* instead of s1_* directly).
    u_sdram_arbiter : entity work.sdram_arbiter
        port map (
            clk   => clk,
            rst_n => rst_n_sync,

            a_adr_i => fa_addr,
            a_dat_i => fa_wdata,
            a_dat_o => fa_rdata,
            a_sel_i => fa_sel,
            a_we_i  => fa_we,
            a_stb_i => fa_stb,
            a_cyc_i => fa_cyc,
            a_ack_o => fa_ack,

            b_adr_i => vf_adr,
            b_dat_i => (others => '0'),  -- vga_line_fetch never writes
            b_dat_o => vf_rdata,
            b_sel_i => vf_sel,
            b_we_i  => vf_we,
            b_stb_i => vf_stb_gated,
            b_cyc_i => vf_cyc_gated,
            b_ack_o => vf_ack,

            m_adr_o => sdram_m_addr,
            m_dat_o => sdram_m_wdata,
            m_dat_i => sdram_m_rdata,
            m_sel_o => sdram_m_sel,
            m_we_o  => sdram_m_we,
            m_stb_o => sdram_m_stb,
            m_cyc_o => sdram_m_cyc,
            m_ack_i => sdram_m_ack
        );

    -- TEMP DIAGNOSTIC wiring for DEBUG_VGA_FETCH_BYPASS -- see the
    -- constant's declaration above for the full explanation.
    vf_stb_gated  <= '0' when DEBUG_VGA_FETCH_BYPASS else vf_stb;
    vf_cyc_gated  <= '0' when DEBUG_VGA_FETCH_BYPASS else vf_cyc;
    vf_ack_used   <= vf_stb when DEBUG_VGA_FETCH_BYPASS else vf_ack;
    vf_rdata_used <= x"01010101" when DEBUG_VGA_FETCH_BYPASS else vf_rdata;

    -- SDRAM forwarded-clock PLL (added 2026-08-27, see sdram_pll.vhd's
    -- header and the sdram_clk_shifted/sdram_pll_locked declarations
    -- above). areset follows the same active-high-from-active-low
    -- convention as u_vga_pll below.
    u_sdram_pll : entity work.sdram_pll
        port map (
            inclk0 => clk,
            areset => not rst_n_sync,
            c0     => sdram_clk_shifted,
            locked => sdram_pll_locked
        );

    u_sdram : entity work.sdram_controller
        generic map (
            clk_freq_mhz  => 50,
            simulation    => simulation,
            read_cas_wait => sdram_read_cas_wait
        )
        port map (
            clk          => clk,
            -- Gated with sdram_pll_locked: the controller's power-on
            -- command sequence must not start until the physical chip
            -- has a stable, locked clock to see it over. See
            -- sdram_clk_shifted's declaration above.
            reset_n      => rst_n_sync and sdram_pll_locked,
            wb_adr_i     => sdram_m_addr,
            wb_dat_i     => sdram_m_wdata,
            wb_dat_o     => sdram_m_rdata,
            wb_sel_i     => sdram_m_sel,
            wb_we_i      => sdram_m_we,
            wb_stb_i     => sdram_m_stb,
            wb_cyc_i     => sdram_m_cyc,
            wb_ack_o     => sdram_m_ack,

            sdram_cke    => sdram_cke,
            sdram_cs_n   => sdram_cs_n,
            sdram_ras_n => sdram_ras_n,
            sdram_cas_n => sdram_cas_n,
            sdram_we_n  => sdram_we_n,
            sdram_ba     => sdram_ba,
            sdram_addr   => sdram_addr,
            sdram_dqm    => sdram_dqm,
            sdram_dq     => sdram_dq,
            -- sdram_controller's own sdram_clk output (a plain
            -- unregistered copy of clk) is left unconnected -- the
            -- physical pin is now driven from sdram_pll's
            -- phase-shifted c0 instead. See the top-level sdram_clk
            -- assignment below.
            sdram_clk    => open
        );

    -- Physical SD_CLK pin: the phase-shifted PLL output, not a raw
    -- copy of clk. See sdram_clk_shifted's declaration above.
    sdram_clk <= sdram_clk_shifted;

    -- VGA slave-2 window (0xC000_0000+, see bus_interconnect.vhd):
    -- palette control registers. Word-addressed, 256 entries at
    -- +4*index; software writes a colour with a plain 32-bit store
    -- (only the low PALETTE_BITS bits of the low byte are stored --
    -- see vga_palette.vhd). Single-cycle ack, no readback yet (reads
    -- always return 0) -- readback wasn't needed for anything so far
    -- and would mean giving vga_palette a second read port on this
    -- clock domain; add one if software ever needs to read back a
    -- palette entry it wrote.
    pal_wr_en    <= s2_we and s2_stb and s2_cyc;
    pal_wr_index <= s2_addr(9 downto 2);
    pal_wr_data  <= s2_wdata(PALETTE_BITS-1 downto 0);

    s2_rdata <= (others => '0');
    s2_ack   <= s2_stb and s2_cyc;

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
        generic map (
            simulation => simulation
        )
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

    -- ------------------------------------------------------------------
    -- VGA (Phase 4.1): PLL, pix_clk-domain reset, and the timing
    -- generator itself. See the signal declarations above for the
    -- reasoning behind the reset synchronization.
    -- ------------------------------------------------------------------

    -- 50 MHz clk -> 25 MHz pix_clk (CLK0_MULTIPLY_BY=1, CLK0_DIVIDE_BY=2).
    -- areset is ALTPLL's own reset pin, active-HIGH -- the inverse of
    -- this project's active-low rst_n_sync convention.
    u_vga_pll : entity work.vga_pll
        port map (
            inclk0 => clk,
            areset => not rst_n_sync,
            c0     => pix_clk,
            locked => vga_pll_locked
        );

    -- Domain-crossing reset for pix_clk, held until rst_n_sync has
    -- cleared AND vga_pll has locked. stretch_bits is small: this
    -- instance only needs to perform the clk -> pix_clk synchronizer
    -- crossing, not another full mechanical-debounce stretch.
    pix_rst_n_async <= rst_n_sync and vga_pll_locked;

    u_vga_rst_sync : entity work.rst_sync
        generic map (
            stretch_bits => 4
        )
        port map (
            clk         => pix_clk,
            rst_n_async => pix_rst_n_async,
            rst_n_sync  => pix_rst_n_sync
        );

    -- 640x480@60 sync/blanking/letterbox timing generator. Verified
    -- standalone in sim/tb_vga_timing_gen.vhd; see docs/README.md
    -- Phase 4 for what's been checked. Outputs are not yet connected
    -- to anything -- Phase 4.2 (framebuffer, line fetch, pixel output)
    -- is what will consume them.
    u_vga_timing_gen : entity work.vga_timing_gen
        port map (
            pix_clk       => pix_clk,
            rst_n         => pix_rst_n_sync,
            hsync         => vga_hsync,
            vsync         => vga_vsync,
            hblank        => vga_hblank,
            vblank        => vga_vblank,
            active_region => vga_active_region,
            pixel_x       => vga_pixel_x,
            pixel_y       => vga_pixel_y,
            line_num      => vga_line_num,
            start_fetch   => vga_start_fetch
        );

    -- ------------------------------------------------------------------
    -- Phase 4.2: framebuffer line fetch, line buffer, palette, and
    -- pixel-output stage. See each module's own header for the
    -- reasoning (CDC handling, bank ping-pong, latency matching).
    -- ------------------------------------------------------------------

    u_vga_line_fetch : entity work.vga_line_fetch
        port map (
            clk             => clk,
            rst_n           => rst_n_sync,

            pix_clk         => pix_clk,
            pix_rst_n       => pix_rst_n_sync,
            start_fetch_pix => vga_start_fetch,
            line_num_pix    => vga_line_num,

            wb_adr_o => vf_adr,
            wb_dat_i => vf_rdata_used,
            wb_sel_o => vf_sel,
            wb_we_o  => vf_we,
            wb_stb_o => vf_stb,
            wb_cyc_o => vf_cyc,
            wb_ack_i => vf_ack_used,

            buf_wr_en    => lb_wr_en,
            buf_wr_bank  => lb_wr_bank,
            buf_wr_col   => lb_wr_col,
            buf_wr_data  => lb_wr_data,
            write_bank_o => vf_write_bank
        );

    u_vga_line_buffer : entity work.vga_line_buffer
        port map (
            wr_clk  => clk,
            wr_en   => lb_wr_en,
            wr_bank => lb_wr_bank,
            wr_col  => lb_wr_col,
            wr_data => lb_wr_data,

            rd_clk  => pix_clk,
            rd_bank => lb_rd_bank,
            rd_col  => lb_rd_col,
            rd_data => lb_rd_data
        );

    u_vga_palette : entity work.vga_palette
        port map (
            wr_clk   => clk,
            wr_en    => pal_wr_en,
            wr_index => pal_wr_index,
            wr_data  => pal_wr_data,

            rd_clk   => pix_clk,
            rd_index => pal_rd_index,
            rd_data  => pal_rd_data
        );

    u_vga_pixel_pipeline : entity work.vga_pixel_pipeline
        port map (
            pix_clk   => pix_clk,
            pix_rst_n => pix_rst_n_sync,

            hsync_i         => vga_hsync,
            vsync_i         => vga_vsync,
            hblank_i        => vga_hblank,
            active_region_i => vga_active_region,
            pixel_x_i       => vga_pixel_x,

            write_bank_i => vf_write_bank,

            buf_rd_bank => lb_rd_bank,
            buf_rd_col  => lb_rd_col,
            buf_rd_data => lb_rd_data,

            pal_rd_index => pal_rd_index,
            pal_rd_data  => pal_rd_data,

            vga_hsync => vga_hs_pin,
            vga_vsync => vga_vs_pin,
            vga_r     => vga_r_pin,
            vga_g     => vga_g_pin,
            vga_b     => vga_b_pin
        );

end architecture structural;
