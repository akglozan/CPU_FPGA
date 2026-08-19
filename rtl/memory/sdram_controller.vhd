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

entity sdram_controller is
    generic (
        CLK_FREQ_MHZ : integer := 50 -- System Clock Frequency in MHz
    );
    port (
        clk           : in    std_logic;
        reset_n       : in    std_logic;

        -- Wishbone B4 Slave Interface
        wb_adr_i      : in    std_logic_vector(31 downto 0);
        wb_dat_i      : in    std_logic_vector(31 downto 0);
        wb_dat_o      : out   std_logic_vector(31 downto 0);
        wb_sel_i      : in    std_logic_vector(3 downto 0);
        wb_we_i       : in    std_logic;
        wb_stb_i      : in    std_logic;
        wb_cyc_i      : in    std_logic;
        wb_ack_o      : out   std_logic;

        -- Physical SDRAM Pins
        sdram_cke     : out   std_logic;
        sdram_cs_n    : out   std_logic;
        sdram_ras_n   : out   std_logic;
        sdram_cas_n   : out   std_logic;
        sdram_we_n    : out   std_logic;
        sdram_ba      : out   std_logic_vector(1 downto 0);
        sdram_addr    : out   std_logic_vector(11 downto 0);
        sdram_dqm     : out   std_logic_vector(1 downto 0);
        sdram_dq      : inout std_logic_vector(15 downto 0)
    );
end entity sdram_controller;

architecture rtl of sdram_controller is

    -- SDRAM Commands {CS_N, RAS_N, CAS_N, WE_N}
    constant CMD_NOP     : std_logic_vector(3 downto 0) := "0111";
    constant CMD_ACTIVE  : std_logic_vector(3 downto 0) := "0011";
    constant CMD_READ    : std_logic_vector(3 downto 0) := "0101";
    constant CMD_WRITE   : std_logic_vector(3 downto 0) := "0100";
    constant CMD_PRECHG  : std_logic_vector(3 downto 0) := "0010";
    constant CMD_REFRESH : std_logic_vector(3 downto 0) := "0001";
    constant CMD_LOAD_MR : std_logic_vector(3 downto 0) := "0000";

    type state_t is (
        ST_BOOT_WAIT, ST_BOOT_PRECHARGE, ST_BOOT_REF1, ST_BOOT_REF2, ST_BOOT_LMR,
        ST_IDLE, ST_ACTIVE, ST_READ_CMD, ST_READ_WAIT, ST_READ_DATA,
        ST_WRITE_CMD, ST_WRITE_DATA2, ST_WRITE_REC, ST_PRECHARGE, ST_REFRESH
    );
    signal state : state_t := ST_BOOT_WAIT;

    -- Refresh timer: 64ms / 4096 rows = 15.625 us -> ~780 cycles @ 50MHz
    constant REFRESH_PERIOD : integer := (CLK_FREQ_MHZ * 15);
    signal refresh_cnt      : integer range 0 to REFRESH_PERIOD := 0;
    signal refresh_req      : std_logic := '0';

    -- General Delay / Wait Counter
    signal wait_cnt         : integer range 0 to 10000 := 0;

    -- Internal Registers
    signal dq_out           : std_logic_vector(15 downto 0);
    signal dq_oe            : std_logic := '0';
    signal rdata_reg        : std_logic_vector(31 downto 0);
    signal latched_adr      : std_logic_vector(31 downto 0);
    signal latched_wdata    : std_logic_vector(31 downto 0);
    signal latched_sel      : std_logic_vector(3 downto 0);

begin

    sdram_cke <= '1';
    sdram_dq  <= dq_out when (dq_oe = '1') else (others => 'Z');
    wb_dat_o  <= rdata_reg;

    -- Refresh Request Generator
    process(clk, reset_n)
    begin
        if reset_n = '0' then
            refresh_cnt <= 0;
            refresh_req <= '0';
        elsif rising_edge(clk) then
            if refresh_cnt >= REFRESH_PERIOD then
                refresh_cnt <= 0;
                refresh_req <= '1';
            else
                refresh_cnt <= refresh_cnt + 1;
            end if;

            if state = ST_REFRESH then
                refresh_req <= '0';
            end if;
        end if;
    end process;

    -- Main Control FSM
    process(clk, reset_n)
        procedure send_cmd(cmd : in std_logic_vector(3 downto 0)) is
        begin
            sdram_cs_n  <= cmd(3);
            sdram_ras_n <= cmd(2);
            sdram_cas_n <= cmd(1);
            sdram_we_n  <= cmd(0);
        end procedure;
    begin
        if reset_n = '0' then
            state      <= ST_BOOT_WAIT;
            wait_cnt   <= CLK_FREQ_MHZ * 150; -- ~150us power-on delay
            wb_ack_o   <= '0';
            dq_oe      <= '0';
            send_cmd(CMD_NOP);
        elsif rising_edge(clk) then
            wb_ack_o <= '0';
            send_cmd(CMD_NOP);

            case state is
                ----------------------------------------------------------------
                -- Power-On Initialization Sequence
                ----------------------------------------------------------------
                when ST_BOOT_WAIT =>
                    send_cmd(CMD_NOP);
                    if wait_cnt = 0 then
                        state    <= ST_BOOT_PRECHARGE;
                    else
                        wait_cnt <= wait_cnt - 1;
                    end if;

                when ST_BOOT_PRECHARGE =>
                    send_cmd(CMD_PRECHG);
                    sdram_addr(10) <= '1'; -- All banks
                    wait_cnt <= 2;
                    state    <= ST_BOOT_REF1;

                when ST_BOOT_REF1 =>
                    if wait_cnt = 0 then
                        send_cmd(CMD_REFRESH);
                        wait_cnt <= 4;
                        state    <= ST_BOOT_REF2;
                    else
                        wait_cnt <= wait_cnt - 1;
                    end if;

                when ST_BOOT_REF2 =>
                    if wait_cnt = 0 then
                        send_cmd(CMD_REFRESH);
                        wait_cnt <= 4;
                        state    <= ST_BOOT_LMR;
                    else
                        wait_cnt <= wait_cnt - 1;
                    end if;

                when ST_BOOT_LMR =>
                    if wait_cnt = 0 then
                        send_cmd(CMD_LOAD_MR);
                        sdram_ba   <= "00";
                        -- Mode: Sequential, BL=2, CAS=2 (0x021)
                        sdram_addr <= "00" & '0' & "00" & "010" & '0' & "001";
                        wait_cnt   <= 2;
                        state      <= ST_IDLE;
                    else
                        wait_cnt <= wait_cnt - 1;
                    end if;

                ----------------------------------------------------------------
                -- Idle & Arbitration
                ----------------------------------------------------------------
                when ST_IDLE =>
                    dq_oe <= '0';
                    if refresh_req = '1' then
                        send_cmd(CMD_REFRESH);
                        wait_cnt <= 4;
                        state    <= ST_REFRESH;
                    elsif (wb_cyc_i = '1' and wb_stb_i = '1') then
                        latched_adr   <= wb_adr_i;
                        latched_wdata <= wb_dat_i;
                        latched_sel   <= wb_sel_i;
                        
                        -- Issue ACTIVE command
                        send_cmd(CMD_ACTIVE);
                        sdram_ba   <= wb_adr_i(23 downto 22); -- Bank
                        sdram_addr <= wb_adr_i(21 downto 10); -- Row
                        wait_cnt   <= 2;                      -- tRCD delay
                        state      <= ST_ACTIVE;
                    end if;

                when ST_REFRESH =>
                    if wait_cnt = 0 then
                        state <= ST_IDLE;
                    else
                        wait_cnt <= wait_cnt - 1;
                    end if;

                when ST_ACTIVE =>
                    if wait_cnt = 0 then
                        if wb_we_i = '1' then
                            state <= ST_WRITE_CMD;
                        else
                            state <= ST_READ_CMD;
                        end if;
                    else
                        wait_cnt <= wait_cnt - 1;
                    end if;

                ----------------------------------------------------------------
                -- Read Sequence (CAS Latency = 2, BL = 2)
                ----------------------------------------------------------------
                when ST_READ_CMD =>
                    send_cmd(CMD_READ);
                    sdram_ba       <= latched_adr(23 downto 22);
                    sdram_addr     <= "00" & latched_adr(9 downto 1) & '0'; -- 16-bit aligned col
                    sdram_dqm      <= "00";
                    wait_cnt       <= 1; -- CAS-1 cycles
                    state          <= ST_READ_WAIT;

                when ST_READ_WAIT =>
                    if wait_cnt = 0 then
                        state <= ST_READ_DATA;
                    else
                        wait_cnt <= wait_cnt - 1;
                    end if;

                when ST_READ_DATA =>
                    -- Latch lower word
                    rdata_reg(15 downto 0)  <= sdram_dq;
                    -- Next cycle receives upper word
                    state                   <= ST_PRECHARGE;
                    wb_ack_o                <= '1';
                    rdata_reg(31 downto 16) <= sdram_dq;

                ----------------------------------------------------------------
                -- Write Sequence (BL = 2)
                ----------------------------------------------------------------
                when ST_WRITE_CMD =>
                    send_cmd(CMD_WRITE);
                    sdram_ba       <= latched_adr(23 downto 22);
                    sdram_addr     <= "00" & latched_adr(9 downto 1) & '0';
                    sdram_dqm      <= not latched_sel(1 downto 0);
                    dq_out         <= latched_wdata(15 downto 0);
                    dq_oe          <= '1';
                    state          <= ST_WRITE_DATA2;

                when ST_WRITE_DATA2 =>
                    send_cmd(CMD_NOP);
                    sdram_dqm      <= not latched_sel(3 downto 2);
                    dq_out         <= latched_wdata(31 downto 16);
                    wait_cnt       <= 2; -- tWR recovery
                    state          <= ST_WRITE_REC;

                when ST_WRITE_REC =>
                    dq_oe <= '0';
                    if wait_cnt = 0 then
                        wb_ack_o <= '1';
                        state    <= ST_PRECHARGE;
                    else
                        wait_cnt <= wait_cnt - 1;
                    end if;

                ----------------------------------------------------------------
                -- Precharge & Close Row
                ----------------------------------------------------------------
                when ST_PRECHARGE =>
                    send_cmd(CMD_PRECHG);
                    sdram_addr(10) <= '1';
                    wait_cnt <= 2; -- tRP delay
                    state    <= ST_IDLE;

            end case;
        end if;
    end process;

end architecture rtl;