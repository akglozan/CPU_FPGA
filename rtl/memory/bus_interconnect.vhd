-- SPDX-License-Identifier: Apache-2.0
-- Copyright 2026 Ozan Akgül
--
-- Licensed under the Apache License, Version 2.0 (the "License");
-- you may not use this file except in compliance with the License.
-- You may obtain a copy of the License at
--
--     http://www.apache.org/licenses/LICENSE-2.0
--
-- Unless required by applicable law or agreed to in writing, software
-- distributed under the License is distributed on an "AS IS" BASIS,
-- WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
-- See the License for the specific language governing permissions and
-- limitations under the License.

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity bus_interconnect is
    port (
        -- Wishbone Master Interface (CPU MEM Stage)
        m_adr_i  : in  std_logic_vector(31 downto 0);
        m_dat_i  : in  std_logic_vector(31 downto 0);
        m_dat_o  : out std_logic_vector(31 downto 0);
        m_we_i   : in  std_logic;
        m_sel_i  : in  std_logic_vector(3 downto 0);
        m_stb_i  : in  std_logic;
        m_cyc_i  : in  std_logic;
        m_ack_o  : out std_logic;

        -- Slave 0: Internal BRAM (0x0000_0000 - 0x0000_FFFF)
        s0_adr_o : out std_logic_vector(31 downto 0);
        s0_dat_o : out std_logic_vector(31 downto 0);
        s0_dat_i : in  std_logic_vector(31 downto 0);
        s0_sel_o : out std_logic_vector(3 downto 0);
        s0_we_o  : out std_logic;
        s0_stb_o : out std_logic;
        s0_cyc_o : out std_logic;
        s0_ack_i : in  std_logic;

        -- Slave 1: Main SDRAM (0x8000_0000 - 0x87FF_FFFF)
        s1_adr_o : out std_logic_vector(31 downto 0);
        s1_dat_o : out std_logic_vector(31 downto 0);
        s1_dat_i : in  std_logic_vector(31 downto 0);
        s1_sel_o : out std_logic_vector(3 downto 0);
        s1_we_o  : out std_logic;
        s1_stb_o : out std_logic;
        s1_cyc_o : out std_logic;
        s1_ack_i : in  std_logic;

        -- Slave 2: VGA Framebuffer (0xC000_0000 - 0xC007_FFFF)
        s2_adr_o : out std_logic_vector(31 downto 0);
        s2_dat_o : out std_logic_vector(31 downto 0);
        s2_dat_i : in  std_logic_vector(31 downto 0);
        s2_sel_o : out std_logic_vector(3 downto 0);
        s2_we_o  : out std_logic;
        s2_stb_o : out std_logic;
        s2_cyc_o : out std_logic;
        s2_ack_i : in  std_logic;

        -- Slave 3: Peripheral Sub-bus Bridge (0xE000_0000 - 0xE000_FFFF)
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
    type slave_sel_t is (SEL_BRAM, SEL_SDRAM, SEL_VGA, SEL_PERIPH, SEL_NONE);
    signal active_slave : slave_sel_t;
begin

    -- Shared payload and address lines
    s0_adr_o <= m_adr_i; s0_dat_o <= m_dat_i; s0_sel_o <= m_sel_i; s0_we_o <= m_we_i;
    s1_adr_o <= m_adr_i; s1_dat_o <= m_dat_i; s1_sel_o <= m_sel_i; s1_we_o <= m_we_i;
    s2_adr_o <= m_adr_i; s2_dat_o <= m_dat_i; s2_sel_o <= m_sel_i; s2_we_o <= m_we_i;
    s3_adr_o <= m_adr_i; s3_dat_o <= m_dat_i; s3_sel_o <= m_sel_i; s3_we_o <= m_we_i;

    -- Target Address Decoding
    process(m_adr_i)
    begin
        if m_adr_i(31 downto 16) = x"0000" then
            active_slave <= SEL_BRAM;
        elsif m_adr_i(31 downto 27) = "10000" then         -- 0x8000_0000 - 0x87FF_FFFF (128 MB space)
            active_slave <= SEL_SDRAM;
        elsif m_adr_i(31 downto 19) = "1100000000000" then -- 0xC000_0000 - 0xC007_FFFF (512 KB space)
            active_slave <= SEL_VGA;
        elsif m_adr_i(31 downto 16) = x"E000" then         -- 0xE000_0000 - 0xE000_FFFF (64 KB space)
            active_slave <= SEL_PERIPH;
        else
            active_slave <= SEL_NONE;
        end if;
    end process;

    -- Qualified Wishbone Control Signal Routing (Gated CYC and STB)
    s0_cyc_o <= m_cyc_i when (active_slave = SEL_BRAM)   else '0';
    s0_stb_o <= m_stb_i when (active_slave = SEL_BRAM)   else '0';

    s1_cyc_o <= m_cyc_i when (active_slave = SEL_SDRAM)  else '0';
    s1_stb_o <= m_stb_i when (active_slave = SEL_SDRAM)  else '0';

    s2_cyc_o <= m_cyc_i when (active_slave = SEL_VGA)    else '0';
    s2_stb_o <= m_stb_i when (active_slave = SEL_VGA)    else '0';

    s3_cyc_o <= m_cyc_i when (active_slave = SEL_PERIPH) else '0';
    s3_stb_o <= m_stb_i when (active_slave = SEL_PERIPH) else '0';

    -- Return Channel Multiplexer
    process(active_slave, s0_dat_i, s0_ack_i, s1_dat_i, s1_ack_i, 
            s2_dat_i, s2_ack_i, s3_dat_i, s3_ack_i)
    begin
        case active_slave is
            when SEL_BRAM =>
                m_dat_o <= s0_dat_i;
                m_ack_o <= s0_ack_i;
            when SEL_SDRAM =>
                m_dat_o <= s1_dat_i;
                m_ack_o <= s1_ack_i;
            when SEL_VGA =>
                m_dat_o <= s2_dat_i;
                m_ack_o <= s2_ack_i;
            when SEL_PERIPH =>
                m_dat_o <= s3_dat_i;
                m_ack_o <= s3_ack_i;
            when others =>
                m_dat_o <= (others => '0');
                m_ack_o <= '0';
        end case;
    end process;

end architecture rtl;