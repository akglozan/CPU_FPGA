-- SPDX-License-Identifier: Apache-2.0
-- Copyright 2026 Ozan Akgül

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity bus_interconnect is
    port (
        -- Wishbone master interface
        m_adr_i : in  std_logic_vector(31 downto 0);
        m_dat_i : in  std_logic_vector(31 downto 0);
        m_dat_o : out std_logic_vector(31 downto 0);
        m_we_i  : in  std_logic;
        m_sel_i : in  std_logic_vector(3 downto 0);
        m_stb_i : in  std_logic;
        m_cyc_i : in  std_logic;
        m_ack_o : out std_logic;

        -- Slave 0: internal BRAM
        s0_adr_o : out std_logic_vector(31 downto 0);
        s0_dat_o : out std_logic_vector(31 downto 0);
        s0_dat_i : in  std_logic_vector(31 downto 0);
        s0_sel_o : out std_logic_vector(3 downto 0);
        s0_we_o  : out std_logic;
        s0_stb_o : out std_logic;
        s0_cyc_o : out std_logic;
        s0_ack_i : in  std_logic;

        -- Slave 1: external SDRAM
        s1_adr_o : out std_logic_vector(31 downto 0);
        s1_dat_o : out std_logic_vector(31 downto 0);
        s1_dat_i : in  std_logic_vector(31 downto 0);
        s1_sel_o : out std_logic_vector(3 downto 0);
        s1_we_o  : out std_logic;
        s1_stb_o : out std_logic;
        s1_cyc_o : out std_logic;
        s1_ack_i : in  std_logic;

        -- Slave 2: VGA framebuffer
        s2_adr_o : out std_logic_vector(31 downto 0);
        s2_dat_o : out std_logic_vector(31 downto 0);
        s2_dat_i : in  std_logic_vector(31 downto 0);
        s2_sel_o : out std_logic_vector(3 downto 0);
        s2_we_o  : out std_logic;
        s2_stb_o : out std_logic;
        s2_cyc_o : out std_logic;
        s2_ack_i : in  std_logic;

        -- Slave 3: peripheral bridge
        s3_adr_o : out std_logic_vector(31 downto 0);
        s3_dat_o : out std_logic_vector(31 downto 0);
        s3_dat_i : in  std_logic_vector(31 downto 0);
        s3_sel_o : out std_logic_vector(3 downto 0);
        s3_we_o  : out std_logic;
        s3_stb_o : out std_logic;
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
        s3_ack_i
    )
    begin
        m_dat_o <= (others => '0');
        m_ack_o <= '0';

        case active_slave is
            when slave_bram =>
                m_dat_o <= s0_dat_i;
                m_ack_o <= s0_ack_i;

            when slave_sdram =>
                m_dat_o <= s1_dat_i;
                m_ack_o <= s1_ack_i;

            when slave_vga =>
                m_dat_o <= s2_dat_i;
                m_ack_o <= s2_ack_i;

            when slave_peripheral =>
                m_dat_o <= s3_dat_i;
                m_ack_o <= s3_ack_i;

            when slave_none =>
                m_dat_o <= (others => '0');
                m_ack_o <= '0';
        end case;
    end process;

end architecture rtl;