-- Decodes whatever the SoC actually drives on uart_tx at 115200 8N1.
-- Uses simulation => false so the real baud divider is exercised.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.std_logic_textio.all;
use std.textio.all;

entity tb_uart is
    -- 2026-09-01: this testbench could not pass in any amount of time.
    -- It instantiated the SoC with NO sdram_model and boot_done tied
    -- high, but the firmware lives in SDRAM (linker_sdram.ld,
    -- 0x8000_0000) -- so every fetch returned 'Z' and the CPU executed
    -- nothing. The log showed it plainly:
    --     instr_cache: HIT adr=0x80000000 data=0xZZZZZZZZ
    -- The header here still reasoned about a BRAM-resident program,
    -- which stopped being true when the firmware moved to SDRAM; the
    -- run_us bump to 4000 documented below treated the symptom. It now
    -- runs the real boot chain (SPI upload -> boot_loader -> SDRAM),
    -- exactly like tb_firmware_sdram, and keeps simulation => false --
    -- which is this testbench's entire reason to exist, since it is the
    -- only one exercising the true 115200 divider and the real
    -- 2**16-cycle debounce paths rather than their simulation
    -- shortcuts.
    --
    -- Budget for run_us, all at simulation => false:
    --     rst_sync debounce + SDRAM power-on, before any
    --       SPI edge can be accepted at all (see spi_driver) ~ 1.60 ms
    --     SPI upload   2220 bytes * 8 bits * 400 ns          ~ 7.10 ms
    --     boot_done debounce (2**16 cycles @ 50 MHz)         ~ 1.31 ms
    --     firmware boot to main()                            ~ 0.10 ms
    --     "ABC\r\n" at real 115200 (5 * 10 bits)             ~ 0.43 ms
    --                                                        = ~10.5 ms
    -- Unlike under simulation => true, rst_sync's debounce does NOT
    -- overlap the upload here -- it gates it, which is why the 1.60 ms
    -- is a leading term rather than a hidden one. 14000 us leaves
    -- headroom for the rest of the firmware's boot log.
    generic ( run_us : natural := 14000 );
end entity tb_uart;

architecture sim of tb_uart is

    constant bit_time : time := 8680 ns;   -- 115200 baud

    -- Matches tb_firmware_sdram's SPI master. spi_slave is a plain
    -- 50 MHz shift register, so 200 ns per half-bit (10 clocks) is
    -- comfortable regardless of the `simulation` generic.
    constant SPI_HALF_BIT : time := 200 ns;

    signal clk       : std_logic := '0';
    signal rst_n     : std_logic := '0';
    signal uart_rx   : std_logic := '1';
    signal gpio_keys : std_logic_vector(3 downto 0) := (others => '1');
    signal uart_tx   : std_logic;
    signal gpio_leds : std_logic_vector(3 downto 0);

    signal sdram_cke   : std_logic;
    signal sdram_cs_n  : std_logic;
    signal sdram_ras_n : std_logic;
    signal sdram_cas_n : std_logic;
    signal sdram_we_n  : std_logic;
    signal sdram_ba    : std_logic_vector(1 downto 0);
    signal sdram_addr  : std_logic_vector(11 downto 0);
    signal sdram_dqm   : std_logic_vector(1 downto 0);
    signal sdram_dq    : std_logic_vector(15 downto 0);

    signal spi_sclk  : std_logic := '0';
    signal spi_mosi  : std_logic := '0';
    signal spi_cs_n  : std_logic := '1';
    signal boot_done : std_logic := '0';

    signal done : boolean := false;

    -- Expected output of main(): uart_putc('A','B','C','\r','\n').
    type byte_seq is array (natural range <>) of integer;
    constant expected : byte_seq := (65, 66, 67, 13, 10);

    signal rx_count : natural := 0;
    signal rx_bad   : natural := 0;

begin

    clk <= not clk after 10 ns when not done else '0';

    process
    begin
        rst_n <= '0';
        wait for 300 ns;
        rst_n <= '1';
        wait;
    end process;

    dut : entity work.rv32im_soc
        generic map (
            -- Deliberately false, unlike every other SoC-level test:
            -- the real 115200 baud divider and the real 2**16-cycle
            -- debounces are the thing under test here.
            simulation => false,
            -- boot_stub.s compiled to (lui t0,0x80000 ; jr t0) at words
            -- 0/1, NOP elsewhere -- the same stub tb_firmware_sdram
            -- uses. Without it the SoC loads the default sw/boot_bram.mif
            -- and never jumps to the SDRAM-resident firmware at all.
            hex_file   => "sim/ghdl/tb_firmware_sdram_boot.mif"
        )
        port map (
            -- 2026-09-01: no longer tied high. boot_done is now driven
            -- by spi_driver below, once the real firmware image has been
            -- bit-banged into SDRAM through the real spi_slave/
            -- boot_loader RTL. Tying it high skipped the transfer
            -- entirely, so the SDRAM the CPU then fetched from was never
            -- written.
            boot_done => boot_done,
            spi_sclk => spi_sclk, spi_mosi => spi_mosi, spi_cs_n => spi_cs_n,
            clk => clk, rst_n => rst_n, uart_rx => uart_rx,
            gpio_keys => gpio_keys, uart_tx => uart_tx, gpio_leds => gpio_leds,
            sdram_cke => sdram_cke, sdram_cs_n => sdram_cs_n,
            sdram_ras_n => sdram_ras_n, sdram_cas_n => sdram_cas_n,
            sdram_we_n => sdram_we_n, sdram_ba => sdram_ba,
            sdram_addr => sdram_addr, sdram_dqm => sdram_dqm,
            sdram_dq => sdram_dq
        );

    -- 2026-09-01: added. Without a memory model behind the SDRAM pins,
    -- every instruction fetch returned 'Z' and the CPU executed nothing.
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

    -- Real SPI master driving the real spi_slave/boot_loader RTL with
    -- the actual compiled firmware image. Structurally identical to
    -- tb_firmware_sdram's spi_driver -- see that file's header for the
    -- 8-byte little-endian header format and for how
    -- firmware_payload.hex is regenerated.
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

        -- Takes a 32-bit vector rather than a VHDL "natural":
        -- 0x8000_0000 overflows natural's 32-bit-signed-backed range.
        procedure send_word_le(w : std_logic_vector(31 downto 0)) is
        begin
            send_byte(w(7 downto 0));
            send_byte(w(15 downto 8));
            send_byte(w(23 downto 16));
            send_byte(w(31 downto 24));
        end procedure;

        constant FW_LEN : natural := 2212;
        variable n_bytes : natural := 0;
    begin
        wait until rst_n = '1';

        -- Headroom for the reset synchronizer and the SDRAM
        -- controller's power-on sequence before the first real SPI
        -- edge -- starting earlier silently swallows the first MOSI bit
        -- and shifts every byte after it (see tb_firmware_sdram).
        --
        -- 2026-09-01: this is 1600 us here, NOT the 20 us
        -- tb_firmware_sdram uses. That 20 us is explicitly qualified in
        -- its own comment as clearing the settle window "under
        -- fast_simulation" -- and this is the one testbench running
        -- simulation => false. With the real debounce, rst_sync does not
        -- release until 2**16 cycles @ 50 MHz = 1.311 ms (observed:
        -- LEDs -> 1110 @ 1.31397 ms) and the SDRAM controller's power-on
        -- sequence does not finish until ~1.462 ms (observed:
        -- sdram_model mode register loaded). Starting at 20 us drove the
        -- entire transfer into a still-reset spi_slave/boot_loader: the
        -- driver dutifully reported "2212 bytes sent" while SDRAM stayed
        -- all zeros, and the CPU then walked from 0x80000000 through
        -- 2212 bytes of 0x00000000 and off the end of the image without
        -- executing one real instruction.
        wait for 1600 us;

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
               " bytes), asserting boot_done @ " & time'image(now);
        boot_done <= '1';
        wait;
    end process;

    -- Plain 8N1 receiver on the pin.
    rx : process
        variable b  : std_logic_vector(7 downto 0);
        variable v  : integer;
        variable pc : character;
    begin
        loop
            wait until falling_edge(uart_tx);
            wait for bit_time / 2;
            if uart_tx = '0' then                 -- valid start bit
                for i in 0 to 7 loop
                    wait for bit_time;
                    b(i) := uart_tx;
                end loop;
                wait for bit_time;
                v := to_integer(unsigned(b));
                if rx_count < expected'length then
                    if v /= expected(rx_count) then
                        rx_bad <= rx_bad + 1;
                        report "FAIL  byte " & integer'image(rx_count) &
                               " is " & integer'image(v) &
                               ", expected " & integer'image(expected(rx_count))
                               severity warning;
                    end if;
                end if;
                -- Bytes past the greeting are the rest of the firmware's
                -- boot log (FW[0], WAD[0], BUS_ERR, the VGA smoke test
                -- and readback). They used to be counted as failures,
                -- back when main() printed nothing else. Their framing is
                -- still checked by the stop-bit test below -- which is
                -- what this testbench is really for, since it is the only
                -- one running the real 115200 divider.
                if uart_tx /= '1' then
                    rx_bad <= rx_bad + 1;
                    report "FAIL  missing stop bit" severity warning;
                end if;
                rx_count <= rx_count + 1;
                if v >= 32 and v < 127 then
                    pc := character'val(v);
                else
                    pc := '.';
                end if;
                report "UART byte: " & integer'image(v) &
                       "  char='" & pc &
                       "'  stop=" & std_logic'image(uart_tx) &
                       "  @ " & time'image(now);
            end if;
        end loop;
    end process;

    process (gpio_leds)
    begin
        report "LEDs -> " & to_string(gpio_leds) & " @ " & time'image(now);
    end process;

    process
    begin
        wait for run_us * 1 us;
        if rx_count >= expected'length and rx_bad = 0 then
            report "=== end of run: greeting correct, " &
                   integer'image(rx_count) &
                   " well-framed bytes received in total ===";
        else
            report "FAIL  received " & integer'image(rx_count) &
                   " bytes (need at least " &
                   integer'image(expected'length) & "), " &
                   integer'image(rx_bad) & " bad"
                   severity warning;
        end if;
        done <= true;
        wait for 100 ns;
        std.env.stop;
    end process;

end architecture sim;
