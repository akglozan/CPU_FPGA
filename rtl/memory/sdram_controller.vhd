-- SPDX-License-Identifier: Apache-2.0
-- Copyright 2026 Ozan Akgul
--
-- NOTE ON READ TIMING: wait_cnt in ST_READ_CMD is 1, and that is
-- correct -- do not "fix" it to 2. CAS latency 2 is satisfied because
-- the command outputs are registered, so the READ reaches the chip one
-- cycle after the ST_READ_CMD state. Verified end to end by
-- sim/ghdl/tb_sdram.vhd against sim/sdram_model.vhd.

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

-- SDRAM controller for a 16-bit-wide SDR SDRAM chip, exposed as a
-- Wishbone B4 slave. Handles the power-on init sequence (precharge
-- all banks, two auto-refresh cycles, mode register load: sequential
-- burst, BL=2, CAS=2), periodic auto-refresh, and single-word
-- transactions -- each 32-bit CPU word is split across two 16-bit
-- SDRAM beats (burst length 2). Only one row is ever open at a time:
-- every transaction precharges the row it used before returning to
-- ST_IDLE, trading peak throughput for a much simpler FSM.
entity sdram_controller is
    generic (
        CLK_FREQ_MHZ : integer := 50;   -- System Clock Frequency in MHz
        SIMULATION   : boolean := false -- Set to true for fast simulation boot
    );
    port (
        clk           : in    std_logic;
        -- Active-low asynchronous reset.
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
        -- Clock enable; tied permanently high.
        sdram_cke     : out   std_logic;
        -- Chip select, active low (part of the 4-bit command bus).
        sdram_cs_n    : out   std_logic;
        -- Row address strobe, active low (part of the command bus).
        sdram_ras_n   : out   std_logic;
        -- Column address strobe, active low (part of the command bus).
        sdram_cas_n   : out   std_logic;
        -- Write enable, active low (part of the command bus).
        sdram_we_n    : out   std_logic;
        -- Bank address select.
        sdram_ba      : out   std_logic_vector(1 downto 0);
        -- Multiplexed row/column address bus.
        sdram_addr    : out   std_logic_vector(11 downto 0);
        -- Data mask, one bit per byte lane of the 16-bit data bus.
        sdram_dqm     : out   std_logic_vector(1 downto 0);
        -- Bidirectional 16-bit SDRAM data bus.
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
        ST_IDLE, ST_ACTIVE, ST_READ_CMD, ST_READ_WAIT, ST_READ_DATA, ST_READ_DATA2,
        ST_WRITE_CMD, ST_WRITE_DATA2, ST_WRITE_REC, ST_PRECHARGE, ST_REFRESH
    );
    signal state : state_t := ST_BOOT_WAIT;

    -- Refresh timer: 64ms / 4096 rows = 15.625 us -> ~780 cycles @ 50MHz
    constant REFRESH_PERIOD : integer := (CLK_FREQ_MHZ * 15);
    signal refresh_cnt      : integer range 0 to REFRESH_PERIOD := 0;
    signal refresh_req      : std_logic := '0';

    -- General Delay / Wait Counter (Expanded range to prevent overflow)
    signal wait_cnt         : integer range 0 to 65535 := 0;

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
            wb_ack_o   <= '0';
            dq_oe      <= '0';
            sdram_ba   <= "00";
            sdram_addr <= (others => '0');
            sdram_dqm  <= "11";
            send_cmd(CMD_NOP);
            if SIMULATION then
                wait_cnt <= 10;
            else
                wait_cnt <= CLK_FREQ_MHZ * 150;
            end if;
        elsif rising_edge(clk) then
            send_cmd(CMD_NOP); -- Default command to avoid latching control pulses
            wb_ack_o <= '0';   -- Single-cycle ACK clear default

            case state is
                ----------------------------------------------------------------
                -- Power-On Initialization Sequence
                ----------------------------------------------------------------
                when ST_BOOT_WAIT =>
                    if wait_cnt = 0 then
                        state <= ST_BOOT_PRECHARGE;
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
                    -- Honour any delay the previous state asked for.
                    -- ST_PRECHARGE (tRP) and ST_BOOT_LMR (tMRD) both set
                    -- wait_cnt and then fell straight through to here,
                    -- where nothing consumed it -- so both delays were
                    -- silently skipped. At 50 MHz tRP still happened to
                    -- be met by the one cycle the state transition
                    -- provides, but tMRD (2 clocks, specified in clocks
                    -- rather than nanoseconds) was not: a request already
                    -- pending when boot finished issued ACTIVE one clock
                    -- after LOAD MODE REGISTER. Confirmed by the timing
                    -- assertions in sim/sdram_model.vhd.
                    if wait_cnt /= 0 then
                        wait_cnt <= wait_cnt - 1;
                    elsif refresh_req = '1' then
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
                    sdram_addr     <= "000" & latched_adr(9 downto 1); -- Fixed 16-bit word alignment
                    sdram_dqm      <= "00";
                    wait_cnt       <= 1; -- CAS-1 cycles (RESTORED to original value)
                    state          <= ST_READ_WAIT;

                when ST_READ_WAIT =>
                    if wait_cnt = 0 then
                        state <= ST_READ_DATA;
                    else
                        wait_cnt <= wait_cnt - 1;
                    end if;

                when ST_READ_DATA =>
                    rdata_reg(15 downto 0) <= sdram_dq;
                    state                  <= ST_READ_DATA2;

                when ST_READ_DATA2 =>
                    rdata_reg(31 downto 16) <= sdram_dq;
                    wb_ack_o                <= '1';
                    state                   <= ST_PRECHARGE;

                ----------------------------------------------------------------
                -- Write Sequence (BL = 2)
                ----------------------------------------------------------------
                when ST_WRITE_CMD =>
                    send_cmd(CMD_WRITE);
                    sdram_ba       <= latched_adr(23 downto 22);
                    sdram_addr     <= "000" & latched_adr(9 downto 1); -- Fixed 16-bit word alignment
                    sdram_dqm      <= not latched_sel(1 downto 0);
                    dq_out         <= latched_wdata(15 downto 0);
                    dq_oe          <= '1';
                    state          <= ST_WRITE_DATA2;

                when ST_WRITE_DATA2 =>
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
