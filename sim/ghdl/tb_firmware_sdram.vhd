-- SPDX-License-Identifier: Apache-2.0
--
-- tb_firmware_sdram.vhd -- regression test for a real bug found during
-- Phase 5.1 bring-up: rv32_firmware's compiled firmware.bin, running
-- from SDRAM via the Phase 5 fetch path, printed "ABC" (raw immediate
-- putc calls) on real hardware but came out garbled/missing after that
-- -- every .rodata-sourced byte (string literals, the uart_print_hex32
-- digit table) and everything touching the stack, which linker_sdram.ld
-- also put in SDRAM.
--
-- tb_if_sdram_fetch.vhd already proved the fetch mechanism itself works
-- for a short, hand-assembled, lightly-interleaved sequence. This test
-- is a faithful (if accelerated) replica of the real boot chain -- it
-- bit-bangs the ACTUAL compiled firmware.bin over the real
-- spi_slave/boot_loader RTL (8-byte little-endian header, MSB-first,
-- Mode 0, matching docs/README.md's Phase 3 closeout), asserts
-- boot_done, and decodes whatever appears on uart_tx exactly like a
-- serial monitor would -- because what's different about a real
-- program versus the narrow earlier test is the ACCESS PATTERN:
-- uart_print_hex32()/uart_print_str() interleave continuous instruction
-- fetch with frequent single-byte .rodata reads, and the stack itself
-- now lives in the SDRAM WORK region too -- all sharing fetch_arbiter
-- and sdram_arbiter far more heavily than the earlier test exercised.
-- It does not bother sending DOOM1.WAD -- boot_loader.vhd doesn't care
-- how many files arrive, and this test only needs FIRMWARE.BIN in place
-- before boot_done releases the CPU.
--
-- ROOT CAUSE (found 2026-08-28 via this test): if_fetch_stb/if_fetch_cyc
-- in rv32im_soc.vhd used to be a bare level -- asserted for as long as
-- PC sat in the SDRAM range, with no gap between back-to-back fetches.
-- fetch_arbiter's grant only re-arbitrates when its m_cyc_o goes idle,
-- and fetch's own request never did -- so once FETCH first won the
-- grant, DATA (every stack push/pop, every .rodata read) could never
-- win the bus again, no matter how long it waited. The system only
-- limped along at all because bus_interconnect's own watchdog (meant
-- for genuine unanswered-slave faults) eventually force-acked each
-- starved DATA access after its full 65536-cycle timeout -- observed
-- here as the CPU parking on a single pc for ~1.3 ms at a time, BUS_ERR
-- permanently latched, and a forced ack (not a real completed
-- transaction) very plausibly explaining the garbled real-hardware
-- output. Fixed by holding if_fetch_stb/if_fetch_cyc low for the one
-- bubble cycle sdram_controller's own ST_IDLE already burns after every
-- ack (see its wait_cnt<=1 comment) -- costs no extra latency, but
-- finally gives fetch_arbiter (and, transitively, sdram_arbiter, which
-- had the identical exposure against vga_line_fetch, never yet
-- triggered) a real idle cycle to re-arbitrate.
--
-- This test locks that fix in: it checks the immediate "ABC\r\n" greeting
-- arrives intact, that GPIO_LED reaches 0xF (main()'s first store, now
-- itself a stack-adjacent SDRAM data write) promptly after boot rather
-- than only after a multi-millisecond watchdog-forced stall, and that
-- BUS_ERR never latches during the whole run.
--
-- Support files (checked into sim/ghdl/, regenerate if rv32_firmware's
-- source or linker script ever changes):
--   sim/ghdl/firmware_payload.hex -- one hex byte per line, extracted
--     from rv32_firmware/build/firmware.bin, e.g.:
--       python3 -c "
--       data = open('rv32_firmware/build/firmware.bin','rb').read()
--       open('sim/ghdl/firmware_payload.hex','w').write(
--           '\n'.join(f'{b:02x}' for b in data) + '\n')"
--     and update FW_LEN in spi_driver below to len(data) if it changes.
--   sim/ghdl/tb_firmware_sdram_boot.mif -- 1024-word Quartus MIF holding
--     boot_stub.s's two compiled words (lui t0,0x80000 ; jr t0) at
--     addresses 0/1, NOP (0x00000013) elsewhere; only needs regenerating
--     if boot_stub.s itself changes.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.std_logic_textio.all;
use std.textio.all;

entity tb_firmware_sdram is
    generic ( run_us : natural := 30000 );
end entity tb_firmware_sdram;

architecture sim of tb_firmware_sdram is

    constant SPI_HALF_BIT : time := 200 ns;

    -- rv32im_soc's get_baud_rate() runs the UART at 12.5 MHz (not the
    -- real board's 115200) whenever generic simulation=>true is set,
    -- exactly as this DUT is instantiated below.
    constant UART_BIT_TIME : time := 80 ns;

    signal clk       : std_logic := '0';
    signal rst_n     : std_logic := '0';
    signal uart_rx   : std_logic := '1';
    signal gpio_keys : std_logic_vector(3 downto 0) := (others => '1');
    signal uart_tx   : std_logic;
    signal gpio_leds : std_logic_vector(3 downto 0);

    signal spi_sclk  : std_logic := '0';
    signal spi_mosi  : std_logic := '0';
    signal spi_cs_n  : std_logic := '1';
    signal boot_done : std_logic := '0';

    signal sdram_cke   : std_logic;
    signal sdram_cs_n  : std_logic;
    signal sdram_ras_n : std_logic;
    signal sdram_cas_n : std_logic;
    signal sdram_we_n  : std_logic;
    signal sdram_ba    : std_logic_vector(1 downto 0);
    signal sdram_addr  : std_logic_vector(11 downto 0);
    signal sdram_dqm   : std_logic_vector(1 downto 0);
    signal sdram_dq    : std_logic_vector(15 downto 0);

    signal done : boolean := false;

    -- Set once boot_active releases the bus back to the CPU (mirrors
    -- gpio_leds' own mux condition in rv32im_soc.vhd), so the two
    -- checker processes below know when to start their clocks.
    signal boot_finished : boolean := false;
    signal boot_finished_time : time := 0 ns;

    -- First 5 UART bytes received, and how many have arrived so far --
    -- checked against "ABC\r\n" (65,66,67,13,10) once available.
    type byte_array is array (natural range <>) of integer;
    signal rx_bytes  : byte_array(0 to 4) := (others => -1);
    signal rx_count  : natural := 0;

    -- One pass/fail signal per check (each driven by exactly one
    -- process -- an unresolved type like these can't have more than one
    -- driver, hence not a single shared counter).
    signal led_check_failed      : boolean := false;
    signal greeting_check_failed : boolean := false;
    signal buserr_check_failed   : boolean := false;

begin

    clk <= not clk after 10 ns when not done else '0';   -- 50 MHz

    process
    begin
        rst_n <= '0';
        wait for 200 ns;
        wait until rising_edge(clk);
        rst_n <= '1';
        report "reset released";
        wait;
    end process;

    dut : entity work.rv32im_soc
        generic map (
            simulation => true,
            hex_file   => "sim/ghdl/tb_firmware_sdram_boot.mif"
        )
        port map (
            boot_done   => boot_done,
            clk         => clk,
            rst_n       => rst_n,
            uart_rx     => uart_rx,
            gpio_keys   => gpio_keys,
            uart_tx     => uart_tx,
            gpio_leds   => gpio_leds,
            spi_sclk    => spi_sclk,
            spi_mosi    => spi_mosi,
            spi_cs_n    => spi_cs_n,
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

    u_sdram : entity work.sdram_model
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

    -- Real SPI master, driving the real spi_slave/boot_loader RTL with
    -- the actual compiled firmware image (extracted one hex byte per
    -- line into firmware_payload.hex by the same shell session that
    -- built rv32_firmware/build/firmware.bin).
    spi_driver : process
        file payload_file : text open read_mode is "sim/ghdl/firmware_payload.hex";
        variable line_v   : line;
        variable byte_v   : std_logic_vector(7 downto 0);

        procedure send_byte(b : std_logic_vector(7 downto 0)) is
        begin
            for i in 7 downto 0 loop
                spi_mosi <= b(i);
                wait for SPI_HALF_BIT;
                spi_sclk <= '1';
                wait for SPI_HALF_BIT;
                spi_sclk <= '0';
            end loop;
        end procedure;

        -- Takes the word directly as a 32-bit vector rather than a
        -- VHDL "natural" -- 0x8000_0000 (2,147,483,648) overflows
        -- "natural"'s 32-bit-signed-backed range (max 2^31-1), a classic
        -- VHDL integer-width trap for anything with the top address bit
        -- set.
        procedure send_word_le(w : std_logic_vector(31 downto 0)) is
        begin
            send_byte(w(7 downto 0));
            send_byte(w(15 downto 8));
            send_byte(w(23 downto 16));
            send_byte(w(31 downto 24));
        end procedure;

        constant FW_LEN : natural := 2252;
        variable n_bytes : natural := 0;
    begin
        wait until rst_n = '1';

        -- Give the SoC's internal reset synchronizer and the SDRAM
        -- controller's own power-on command sequence generous headroom
        -- to finish settling before the first real SPI edge. An earlier
        -- version of this test started at +500ns, well before that
        -- settled -- spi_slave's synchronizers/bit_count were still
        -- gated by an unsettled reset, silently swallowing the first
        -- real MOSI bit and shifting every byte after it by one bit,
        -- producing a bogus destination address/length and making it
        -- look (misleadingly) as though every SDRAM fetch returned zero.
        -- 20us comfortably clears both under fast_simulation.
        wait for 20 us;

        spi_cs_n <= '0';
        wait for SPI_HALF_BIT;

        -- 8-byte header: destination address 0x8000_0000, then length.
        send_word_le(x"80000000");
        send_word_le(std_logic_vector(to_unsigned(FW_LEN, 32)));

        while not endfile(payload_file) loop
            readline(payload_file, line_v);
            hread(line_v, byte_v);
            send_byte(byte_v);
            n_bytes := n_bytes + 1;
        end loop;

        spi_cs_n <= '1';
        wait for 2 us;

        assert n_bytes = FW_LEN
            report "spi_driver: sent " & integer'image(n_bytes) &
                   " payload bytes, expected " & integer'image(FW_LEN)
            severity warning;

        report "spi_driver: FIRMWARE.BIN sent (" & integer'image(n_bytes) &
               " bytes), asserting boot_done";
        boot_done <= '1';
        wait;
    end process;

    -- Plain 8N1 UART receiver -- same shape as tb_uart.vhd's, but
    -- reporting every byte rather than checking a fixed sequence, since
    -- this test cares about the whole stream, not just the first few
    -- characters.
    rx : process
        variable b  : std_logic_vector(7 downto 0);
        variable v  : integer;
        variable pc : character;
    begin
        loop
            wait until falling_edge(uart_tx);
            wait for UART_BIT_TIME / 2;
            if uart_tx = '0' then
                for i in 0 to 7 loop
                    wait for UART_BIT_TIME;
                    b(i) := uart_tx;
                end loop;
                wait for UART_BIT_TIME;
                v := to_integer(unsigned(b));
                if v >= 32 and v < 127 then
                    pc := character'val(v);
                else
                    pc := '.';
                end if;
                report "UART byte: " & integer'image(v) &
                       "  char='" & pc &
                       "'  stop=" & std_logic'image(uart_tx) &
                       "  @ " & time'image(now);
                if rx_count <= 4 then
                    rx_bytes(rx_count) <= v;
                end if;
                rx_count <= rx_count + 1;
            end if;
        end loop;
    end process;

    process (gpio_leds)
    begin
        report "LEDs -> " & to_string(gpio_leds) & " @ " & time'image(now);
    end process;

    -- boot_active releases the bus back to the CPU one cycle after
    -- boot_done_latched sets (see rv32im_soc.vhd's cpu_rst_n comment);
    -- LEDs -> "0000" is that same moment made visible externally (all
    -- four boot-progress diag bits sticky-high, boot_done_latched just
    -- set -- see the gpio_leds mux's bit layout comment). Using it here
    -- avoids needing a GHDL external-name probe just to know when to
    -- start the two checks below.
    process (gpio_leds)
    begin
        if gpio_leds = "0000" and not boot_finished then
            boot_finished      <= true;
            boot_finished_time <= now;
        end if;
    end process;

    -- Check 1: GPIO_LED must reach 0xF (main()'s first store -- itself
    -- now a stack-adjacent SDRAM data write) promptly after boot. The
    -- pre-fix bug made this take ~10.45ms (repeated 1.3ms
    -- bus_interconnect watchdog timeouts forcing each starved store
    -- through one at a time); a correctly-arbitrated fetch/data path
    -- reaches it in on the order of 10us. 500us is generous headroom
    -- while still failing hard on any reintroduction of the starvation.
    led_check : process
    begin
        wait until boot_finished;
        wait for 500 us;
        if gpio_leds /= "1111" then
            report "FAIL  GPIO_LED did not reach 0xF within 500us of boot completing " &
                   "(got " & to_string(gpio_leds) & ") -- looks like the " &
                   "fetch/data starvation bug is back"
                   severity warning;
            led_check_failed <= true;
        else
            report "PASS  GPIO_LED reached 0xF within 500us of boot completing";
        end if;
        wait;
    end process;

    -- Check 2: the immediate "ABC\r\n" greeting (raw putc calls, no
    -- .rodata involved) must arrive intact and in order.
    greeting_check : process
    begin
        wait until boot_finished;
        wait for 2 ms;
        if rx_count < 5 then
            report "FAIL  fewer than 5 UART bytes received within 2ms of boot " &
                   "completing (got " & integer'image(rx_count) & ")"
                   severity warning;
            greeting_check_failed <= true;
        elsif rx_bytes(0) = 65 and rx_bytes(1) = 66 and rx_bytes(2) = 67 and
              rx_bytes(3) = 13 and rx_bytes(4) = 10 then
            report "PASS  ABC\r\n greeting received intact";
        else
            report "FAIL  ABC\r\n greeting corrupted -- got (" &
                   integer'image(rx_bytes(0)) & "," & integer'image(rx_bytes(1)) & "," &
                   integer'image(rx_bytes(2)) & "," & integer'image(rx_bytes(3)) & "," &
                   integer'image(rx_bytes(4)) & ")"
                   severity warning;
            greeting_check_failed <= true;
        end if;
        wait;
    end process;

    -- Check 3: BUS_ERR must never latch. bus_interconnect's and
    -- fetch_arbiter's watchdogs exist for genuine unanswered-slave
    -- faults; a starved-but-otherwise-healthy access forcing one is
    -- exactly the bug this test guards against.
    buserr_check : process
        alias dbg_bus_error is <<signal dut.bus_error : std_logic>>;
    begin
        wait until boot_finished;
        wait for run_us * 1 us - now;
        if dbg_bus_error = '1' then
            report "FAIL  BUS_ERR latched during the run -- a watchdog forced " &
                   "an ack somewhere instead of a real transaction completing"
                   severity warning;
            buserr_check_failed <= true;
        else
            report "PASS  BUS_ERR never latched";
        end if;
        wait;
    end process;

    process
        variable n_failed : natural := 0;
    begin
        wait for run_us * 1 us;
        wait for 1 us;  -- let the three check processes' signal updates settle
        if led_check_failed then
            n_failed := n_failed + 1;
        end if;
        if greeting_check_failed then
            n_failed := n_failed + 1;
        end if;
        if buserr_check_failed then
            n_failed := n_failed + 1;
        end if;
        report "================================================";
        if n_failed = 0 then
            report "tb_firmware_sdram: ALL CHECKS PASSED";
        else
            report "tb_firmware_sdram: " & integer'image(n_failed) &
                   " CHECK(S) FAILED"
                   severity warning;
        end if;
        report "================================================";
        done <= true;
        wait for 100 ns;
        std.env.stop;
    end process;

end architecture sim;
