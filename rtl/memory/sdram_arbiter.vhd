-- SPDX-License-Identifier: Apache-2.0
--
-- sdram_arbiter.vhd -- 2-input Wishbone arbiter sitting between
-- sdram_controller and its two masters: the existing CPU/boot_loader
-- path (routed through bus_interconnect's slave-1 port, port "a" here)
-- and the new vga_line_fetch bus master (port "b"), added in Phase 4.2.
--
-- This is deliberately a NEW, separate arbiter rather than a third leg
-- added to rv32im_soc.vhd's existing boot_active mux (the one that
-- currently picks between the CPU and boot_loader). That mux drives
-- bus_interconnect's single global master port, i.e. it decides who
-- talks to ALL FOUR slaves at once. vga_line_fetch only ever needs
-- SDRAM -- it never touches BRAM, the VGA control/palette window, or
-- the peripheral bridge -- so giving it a vote in the global mux would
-- mean plumbing it through bus_interconnect for slaves it will never
-- use. Arbitrating one level lower, right in front of sdram_controller
-- itself, keeps bus_interconnect and the existing CPU/boot_loader mux
-- completely unchanged.
--
-- Priority is fixed: B (vga_line_fetch) always wins over A (CPU, via
-- bus_interconnect) when both want the bus. This is a real-time
-- correctness requirement, not a performance tuning choice -- if
-- vga_line_fetch doesn't finish pulling a scanline out of SDRAM before
-- vga_pixel_pipeline needs it, the display shows stale or torn pixel
-- data with no way to recover until the next frame. The CPU, by
-- contrast, only stalls a few extra cycles per scanline (roughly 80
-- word transactions' worth, once every ~64 us) -- imperceptible to
-- software, and bus_interconnect's own watchdog (65536 cycles, see its
-- header) is far longer than any stall this can cause.
--
-- Grant only changes while the bus is idle (out_cyc = '0'), so an
-- in-flight transaction always runs to completion before arbitration
-- is reconsidered -- neither master can be cut off mid-transaction.
library ieee;
use ieee.std_logic_1164.all;

entity sdram_arbiter is
    port (
        clk   : in  std_logic;
        rst_n : in  std_logic;

        -- Port A: CPU / boot_loader, via bus_interconnect slave 1.
        a_adr_i  : in  std_logic_vector(31 downto 0);
        a_dat_i  : in  std_logic_vector(31 downto 0);
        a_dat_o  : out std_logic_vector(31 downto 0);
        a_sel_i  : in  std_logic_vector(3 downto 0);
        a_we_i   : in  std_logic;
        a_stb_i  : in  std_logic;
        a_cyc_i  : in  std_logic;
        a_ack_o  : out std_logic;

        -- Port B: vga_line_fetch. Read-only in practice (it never
        -- writes), but wired symmetrically for uniformity.
        b_adr_i  : in  std_logic_vector(31 downto 0);
        b_dat_i  : in  std_logic_vector(31 downto 0);
        b_dat_o  : out std_logic_vector(31 downto 0);
        b_sel_i  : in  std_logic_vector(3 downto 0);
        b_we_i   : in  std_logic;
        b_stb_i  : in  std_logic;
        b_cyc_i  : in  std_logic;
        b_ack_o  : out std_logic;

        -- Downstream: sdram_controller's Wishbone slave port.
        m_adr_o : out std_logic_vector(31 downto 0);
        m_dat_o : out std_logic_vector(31 downto 0);
        m_dat_i : in  std_logic_vector(31 downto 0);
        m_sel_o : out std_logic_vector(3 downto 0);
        m_we_o  : out std_logic;
        m_stb_o : out std_logic;
        m_cyc_o : out std_logic;
        m_ack_i : in  std_logic
    );
end entity sdram_arbiter;

architecture rtl of sdram_arbiter is

    -- '0' = grant A, '1' = grant B.
    signal grant : std_logic := '0';

begin

    process (clk)
    begin
        if rising_edge(clk) then
            if rst_n = '0' then
                grant <= '0';
            elsif m_cyc_o = '0' then
                -- Bus idle: free to (re)arbitrate. B has priority.
                grant <= b_cyc_i;
            end if;
        end if;
    end process;

    m_adr_o <= b_adr_i when grant = '1' else a_adr_i;
    m_dat_o <= b_dat_i when grant = '1' else a_dat_i;
    m_sel_o <= b_sel_i when grant = '1' else a_sel_i;
    m_we_o  <= b_we_i  when grant = '1' else a_we_i;
    m_stb_o <= b_stb_i when grant = '1' else a_stb_i;
    m_cyc_o <= b_cyc_i when grant = '1' else a_cyc_i;

    a_dat_o <= m_dat_i;
    b_dat_o <= m_dat_i;

    a_ack_o <= m_ack_i when grant = '0' else '0';
    b_ack_o <= m_ack_i when grant = '1' else '0';

end architecture rtl;
