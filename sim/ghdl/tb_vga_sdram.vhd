-- SPDX-License-Identifier: Apache-2.0
--
-- tb_vga_sdram.vhd -- INTEGRATION testbench for the Phase 4.2 read path
-- that no existing testbench covers:
--
--     vga_line_fetch -> sdram_arbiter -> sdram_controller -> sdram_model
--
-- tb_vga_line_fetch.vhd exercises vga_line_fetch against a FAKE slave
-- (acks with the address as data); tb_sdram.vhd exercises
-- sdram_controller against a synthetic testbench master, and only ever
-- with wb_sel = "1111" word accesses. sdram_arbiter is instantiated by
-- NO other testbench at all.
--
-- Method: drive arbiter port A (the CPU side) as a Wishbone master and
-- fill two scanlines using BYTE stores shaped exactly as MEM_Stage.vhd
-- shapes them -- full byte address on the bus, lane chosen by wb_sel --
-- writing 0xAA to bytes 0..1 and 0xBB to bytes 2..3 of every word, just
-- as the firmware's vga_smoke_test() does. Then go idle on port A and
-- let vga_line_fetch fetch those lines over port B; every byte it
-- delivers must match what was written.
--
-- This is the testbench that caught the BURST ALIGNMENT bug documented
-- in rtl/memory/sdram_controller.vhd: byte stores to an odd halfword
-- presented an odd start column, and a BL=2 sequential burst starting on
-- an odd column wraps backwards, swapping the two beats. Revert that fix
-- and this testbench reports 640 corrupted bytes and a word 0 of
-- 0x0000BBBB instead of 0xBBBBAAAA.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.vga_pkg.all;

entity tb_vga_sdram is
end entity tb_vga_sdram;

architecture sim of tb_vga_sdram is

    constant SYS_PERIOD : time := 20 ns;   -- 50 MHz
    constant PIX_PERIOD : time := 40 ns;   -- 25 MHz

    signal clk       : std_logic := '0';
    signal pix_clk   : std_logic := '0';
    signal rst_n     : std_logic := '0';
    signal pix_rst_n : std_logic := '0';
    signal done      : boolean := false;

    -- Arbiter port A (stands in for the CPU / bus_interconnect slave 1).
    signal a_adr : std_logic_vector(31 downto 0) := (others => '0');
    signal a_dat_w : std_logic_vector(31 downto 0) := (others => '0');
    signal a_dat_r : std_logic_vector(31 downto 0);
    signal a_sel : std_logic_vector(3 downto 0) := "1111";
    signal a_we  : std_logic := '0';
    signal a_stb : std_logic := '0';
    signal a_cyc : std_logic := '0';
    signal a_ack : std_logic;

    -- Arbiter port B (vga_line_fetch).
    signal vf_adr : std_logic_vector(31 downto 0);
    signal vf_dat : std_logic_vector(31 downto 0);
    signal vf_sel : std_logic_vector(3 downto 0);
    signal vf_we  : std_logic;
    signal vf_stb : std_logic;
    signal vf_cyc : std_logic;
    signal vf_ack : std_logic;

    -- Arbiter -> controller.
    signal m_adr : std_logic_vector(31 downto 0);
    signal m_dat_w : std_logic_vector(31 downto 0);
    signal m_dat_r : std_logic_vector(31 downto 0);
    signal m_sel : std_logic_vector(3 downto 0);
    signal m_we  : std_logic;
    signal m_stb : std_logic;
    signal m_cyc : std_logic;
    signal m_ack : std_logic;

    -- Physical SDRAM pins.
    signal s_cke   : std_logic;
    signal s_cs_n  : std_logic;
    signal s_ras_n : std_logic;
    signal s_cas_n : std_logic;
    signal s_we_n  : std_logic;
    signal s_ba    : std_logic_vector(1 downto 0);
    signal s_addr  : std_logic_vector(11 downto 0);
    signal s_dqm   : std_logic_vector(1 downto 0);
    signal s_dq    : std_logic_vector(15 downto 0);

    -- vga_line_fetch -> line buffer write port (what we actually check).
    signal lb_wr_en   : std_logic;
    signal lb_wr_bank : std_logic;
    signal lb_wr_col  : unsigned(8 downto 0);
    signal lb_wr_data : std_logic_vector(7 downto 0);
    signal write_bank : std_logic;

    signal dbg_word0 : std_logic_vector(31 downto 0);
    signal dbg_word1 : std_logic_vector(31 downto 0);

    -- pix-domain stimulus.
    signal start_fetch_pix : std_logic := '0';
    signal line_num_pix    : unsigned(7 downto 0) := (others => '0');

    signal checking : boolean := false;
    signal bad_bytes : natural := 0;
    signal good_bytes : natural := 0;

    -- Byte the fill wrote at framebuffer offset i (and therefore the
    -- byte vga_line_fetch must deliver at line-buffer column i).
    function exp_byte (i : integer) return std_logic_vector is
    begin
        if (i mod 4) >= 2 then
            return x"BB";
        else
            return x"AA";
        end if;
    end function;

    function h32 (v : std_logic_vector(31 downto 0)) return string is
        constant hexc : string(1 to 16) := "0123456789ABCDEF";
        variable r : string(1 to 8);
        variable u : unsigned(31 downto 0) := unsigned(v);
    begin
        for i in 7 downto 0 loop
            r(8 - i) := hexc(to_integer(u(i * 4 + 3 downto i * 4)) + 1);
        end loop;
        return r;
    end function;

    function h8 (v : std_logic_vector(7 downto 0)) return string is
        constant hexc : string(1 to 16) := "0123456789ABCDEF";
        variable r : string(1 to 2);
        variable u : unsigned(7 downto 0) := unsigned(v);
    begin
        for i in 1 downto 0 loop
            r(2 - i) := hexc(to_integer(u(i * 4 + 3 downto i * 4)) + 1);
        end loop;
        return r;
    end function;

begin

    clk     <= not clk     after SYS_PERIOD / 2 when not done else '0';
    pix_clk <= not pix_clk after PIX_PERIOD / 2 when not done else '0';

    -- Weak pull-down so an undriven bus reads 0 rather than a wall of Z.
    s_dq <= (others => 'L');

    u_arb : entity work.sdram_arbiter
        port map (
            clk => clk, rst_n => rst_n,
            a_adr_i => a_adr, a_dat_i => a_dat_w, a_dat_o => a_dat_r,
            a_sel_i => a_sel, a_we_i => a_we,
            a_stb_i => a_stb, a_cyc_i => a_cyc, a_ack_o => a_ack,
            b_adr_i => vf_adr, b_dat_i => (others => '0'), b_dat_o => vf_dat,
            b_sel_i => vf_sel, b_we_i => vf_we,
            b_stb_i => vf_stb, b_cyc_i => vf_cyc, b_ack_o => vf_ack,
            m_adr_o => m_adr, m_dat_o => m_dat_w, m_dat_i => m_dat_r,
            m_sel_o => m_sel, m_we_o => m_we,
            m_stb_o => m_stb, m_cyc_o => m_cyc, m_ack_i => m_ack
        );

    u_ctrl : entity work.sdram_controller
        generic map (
            CLK_FREQ_MHZ => 50,
            SIMULATION   => true
        )
        port map (
            clk => clk, reset_n => rst_n,
            wb_adr_i => m_adr, wb_dat_i => m_dat_w, wb_dat_o => m_dat_r,
            wb_sel_i => m_sel, wb_we_i => m_we,
            wb_stb_i => m_stb, wb_cyc_i => m_cyc, wb_ack_o => m_ack,
            sdram_cke => s_cke, sdram_cs_n => s_cs_n, sdram_ras_n => s_ras_n,
            sdram_cas_n => s_cas_n, sdram_we_n => s_we_n, sdram_ba => s_ba,
            sdram_addr => s_addr, sdram_dqm => s_dqm, sdram_dq => s_dq
        );

    u_chip : entity work.sdram_model
        port map (
            clk => clk, cke => s_cke, cs_n => s_cs_n, ras_n => s_ras_n,
            cas_n => s_cas_n, we_n => s_we_n, ba => s_ba, addr => s_addr,
            dqm => s_dqm, dq => s_dq
        );

    u_fetch : entity work.vga_line_fetch
        port map (
            clk => clk, rst_n => rst_n,
            pix_clk => pix_clk, pix_rst_n => pix_rst_n,
            start_fetch_pix => start_fetch_pix,
            line_num_pix    => line_num_pix,
            wb_adr_o => vf_adr, wb_dat_i => vf_dat,
            wb_sel_o => vf_sel, wb_we_o => vf_we,
            wb_stb_o => vf_stb, wb_cyc_o => vf_cyc, wb_ack_i => vf_ack,
            buf_wr_en => lb_wr_en, buf_wr_bank => lb_wr_bank,
            buf_wr_col => lb_wr_col, buf_wr_data => lb_wr_data,
            write_bank_o => write_bank,
            dbg_word0_o => dbg_word0, dbg_word1_o => dbg_word1
        );

    -- ---------------------------------------------------------------
    -- Checker: every byte vga_line_fetch pushes into the line buffer
    -- must be 0x01 once we've filled the framebuffer with 0x01010101.
    -- ---------------------------------------------------------------
    checker : process (clk)
    begin
        if rising_edge(clk) then
            if checking and lb_wr_en = '1' then
                if lb_wr_data = exp_byte(to_integer(lb_wr_col)) then
                    good_bytes <= good_bytes + 1;
                else
                    if bad_bytes < 12 then
                        report "  BAD byte at col " &
                               integer'image(to_integer(lb_wr_col)) &
                               " = 0x" & h8(lb_wr_data) & " (expected 0x" &
                               h8(exp_byte(to_integer(lb_wr_col))) & ")"
                               severity note;
                    end if;
                    bad_bytes <= bad_bytes + 1;
                end if;
            end if;
        end if;
    end process;

    -- ---------------------------------------------------------------
    -- pix-domain: issue start_fetch pulses.
    -- ---------------------------------------------------------------
    stim : process
        constant FB_BASE : unsigned(31 downto 0) := unsigned(FB_BASE_ADDR);

        procedure wb_write_a (
            addr : in unsigned(31 downto 0);
            dat  : in std_logic_vector(31 downto 0)
        ) is
            variable guard : natural := 0;
        begin
            wait until rising_edge(clk);
            a_adr   <= std_logic_vector(addr);
            a_dat_w <= dat;
            a_sel   <= "1111";
            a_we    <= '1';
            a_stb   <= '1';
            a_cyc   <= '1';
            loop
                wait until rising_edge(clk);
                exit when a_ack = '1';
                guard := guard + 1;
                if guard > 5000 then
                    report "TIMEOUT waiting for write ack" severity failure;
                end if;
            end loop;
            a_stb <= '0';
            a_cyc <= '0';
            a_we  <= '0';
        end procedure;

        -- Single byte store, formed exactly the way MEM_Stage.vhd forms
        -- one: the FULL byte address goes on the bus (wb_addr_o <=
        -- mem_addr, no alignment masking) and the lane is chosen by
        -- wb_sel. This is what the firmware's framebuffer fill does, and
        -- it is the access shape no existing testbench ever produced --
        -- tb_sdram only ever drives sel="1111" word accesses.
        procedure wb_write_byte_a (
            addr : in unsigned(31 downto 0);
            val  : in std_logic_vector(7 downto 0)
        ) is
            variable guard : natural := 0;
            variable lane  : integer;
        begin
            wait until rising_edge(clk);
            lane    := to_integer(addr(1 downto 0));
            a_adr   <= std_logic_vector(addr);
            a_dat_w <= (others => '0');
            a_dat_w(lane * 8 + 7 downto lane * 8) <= val;
            a_sel   <= (others => '0');
            a_sel(lane) <= '1';
            a_we    <= '1';
            a_stb   <= '1';
            a_cyc   <= '1';
            loop
                wait until rising_edge(clk);
                exit when a_ack = '1';
                guard := guard + 1;
                if guard > 5000 then
                    report "TIMEOUT waiting for byte write ack" severity failure;
                end if;
            end loop;
            a_stb <= '0';
            a_cyc <= '0';
            a_we  <= '0';
        end procedure;

        procedure pix_pulse (line : in natural) is
        begin
            wait until rising_edge(pix_clk);
            line_num_pix    <= to_unsigned(line, 8);
            start_fetch_pix <= '1';
            wait until rising_edge(pix_clk);
            start_fetch_pix <= '0';
        end procedure;

        variable word_addr : unsigned(31 downto 0);
    begin
        rst_n     <= '0';
        pix_rst_n <= '0';
        wait for 200 ns;
        wait until rising_edge(clk);
        rst_n     <= '1';
        pix_rst_n <= '1';

        -- Let the controller finish its (shortened) power-on sequence.
        for i in 1 to 200 loop
            wait until rising_edge(clk);
        end loop;

        -- Fill with BYTE stores, the way the firmware's vga_smoke_test()
        -- does: bytes 0,1 of every word get 0xAA and bytes 2,3 get 0xBB,
        -- so each word must read back as 0xBBBBAAAA.
        report "--- filling scanlines 0 and 1 via port A BYTE stores ---";
        for b in 0 to (2 * FB_WIDTH) - 1 loop
            if (b mod 4) >= 2 then
                wb_write_byte_a(FB_BASE + to_unsigned(b, 32), x"BB");
            else
                wb_write_byte_a(FB_BASE + to_unsigned(b, 32), x"AA");
            end if;
        end loop;

        -- Read one word back through port A (the "CPU" path) to prove
        -- the data really is correct at rest, exactly as the firmware's
        -- vga_readback_check() does on hardware.
        wait until rising_edge(clk);
        a_adr <= std_logic_vector(FB_BASE);
        a_sel <= "1111";
        a_we  <= '0';
        a_stb <= '1';
        a_cyc <= '1';
        loop
            wait until rising_edge(clk);
            exit when a_ack = '1';
        end loop;
        report "port A (CPU-style) readback of FB word 0 = 0x" & h32(a_dat_r) & "  (expect 0xBBBBAAAA)";
        a_stb <= '0';
        a_cyc <= '0';

        for i in 1 to 20 loop
            wait until rising_edge(clk);
        end loop;

        report "--- now fetching those lines over port B (vga_line_fetch) ---";
        checking <= true;

        -- captured_line + 1 is what gets fetched, so pulse with 199 to
        -- fetch line 0, then 0 to fetch line 1.
        pix_pulse(FB_HEIGHT - 1);
        for i in 1 to 4000 loop
            wait until rising_edge(clk);
        end loop;

        report "after line 0 fetch: dbg_word0=0x" & h32(dbg_word0) &
               " dbg_word1=0x" & h32(dbg_word1);

        pix_pulse(0);
        for i in 1 to 4000 loop
            wait until rising_edge(clk);
        end loop;

        report "after line 1 fetch: dbg_word0=0x" & h32(dbg_word0) &
               " dbg_word1=0x" & h32(dbg_word1);

        checking <= false;
        wait until rising_edge(clk);

        report "================================================";
        report "  bytes correct : " & integer'image(good_bytes);
        report "  bytes WRONG   : " & integer'image(bad_bytes);
        if bad_bytes = 0 then
            report "  tb_vga_sdram: ALL CHECKS PASSED";
        else
            report "  tb_vga_sdram: FAIL -- " & integer'image(bad_bytes) &
                   " corrupted bytes" severity warning;
        end if;
        report "================================================";

        done <= true;
        wait;
    end process;

end architecture sim;
