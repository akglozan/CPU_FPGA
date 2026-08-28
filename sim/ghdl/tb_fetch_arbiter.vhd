-- SPDX-License-Identifier: Apache-2.0
--
-- tb_fetch_arbiter.vhd -- unit testbench for fetch_arbiter.vhd (Phase 5).
-- Drives its DATA and FETCH master ports directly against a small fake
-- downstream slave (echoes the requested address back as data after a
-- fixed number of cycles, same style tb_vga_line_fetch.vhd uses), so
-- every fetched/read value is predictable from the address alone.
--
-- Checks:
--   1. DATA-only request is a plain passthrough.
--   2. FETCH-only request is a plain passthrough.
--   3. DATA and FETCH both requesting the same cycle -- DATA must win,
--      and FETCH's request must still complete afterward (not be
--      dropped), once DATA's own transaction finishes.
--   4. Watchdog: a granted transaction that never sees ack from the
--      downstream slave gets a synthetic ack after TIMEOUT_CYCLES and
--      sets bus_error_o, sticky until reset.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_fetch_arbiter is
end entity tb_fetch_arbiter;

architecture sim of tb_fetch_arbiter is

    constant PERIOD  : time    := 20 ns;   -- 50 MHz
    constant TIMEOUT : natural := 32;      -- small, so the watchdog test is fast

    signal clk   : std_logic := '0';
    signal rst_n : std_logic := '0';
    signal done  : boolean := false;

    signal data_adr : std_logic_vector(31 downto 0) := (others => '0');
    signal data_dat_i : std_logic_vector(31 downto 0);
    signal data_sel : std_logic_vector(3 downto 0) := "1111";
    signal data_we  : std_logic := '0';
    signal data_stb : std_logic := '0';
    signal data_cyc : std_logic := '0';
    signal data_ack : std_logic;

    signal fetch_adr : std_logic_vector(31 downto 0) := (others => '0');
    signal fetch_dat_i : std_logic_vector(31 downto 0);
    signal fetch_sel : std_logic_vector(3 downto 0) := "1111";
    signal fetch_stb : std_logic := '0';
    signal fetch_cyc : std_logic := '0';
    signal fetch_ack : std_logic;

    signal m_adr : std_logic_vector(31 downto 0);
    signal m_dat_w : std_logic_vector(31 downto 0);
    signal m_dat_r : std_logic_vector(31 downto 0) := (others => '0');
    signal m_sel : std_logic_vector(3 downto 0);
    signal m_we  : std_logic;
    signal m_stb : std_logic;
    signal m_cyc : std_logic;
    signal m_ack : std_logic := '0';

    signal bus_error : std_logic;

    -- Fake slave control: how many cycles after stb&cyc to ack. A huge
    -- value effectively never acks (used for the watchdog test).
    signal slave_ack_delay : natural := 2;

    signal n_failures : natural := 0;

    procedure check(cond : boolean; msg : string; signal failures : inout natural) is
    begin
        if not cond then
            report "FAIL  " & msg severity warning;
            failures <= failures + 1;
        else
            report "PASS  " & msg;
        end if;
    end procedure;

begin

    clk <= not clk after PERIOD/2 when not done else '0';

    dut : entity work.fetch_arbiter
        generic map (
            TIMEOUT_CYCLES => TIMEOUT
        )
        port map (
            clk   => clk,
            rst_n => rst_n,

            data_adr_i => data_adr,
            data_dat_i => (others => '0'),
            data_dat_o => data_dat_i,
            data_sel_i => data_sel,
            data_we_i  => data_we,
            data_stb_i => data_stb,
            data_cyc_i => data_cyc,
            data_ack_o => data_ack,

            fetch_adr_i => fetch_adr,
            fetch_dat_o => fetch_dat_i,
            fetch_sel_i => fetch_sel,
            fetch_stb_i => fetch_stb,
            fetch_cyc_i => fetch_cyc,
            fetch_ack_o => fetch_ack,

            m_adr_o => m_adr,
            m_dat_o => m_dat_w,
            m_dat_i => m_dat_r,
            m_sel_o => m_sel,
            m_we_o  => m_we,
            m_stb_o => m_stb,
            m_cyc_o => m_cyc,
            m_ack_i => m_ack,

            bus_error_o => bus_error
        );

    -- Fake downstream slave: echoes m_adr as data, acks slave_ack_delay
    -- cycles after stb&cyc first assert (or never, if slave_ack_delay
    -- is set larger than the watchdog's own TIMEOUT_CYCLES).
    process (clk)
        variable cnt : natural := 0;
        variable armed : boolean := false;
    begin
        if rising_edge(clk) then
            if rst_n = '0' then
                cnt := 0;
                armed := false;
                m_ack <= '0';
            elsif m_cyc = '1' and m_stb = '1' then
                m_ack <= '0';
                if not armed then
                    armed := true;
                    cnt := 0;
                elsif cnt >= slave_ack_delay - 1 then
                    m_ack   <= '1';
                    m_dat_r <= m_adr;
                    armed   := false;
                else
                    cnt := cnt + 1;
                end if;
            else
                armed := false;
                cnt   := 0;
                m_ack <= '0';
            end if;
        end if;
    end process;

    process
    begin
        rst_n <= '0';
        wait for 100 ns;
        wait until rising_edge(clk);
        rst_n <= '1';

        --------------------------------------------------------------
        -- 1. DATA-only passthrough.
        --------------------------------------------------------------
        slave_ack_delay <= 2;
        data_adr <= x"10000000";
        data_stb <= '1';
        data_cyc <= '1';
        wait until rising_edge(clk) and data_ack = '1';
        check(data_dat_i = x"10000000", "DATA-only: readback matches requested address", n_failures);
        data_stb <= '0';
        data_cyc <= '0';
        wait until rising_edge(clk);

        --------------------------------------------------------------
        -- 2. FETCH-only passthrough.
        --------------------------------------------------------------
        fetch_adr <= x"20000000";
        fetch_stb <= '1';
        fetch_cyc <= '1';
        wait until rising_edge(clk) and fetch_ack = '1';
        check(fetch_dat_i = x"20000000", "FETCH-only: readback matches requested address", n_failures);
        fetch_stb <= '0';
        fetch_cyc <= '0';
        wait until rising_edge(clk);

        --------------------------------------------------------------
        -- 3. Simultaneous request: DATA must win, FETCH must still
        -- complete afterward (not be dropped).
        --------------------------------------------------------------
        slave_ack_delay <= 3;
        data_adr  <= x"30000000";
        fetch_adr <= x"40000000";
        data_stb  <= '1';
        data_cyc  <= '1';
        fetch_stb <= '1';
        fetch_cyc <= '1';
        wait until rising_edge(clk);
        check(fetch_ack = '0', "contention: FETCH not granted while DATA is requesting", n_failures);

        wait until rising_edge(clk) and data_ack = '1';
        check(data_dat_i = x"30000000", "contention: DATA's own transaction completed correctly", n_failures);
        data_stb <= '0';
        data_cyc <= '0';

        wait until rising_edge(clk) and fetch_ack = '1';
        check(fetch_dat_i = x"40000000", "contention: FETCH was granted afterward, not dropped", n_failures);
        fetch_stb <= '0';
        fetch_cyc <= '0';
        wait until rising_edge(clk);

        --------------------------------------------------------------
        -- 4. Watchdog: FETCH requests, slave never acks.
        --------------------------------------------------------------
        slave_ack_delay <= TIMEOUT * 4;  -- far beyond TIMEOUT_CYCLES
        fetch_adr <= x"50000000";
        fetch_stb <= '1';
        fetch_cyc <= '1';
        check(bus_error = '0', "watchdog: bus_error clear before any timeout", n_failures);

        wait until rising_edge(clk) and fetch_ack = '1' for (TIMEOUT + 10) * PERIOD;
        check(fetch_ack = '1', "watchdog: fetch_ack eventually forced high after timeout", n_failures);
        check(bus_error = '1', "watchdog: bus_error set after timeout", n_failures);
        fetch_stb <= '0';
        fetch_cyc <= '0';
        wait until rising_edge(clk);
        check(bus_error = '1', "watchdog: bus_error stays sticky after the transaction ends", n_failures);

        report "================ FAILURES: " & integer'image(n_failures) & " ================";
        done <= true;
        wait for 100 ns;
        std.env.stop;
    end process;

end architecture sim;
