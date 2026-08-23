-- SPDX-License-Identifier: Apache-2.0
-- Copyright 2026 Ozan Akgül

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Central Wishbone B4 bus interconnect / address decoder. Routes the
-- single CPU master onto one of four slaves based on the address
-- range presented on m_adr_i: internal BRAM (bootloader), external
-- SDRAM, the VGA framebuffer, or the peripheral bridge (UART, GPIO,
-- timer, etc). Only one slave's cyc/stb are ever asserted at a time;
-- an address matching no slave still generates a synchronous-looking
-- ack so the CPU doesn't hang on a stray access.
entity bus_interconnect is
    generic (
        -- Cycles a transaction may go unacknowledged before the watchdog
        -- forces an ack. Must comfortably exceed the slowest legitimate
        -- response: the SDRAM controller's power-on init is
        -- CLK_FREQ_MHZ*150 = 7500 cycles at 50 MHz (~150 us), and a CPU
        -- access issued during it waits the whole time. 65536 cycles is
        -- ~1.3 ms, well clear of that, and still far below human
        -- perception.
        TIMEOUT_CYCLES : natural := 65536
    );
    port (
        clk   : in std_logic;
        -- Active-low synchronous reset; also clears the sticky error.
        rst_n : in std_logic;

        -- Wishbone master interface
        -- Byte address from the CPU.
        m_adr_i : in  std_logic_vector(31 downto 0);
        -- Write data from the CPU.
        m_dat_i : in  std_logic_vector(31 downto 0);
        -- Read data returned to the CPU from the selected slave.
        m_dat_o : out std_logic_vector(31 downto 0);
        -- Write enable from the CPU.
        m_we_i  : in  std_logic;
        -- Byte-lane select from the CPU.
        m_sel_i : in  std_logic_vector(3 downto 0);
        -- Strobe from the CPU.
        m_stb_i : in  std_logic;
        -- Cycle indicator from the CPU.
        m_cyc_i : in  std_logic;
        -- Acknowledge returned to the CPU from the selected slave, or
        -- synthesised by the watchdog when a slave fails to respond.
        m_ack_o : out std_logic;
        -- Sticky: set the first time any access times out, held until
        -- reset. Readable by software at BUS_ERR (0xE000_0014).
        bus_error_o : out std_logic;

        -- Slave 0: internal BRAM
        s0_adr_o : out std_logic_vector(31 downto 0);
        s0_dat_o : out std_logic_vector(31 downto 0);
        s0_dat_i : in  std_logic_vector(31 downto 0);
        s0_sel_o : out std_logic_vector(3 downto 0);
        s0_we_o  : out std_logic;
        -- Asserted only while address decode selects this slave.
        s0_stb_o : out std_logic;
        -- Asserted only while address decode selects this slave.
        s0_cyc_o : out std_logic;
        s0_ack_i : in  std_logic;

        -- Slave 1: external SDRAM
        s1_adr_o : out std_logic_vector(31 downto 0);
        s1_dat_o : out std_logic_vector(31 downto 0);
        s1_dat_i : in  std_logic_vector(31 downto 0);
        s1_sel_o : out std_logic_vector(3 downto 0);
        s1_we_o  : out std_logic;
        -- Asserted only while address decode selects this slave.
        s1_stb_o : out std_logic;
        -- Asserted only while address decode selects this slave.
        s1_cyc_o : out std_logic;
        s1_ack_i : in  std_logic;

        -- Slave 2: VGA framebuffer
        s2_adr_o : out std_logic_vector(31 downto 0);
        s2_dat_o : out std_logic_vector(31 downto 0);
        s2_dat_i : in  std_logic_vector(31 downto 0);
        s2_sel_o : out std_logic_vector(3 downto 0);
        s2_we_o  : out std_logic;
        -- Asserted only while address decode selects this slave.
        s2_stb_o : out std_logic;
        -- Asserted only while address decode selects this slave.
        s2_cyc_o : out std_logic;
        s2_ack_i : in  std_logic;

        -- Slave 3: peripheral bridge
        s3_adr_o : out std_logic_vector(31 downto 0);
        s3_dat_o : out std_logic_vector(31 downto 0);
        s3_dat_i : in  std_logic_vector(31 downto 0);
        s3_sel_o : out std_logic_vector(3 downto 0);
        s3_we_o  : out std_logic;
        -- Asserted only while address decode selects this slave.
        s3_stb_o : out std_logic;
        -- Asserted only while address decode selects this slave.
        s3_cyc_o : out std_logic;
        s3_ack_i : in  std_logic
    );
end entity bus_interconnect;

architecture rtl of bus_interconnect is

    type slave_select_t is (
        slave_bram,
        slave_sdram,
        slave_vga,
        slave_peripheral,
        slave_none
    );

    signal active_slave : slave_select_t;

    -- Response from the decoded slave, before the watchdog is applied.
    signal slave_dat   : std_logic_vector(31 downto 0);
    signal slave_ack   : std_logic;

    -- Watchdog. Without this a slave that never asserts ack leaves
    -- mem_stage's bus_stall_o high forever and the CPU freezes with no
    -- outward sign -- the same silent-hang signature as the reset bug
    -- that corrupted BRAM word 0. Three ways that can happen today: the
    -- VGA slave is hard-tied s2_ack <= '0', so any access to
    -- 0xC000_0000 hangs; the SDRAM controller is newly brought up and
    -- unproven on hardware; and any future slave can regress into it.
    signal to_cnt      : natural range 0 to TIMEOUT_CYCLES := 0;
    signal timeout_ack : std_logic := '0';
    signal bus_error_r : std_logic := '0';

begin

    -- Payload signals are shared with all slaves.
    s0_adr_o <= m_adr_i;
    s0_dat_o <= m_dat_i;
    s0_sel_o <= m_sel_i;
    s0_we_o  <= m_we_i;

    s1_adr_o <= m_adr_i;
    s1_dat_o <= m_dat_i;
    s1_sel_o <= m_sel_i;
    s1_we_o  <= m_we_i;

    s2_adr_o <= m_adr_i;
    s2_dat_o <= m_dat_i;
    s2_sel_o <= m_sel_i;
    s2_we_o  <= m_we_i;

    s3_adr_o <= m_adr_i;
    s3_dat_o <= m_dat_i;
    s3_sel_o <= m_sel_i;
    s3_we_o  <= m_we_i;

    -- Address decoder.
    process (m_adr_i)
    begin
        if m_adr_i(31 downto 16) = x"0000" then
            active_slave <= slave_bram;

        elsif m_adr_i(31 downto 27) = "10000" then
            active_slave <= slave_sdram;

        elsif m_adr_i(31 downto 19) = "1100000000000" then
            active_slave <= slave_vga;

        elsif m_adr_i(31 downto 16) = x"E000" then
            active_slave <= slave_peripheral;

        else
            active_slave <= slave_none;
        end if;
    end process;

    -- Qualified Wishbone control signals.
    s0_cyc_o <= m_cyc_i when active_slave = slave_bram else '0';
    s0_stb_o <= m_stb_i when active_slave = slave_bram else '0';

    s1_cyc_o <= m_cyc_i when active_slave = slave_sdram else '0';
    s1_stb_o <= m_stb_i when active_slave = slave_sdram else '0';

    s2_cyc_o <= m_cyc_i when active_slave = slave_vga else '0';
    s2_stb_o <= m_stb_i when active_slave = slave_vga else '0';

    s3_cyc_o <= m_cyc_i when active_slave = slave_peripheral else '0';
    s3_stb_o <= m_stb_i when active_slave = slave_peripheral else '0';

    -- Return data and acknowledgement from the selected slave.
    process (
        active_slave,
        s0_dat_i,
        s0_ack_i,
        s1_dat_i,
        s1_ack_i,
        s2_dat_i,
        s2_ack_i,
        s3_dat_i,
        s3_ack_i,
        m_stb_i,
        m_cyc_i
    )
    begin
        slave_dat <= (others => '0');
        slave_ack <= '0';

        case active_slave is
            when slave_bram =>
                slave_dat <= s0_dat_i;
                slave_ack <= s0_ack_i;

            when slave_sdram =>
                slave_dat <= s1_dat_i;
                slave_ack <= s1_ack_i;

            when slave_vga =>
                slave_dat <= s2_dat_i;
                slave_ack <= s2_ack_i;

            when slave_peripheral =>
                slave_dat <= s3_dat_i;
                slave_ack <= s3_ack_i;

            when slave_none =>
                slave_dat <= (others => '0');
                slave_ack <= m_stb_i and m_cyc_i;
        end case;
    end process;

    -- Watchdog: count cycles a transaction stays unacknowledged.
    process (clk)
    begin
        if rising_edge(clk) then
            if rst_n = '0' then
                to_cnt      <= 0;
                timeout_ack <= '0';
                bus_error_r <= '0';
            else
                timeout_ack <= '0';   -- single-cycle pulse

                if m_cyc_i = '1' and m_stb_i = '1' then
                    if slave_ack = '1' or timeout_ack = '1' then
                        to_cnt <= 0;
                    elsif to_cnt >= TIMEOUT_CYCLES - 1 then
                        -- Give up: unblock the CPU and remember why.
                        to_cnt      <= 0;
                        timeout_ack <= '1';
                        bus_error_r <= '1';
                    else
                        to_cnt <= to_cnt + 1;
                    end if;
                else
                    to_cnt <= 0;
                end if;
            end if;
        end if;
    end process;

    -- A timed-out read returns zero rather than whatever the floating
    -- slave bus happened to hold, so the failure is at least
    -- deterministic. Software detects it by reading bus_error_o.
    m_ack_o <= slave_ack or timeout_ack;
    m_dat_o <= (others => '0') when timeout_ack = '1' else slave_dat;

    bus_error_o <= bus_error_r;

end architecture rtl;