-- SPDX-License-Identifier: Apache-2.0
--
-- fetch_arbiter.vhd -- 2-input Wishbone arbiter sitting between the
-- CPU's data-access path (forwarded from bus_interconnect's slave-1
-- port) and the new CPU instruction-fetch path (Phase 5: resolving the
-- fetch-hardwired-to-BRAM blocker), in front of sdram_arbiter's existing
-- port A. Mirrors sdram_arbiter.vhd's own structure and rationale --
-- arbitrate one level lower, right in front of the resource actually
-- contended for, rather than touching bus_interconnect or sdram_arbiter
-- themselves.
--
-- Priority is fixed: DATA always wins over FETCH when both want SDRAM
-- in the same cycle. A data access belongs to an instruction already
-- several pipeline stages deep and committed to needing that word; a
-- stalled fetch only delays the *next* instruction entering the pipe,
-- and Hazard_Unit's dedicated fetch-stall case freezes only the front
-- of the pipe while it waits -- the same asymmetry that already
-- justifies VGA over CPU in sdram_arbiter.
--
-- Grant only changes while the bus is idle (m_cyc_o = '0'), so an
-- in-flight transaction always runs to completion before arbitration is
-- reconsidered -- same as sdram_arbiter. The CPU-fetch side never
-- abandons a granted, in-flight transaction either (see rv32im_soc.vhd
-- and CPU_FPGA.vhd's pending_branch/pending_target latch): a branch
-- resolving while a fetch is outstanding is held pending rather than
-- redirecting pc immediately, specifically so this arbiter never has to
-- reason about a request being pulled out from under it mid-transaction.
--
-- Unlike sdram_arbiter, this arbiter also carries its own watchdog.
-- bus_interconnect's watchdog protects the data path, but nothing
-- upstream of this arbiter protected the new fetch path -- an
-- unacknowledged fetch would otherwise freeze the CPU silently forever,
-- the same failure class bus_interconnect's own watchdog exists to
-- catch (see its header). TIMEOUT_CYCLES matches bus_interconnect's
-- default for the same reason: it must comfortably exceed the SDRAM
-- controller's power-on init (~7500 cycles @ 50 MHz) plus normal
-- ACTIVATE/CAS latency.
library ieee;
use ieee.std_logic_1164.all;

entity fetch_arbiter is
    generic (
        TIMEOUT_CYCLES : natural := 65536
    );
    port (
        clk   : in  std_logic;
        rst_n : in  std_logic;

        -- Port DATA: CPU data access, via bus_interconnect slave 1.
        data_adr_i  : in  std_logic_vector(31 downto 0);
        data_dat_i  : in  std_logic_vector(31 downto 0);
        data_dat_o  : out std_logic_vector(31 downto 0);
        data_sel_i  : in  std_logic_vector(3 downto 0);
        data_we_i   : in  std_logic;
        data_stb_i  : in  std_logic;
        data_cyc_i  : in  std_logic;
        data_ack_o  : out std_logic;

        -- Port FETCH: CPU instruction fetch. Read-only in practice (it
        -- never writes), but wired symmetrically for uniformity, same
        -- as sdram_arbiter's port B.
        fetch_adr_i : in  std_logic_vector(31 downto 0);
        fetch_dat_o : out std_logic_vector(31 downto 0);
        fetch_sel_i : in  std_logic_vector(3 downto 0);
        fetch_stb_i : in  std_logic;
        fetch_cyc_i : in  std_logic;
        fetch_ack_o : out std_logic;

        -- Downstream: sdram_arbiter's port A.
        m_adr_o : out std_logic_vector(31 downto 0);
        m_dat_o : out std_logic_vector(31 downto 0);
        m_dat_i : in  std_logic_vector(31 downto 0);
        m_sel_o : out std_logic_vector(3 downto 0);
        m_we_o  : out std_logic;
        m_stb_o : out std_logic;
        m_cyc_o : out std_logic;
        m_ack_i : in  std_logic;

        -- Sticky: set the first time a granted transaction times out
        -- without ack. Held until reset. OR'd into the SoC's existing
        -- BUS_ERR bit alongside bus_interconnect's own bus_error_o.
        bus_error_o : out std_logic
    );
end entity fetch_arbiter;

architecture rtl of fetch_arbiter is

    -- '0' = grant DATA, '1' = grant FETCH.
    signal grant : std_logic := '0';

    signal to_cnt      : natural range 0 to TIMEOUT_CYCLES := 0;
    signal timeout_ack : std_logic := '0';
    signal bus_error_r : std_logic := '0';

    signal m_ack_used : std_logic;

begin

    process (clk)
    begin
        if rising_edge(clk) then
            if rst_n = '0' then
                grant <= '0';
            elsif m_cyc_o = '0' then
                -- Bus idle: free to (re)arbitrate. DATA has priority --
                -- FETCH is only granted when DATA isn't asking.
                grant <= (not data_cyc_i) and fetch_cyc_i;
            end if;
        end if;
    end process;

    m_adr_o <= fetch_adr_i when grant = '1' else data_adr_i;
    m_dat_o <= (others => '0') when grant = '1' else data_dat_i;
    m_sel_o <= fetch_sel_i when grant = '1' else data_sel_i;
    m_we_o  <= '0'         when grant = '1' else data_we_i;
    m_stb_o <= fetch_stb_i when grant = '1' else data_stb_i;
    m_cyc_o <= fetch_cyc_i when grant = '1' else data_cyc_i;

    data_dat_o  <= m_dat_i;
    fetch_dat_o <= m_dat_i;

    m_ack_used <= m_ack_i or timeout_ack;

    data_ack_o  <= m_ack_used when grant = '0' else '0';
    fetch_ack_o <= m_ack_used when grant = '1' else '0';

    -- Watchdog: count cycles the granted transaction stays unacknowledged.
    -- Structurally identical to bus_interconnect's own watchdog.
    process (clk)
    begin
        if rising_edge(clk) then
            if rst_n = '0' then
                to_cnt      <= 0;
                timeout_ack <= '0';
                bus_error_r <= '0';
            else
                timeout_ack <= '0';  -- single-cycle pulse

                if m_cyc_o = '1' and m_stb_o = '1' then
                    if m_ack_i = '1' or timeout_ack = '1' then
                        to_cnt <= 0;
                    elsif to_cnt >= TIMEOUT_CYCLES - 1 then
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

    bus_error_o <= bus_error_r;

end architecture rtl;
