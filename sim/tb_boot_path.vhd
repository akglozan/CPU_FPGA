-- SPDX-License-Identifier: Apache-2.0
-- Copyright 2026 Ozan Akgul

library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;

-- Focused testbench for the ESP32-boot write path in isolation:
-- spi_slave -> boot_loader -> sdram_controller -> sdram_model. Bit-bangs
-- a real SPI Mode 0 byte stream (matching esp32_firmware/src/main.cpp's
-- bootSendHeader()/bootSendFile() framing exactly: 8-byte little-endian
-- addr+length header, then payload bytes, all under one CS-low session)
-- at the outside, the same way the ESP32 actually does it -- nothing in
-- this testbench pokes boot_loader's or sdram_controller's internals
-- directly. After the transfer, a second, independent Wishbone master
-- (used only once boot_loader has gone idle, so there's never bus
-- contention) reads the words back straight from sdram_controller.
--
-- Two files are sent, to destinations exactly 512 bytes apart. The
-- first is the real WAD destination carrying the real 'IWAD' magic --
-- the original end-to-end question, "does a byte stream shaped like the
-- real boot transfer land correctly in SDRAM?". The second exists to
-- catch the SDRAM column-aliasing bug documented in
-- rtl/memory/sdram_controller.vhd: on the fitted 256-column part, a
-- controller that drives a 9-bit column discards byte-address bit 9, so
-- destinations 512 bytes apart collapse onto the same cells and the
-- second file silently destroys the first.
--
-- The single-file version of this testbench passed against exactly that
-- broken controller, because sim/sdram_model.vhd had been written with
-- the same 512-column assumption. Both halves had to be fixed for this
-- test to mean anything -- the model now decodes 8 column bits like the
-- real chip, and this testbench now writes across the alias stride.
entity tb_boot_path is
end entity tb_boot_path;

architecture sim of tb_boot_path is

    constant CLK_PERIOD : time := 20 ns;   -- 50 MHz
    -- SPI Mode 0, accelerated vs. the real 1 MHz (SPISettings(1000000,...)
    -- in main.cpp) so the sim doesn't spend real minutes bit-banging --
    -- still 10 FPGA clocks per half-bit, comfortably inside spi_slave's
    -- 3-stage synchronizer margin (needs >=3 clk periods of stable level
    -- to guarantee a transition is caught).
    constant SCLK_HALF  : time := 200 ns;

    signal clk          : std_logic := '0';
    signal rst_n        : std_logic := '0';
    signal sim_finished : boolean   := false;

    -- SPI lines, driven exactly as an SPI Mode 0 master would.
    signal spi_sclk  : std_logic := '0';
    signal spi_mosi  : std_logic := '0';
    signal spi_cs_n  : std_logic := '1';

    signal spi_rx_byte  : std_logic_vector(7 downto 0);
    signal spi_rx_valid : std_logic;

    -- boot_loader's Wishbone master.
    signal bl_adr : std_logic_vector(31 downto 0);
    signal bl_dat : std_logic_vector(31 downto 0);
    signal bl_sel : std_logic_vector(3 downto 0);
    signal bl_we  : std_logic;
    signal bl_stb : std_logic;
    signal bl_cyc : std_logic;
    signal bl_ack : std_logic;

    -- Second, independent Wishbone master used only after boot_loader
    -- has finished (see use_read_master below) to read the result back.
    signal rd_adr : std_logic_vector(31 downto 0) := (others => '0');
    signal rd_stb : std_logic := '0';
    signal rd_cyc : std_logic := '0';
    signal rd_ack : std_logic;
    signal rd_dat : std_logic_vector(31 downto 0);

    -- Selects which of the two masters above actually drives
    -- sdram_controller. The two are never active at the same time by
    -- construction (the read only starts long after the write
    -- transaction has completed and CS has gone back high), so a plain
    -- mux -- same idea as rv32im_soc.vhd's real boot_active mux -- is
    -- sufficient here too.
    signal use_read_master : boolean := false;

    signal m_adr    : std_logic_vector(31 downto 0);
    signal m_dat_wr : std_logic_vector(31 downto 0);
    signal m_dat_rd : std_logic_vector(31 downto 0);
    signal m_sel    : std_logic_vector(3 downto 0);
    signal m_we     : std_logic;
    signal m_stb    : std_logic;
    signal m_cyc    : std_logic;
    signal m_ack    : std_logic;

    -- Physical SDRAM bus between sdram_controller and the behavioral
    -- sdram_model (same model tb_rv32im_soc.vhd already uses).
    signal sdram_cke   : std_logic;
    signal sdram_cs_n  : std_logic;
    signal sdram_ras_n : std_logic;
    signal sdram_cas_n : std_logic;
    signal sdram_we_n  : std_logic;
    signal sdram_ba    : std_logic_vector(1 downto 0);
    signal sdram_addr  : std_logic_vector(11 downto 0);
    signal sdram_dqm   : std_logic_vector(1 downto 0);
    signal sdram_dq    : std_logic_vector(15 downto 0);

begin

    -------------------------------------------------------------------
    -- Clock
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
    -- DUTs: the real write path, unmodified.
    -------------------------------------------------------------------
    U_SPI_SLAVE : entity work.spi_slave
        port map (
            clk      => clk,
            rst_n    => rst_n,
            spi_sclk => spi_sclk,
            spi_mosi => spi_mosi,
            spi_cs_n => spi_cs_n,
            rx_byte  => spi_rx_byte,
            rx_valid => spi_rx_valid
        );

    U_BOOT_LOADER : entity work.boot_loader
        port map (
            clk      => clk,
            rst_n    => rst_n,
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

    U_SDRAM_CTRL : entity work.sdram_controller
        generic map (
            CLK_FREQ_MHZ => 50,
            SIMULATION   => true
        )
        port map (
            clk          => clk,
            reset_n      => rst_n,
            wb_adr_i     => m_adr,
            wb_dat_i     => m_dat_wr,
            wb_dat_o     => m_dat_rd,
            wb_sel_i     => m_sel,
            wb_we_i      => m_we,
            wb_stb_i     => m_stb,
            wb_cyc_i     => m_cyc,
            wb_ack_o     => m_ack,
            sdram_cke    => sdram_cke,
            sdram_cs_n   => sdram_cs_n,
            sdram_ras_n  => sdram_ras_n,
            sdram_cas_n  => sdram_cas_n,
            sdram_we_n   => sdram_we_n,
            sdram_ba     => sdram_ba,
            sdram_addr   => sdram_addr,
            sdram_dqm    => sdram_dqm,
            sdram_dq     => sdram_dq,
            sdram_clk    => open
        );

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
    -- Master mux: boot_loader until the read-verifier takes over.
    -------------------------------------------------------------------
    m_adr    <= rd_adr           when use_read_master else bl_adr;
    m_dat_wr <= (others => '0')  when use_read_master else bl_dat;
    m_sel    <= "1111"           when use_read_master else bl_sel;
    m_we     <= '0'              when use_read_master else bl_we;
    m_stb    <= rd_stb           when use_read_master else bl_stb;
    m_cyc    <= rd_cyc           when use_read_master else bl_cyc;

    bl_ack <= m_ack when not use_read_master else '0';
    rd_ack <= m_ack when use_read_master else '0';
    -- Missing in the first version of this testbench: rd_dat was
    -- declared but never actually wired to sdram_controller's read-data
    -- output, so it stayed 'U'/'X' for the whole run regardless of what
    -- the DUT returned -- the "0xXXXXXXXX" mismatch that first run
    -- reported was this dangling signal, not a real RTL bug (confirmed
    -- via the VCD: m_dat_rd itself carried the correct 0x44415749).
    rd_dat <= m_dat_rd;

    -------------------------------------------------------------------
    -- Stimulus: bit-bang SPI Mode 0 exactly like bootSendHeader() /
    -- bootSendFile() in esp32_firmware/src/main.cpp, then read back.
    -------------------------------------------------------------------
    stim_process : process
        -- CPHA=0: MOSI must be stable before the SCLK rising (sample)
        -- edge and stays stable until the falling edge, matching the
        -- ESP32's SPI_MODE0 master timing.
        procedure send_byte(b : std_logic_vector(7 downto 0)) is
        begin
            for i in 7 downto 0 loop
                spi_mosi <= b(i);
                wait for SCLK_HALF;
                spi_sclk <= '1';
                wait for SCLK_HALF;
                spi_sclk <= '0';
            end loop;
        end procedure;

        -- Little-endian 32-bit send, matching bootSendHeader()'s byte
        -- ordering (addr/len LSB first).
        procedure send_word_le(w : std_logic_vector(31 downto 0)) is
        begin
            send_byte(w(7 downto 0));
            send_byte(w(15 downto 8));
            send_byte(w(23 downto 16));
            send_byte(w(31 downto 24));
        end procedure;

        -- One complete file: CS low, 8-byte addr+length header, a
        -- single 4-byte payload word, CS high. Same framing
        -- bootSendFile() uses in esp32_firmware/src/main.cpp.
        procedure send_one_word_file(
            dest : std_logic_vector(31 downto 0);
            w    : std_logic_vector(31 downto 0)
        ) is
        begin
            spi_cs_n <= '0';
            wait for SCLK_HALF;

            send_word_le(dest);
            send_word_le(x"00000004");
            send_word_le(w);          -- payload, little-endian like the file

            wait for SCLK_HALF;
            spi_cs_n <= '1';

            -- Let boot_loader's write transaction retire before the next
            -- file's CS assertion. The ACTIVE->WRITE->PRECHARGE sequence
            -- is ~12 clocks (~240 ns); 5 us is a large multiple of that.
            wait for 5 us;
        end procedure;

        -- Read one word back through the second Wishbone master and
        -- compare. Reports the value either way so a failing run says
        -- what it actually got, not just that it mismatched.
        procedure check_word(
            adr      : std_logic_vector(31 downto 0);
            expected : std_logic_vector(31 downto 0);
            -- NB: not "label" -- that is a VHDL reserved word.
            tag      : string
        ) is
        begin
            rd_adr <= adr;
            rd_cyc <= '1';
            rd_stb <= '1';

            wait until m_ack = '1';
            wait for 1 ns;  -- let rd_dat settle after the ack edge

            report tag & " read back = 0x" & to_hstring(unsigned(rd_dat)) &
                   " (expect 0x" & to_hstring(unsigned(expected)) & ")"
                   severity note;

            assert rd_dat = expected
                report "MISMATCH on " & tag & ": the boot path did not " &
                       "deliver the expected word."
                severity error;

            rd_cyc <= '0';
            rd_stb <= '0';
            wait for 200 ns;
        end procedure;
    begin
        rst_n    <= '0';
        spi_cs_n <= '1';
        wait for 200 ns;
        rst_n <= '1';

        -- Let sdram_controller's power-on sequence (ST_BOOT_WAIT ..
        -- ST_BOOT_LMR) finish before the first byte arrives.
        wait for 2 us;

        -- Two files, 512 bytes apart. 512 is not arbitrary: it is the
        -- alias stride of the bug this test exists to catch. The chip
        -- (Winbond W9864G6KH, 256 columns) has an 8-bit column address,
        -- so if sdram_controller.vhd ever again drives a 9-bit column,
        -- byte-address bit 9 is discarded and these two destinations
        -- collapse onto the same cells -- the second file would silently
        -- destroy the first. A single-file test cannot see that, which
        -- is exactly how the original bug reached hardware.
        --
        -- File 1 also doubles as the original end-to-end check: the real
        -- WAD destination carrying the real 'I','W','A','D' magic.
        report "Sending file 1: addr=0x80100000 len=4 payload 'IWAD'." severity note;
        send_one_word_file(x"80100000", x"44415749");

        report "Sending file 2: addr=0x80100200 len=4 payload 0xDEADBEEF " &
               "(+512 bytes -- the alias stride of a 9-bit column bug)." severity note;
        send_one_word_file(x"80100200", x"DEADBEEF");

        report "Both files sent. Reading back via an independent Wishbone master..."
               severity note;

        use_read_master <= true;
        wait for 20 ns;

        -- Order matters: check the FIRST destination first. If the two
        -- aliased, this is the one holding the other's payload.
        check_word(x"80100000", x"44415749", "WAD[0]  @0x80100000");
        check_word(x"80100200", x"DEADBEEF", "ALIAS[0]@0x80100200");

        wait for 500 ns;
        sim_finished <= true;
        report "tb_boot_path simulation completed." severity note;
        wait;
    end process;

end architecture sim;
