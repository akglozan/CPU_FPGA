-- SDRAM controller bring-up testbench.
--
-- Drives sdram_controller's Wishbone slave port directly, with
-- sim/sdram_model.vhd standing in for the physical chip. This is the
-- first time either has been exercised: the firmware only ever touches
-- BRAM (0x0000_0000) and the peripheral bridge (0xE000_0000), so the
-- whole 0x8000_0000 path has never run.
--
-- Every access is bounded by a timeout. That matters here: neither
-- bus_interconnect nor mem_stage has a watchdog, so on hardware a
-- controller that fails to ack freezes the CPU permanently with no
-- diagnostic -- the same silent-hang signature as the reset bug. In
-- simulation we turn that into a reported failure instead.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_sdram is
    generic (
        -- Cycles to wait for an ack before declaring the bus hung.
        ack_timeout : natural := 2000
    );
end entity tb_sdram;

architecture sim of tb_sdram is

    signal clk     : std_logic := '0';
    signal reset_n : std_logic := '0';

    signal wb_adr : std_logic_vector(31 downto 0) := (others => '0');
    signal wb_dat_w : std_logic_vector(31 downto 0) := (others => '0');
    signal wb_dat_r : std_logic_vector(31 downto 0);
    signal wb_sel : std_logic_vector(3 downto 0) := "1111";
    signal wb_we  : std_logic := '0';
    signal wb_stb : std_logic := '0';
    signal wb_cyc : std_logic := '0';
    signal wb_ack : std_logic;

    signal s_cke   : std_logic;
    signal s_cs_n  : std_logic;
    signal s_ras_n : std_logic;
    signal s_cas_n : std_logic;
    signal s_we_n  : std_logic;
    signal s_ba    : std_logic_vector(1 downto 0);
    signal s_addr  : std_logic_vector(11 downto 0);
    signal s_dqm   : std_logic_vector(1 downto 0);
    signal s_dq    : std_logic_vector(15 downto 0);

    signal done  : boolean := false;
    signal fails : natural := 0;

    type addr_arr is array (natural range <>) of std_logic_vector(31 downto 0);
    -- Four consecutive words, the shape a CPU produces when it walks an
    -- array. This is what holds cyc/stb high across transaction
    -- boundaries and squeezes the gap between PRECHARGE and the next
    -- ACTIVE down to its minimum.
    constant B2B : addr_arr(0 to 3) := (x"80000000", x"80000004",
                                        x"80000008", x"8000000C");

    function h (v : std_logic_vector(31 downto 0)) return string is
        constant hexc : string(1 to 16) := "0123456789ABCDEF";
        variable r : string(1 to 8);
        variable u : unsigned(31 downto 0) := unsigned(v);
    begin
        for i in 7 downto 0 loop
            r(8 - i) := hexc(to_integer(u(i * 4 + 3 downto i * 4)) + 1);
        end loop;
        return r;
    end function;

begin

    clk <= not clk after 10 ns when not done else '0';

    -- Pull-down so an undriven bus reads as 0 rather than 'Z', keeping
    -- the failure message readable instead of a wall of U/Z.
    s_dq <= (others => 'L');

    dut : entity work.sdram_controller
        generic map (
            CLK_FREQ_MHZ => 50,
            SIMULATION   => true     -- short boot wait
        )
        port map (
            clk => clk, reset_n => reset_n,
            wb_adr_i => wb_adr, wb_dat_i => wb_dat_w, wb_dat_o => wb_dat_r,
            wb_sel_i => wb_sel, wb_we_i => wb_we,
            wb_stb_i => wb_stb, wb_cyc_i => wb_cyc, wb_ack_o => wb_ack,
            sdram_cke => s_cke, sdram_cs_n => s_cs_n, sdram_ras_n => s_ras_n,
            sdram_cas_n => s_cas_n, sdram_we_n => s_we_n, sdram_ba => s_ba,
            sdram_addr => s_addr, sdram_dqm => s_dqm, sdram_dq => s_dq
        );

    chip : entity work.sdram_model
        port map (
            clk => clk, cke => s_cke, cs_n => s_cs_n, ras_n => s_ras_n,
            cas_n => s_cas_n, we_n => s_we_n, ba => s_ba, addr => s_addr,
            dqm => s_dqm, dq => s_dq
        );

    stim : process
        variable cyc : natural;
        variable got : std_logic_vector(31 downto 0);
        variable hung : boolean;

        procedure wb_xfer (
            addr    : std_logic_vector(31 downto 0);
            wdata   : std_logic_vector(31 downto 0);
            is_write: boolean;
            rdata   : out std_logic_vector(31 downto 0);
            timedout: out boolean
        ) is
        begin
            wait until rising_edge(clk);
            wb_adr   <= addr;
            wb_dat_w <= wdata;
            wb_sel   <= "1111";
            wb_we    <= '1' when is_write else '0';
            wb_stb   <= '1';
            wb_cyc   <= '1';

            cyc := 0;
            timedout := false;
            loop
                wait until rising_edge(clk);
                exit when wb_ack = '1';
                cyc := cyc + 1;
                if cyc > ack_timeout then
                    timedout := true;
                    exit;
                end if;
            end loop;

            rdata := wb_dat_r;

            wb_stb <= '0';
            wb_cyc <= '0';
            wb_we  <= '0';
            wait until rising_edge(clk);
        end procedure;

        procedure wr (addr, data : std_logic_vector(31 downto 0)) is
            variable dummy : std_logic_vector(31 downto 0);
        begin
            wb_xfer(addr, data, true, dummy, hung);
            if hung then
                fails <= fails + 1;
                report "FAIL  write 0x" & h(addr) & " never acked (bus hung)"
                       severity warning;
            else
                report "      write 0x" & h(addr) & " = 0x" & h(data) &
                       "  (" & integer'image(cyc) & " cycles)";
            end if;
        end procedure;

        procedure rd_check (addr, expect : std_logic_vector(31 downto 0)) is
        begin
            wb_xfer(addr, (31 downto 0 => '0'), false, got, hung);
            if hung then
                fails <= fails + 1;
                report "FAIL  read 0x" & h(addr) & " never acked (bus hung)"
                       severity warning;
            elsif got = expect then
                report "PASS  read 0x" & h(addr) & " = 0x" & h(got) &
                       "  (" & integer'image(cyc) & " cycles)";
            else
                fails <= fails + 1;
                report "FAIL  read 0x" & h(addr) & " = 0x" & h(got) &
                       ", expected 0x" & h(expect)
                       severity warning;
            end if;
        end procedure;
    begin
        reset_n <= '0';
        wait for 200 ns;
        wait until rising_edge(clk);
        reset_n <= '1';

        -- Let the power-on init sequence finish (precharge, 2x refresh,
        -- load mode register). SIMULATION => true shortens the boot wait.
        for i in 1 to 200 loop
            wait until rising_edge(clk);
        end loop;

        report "--- single write then read back ---";
        wr      (x"80000000", x"DEADBEEF");
        rd_check(x"80000000", x"DEADBEEF");

        report "--- second word, then re-read the first ---";
        -- If consecutive 32-bit words overlap in the chip's address map,
        -- writing the second corrupts the first. Re-reading 0x...00 after
        -- writing 0x...04 is what catches that.
        wr      (x"80000004", x"CAFEBABE");
        rd_check(x"80000004", x"CAFEBABE");
        rd_check(x"80000000", x"DEADBEEF");

        report "--- third word, then re-read all three ---";
        wr      (x"80000008", x"12345678");
        rd_check(x"80000000", x"DEADBEEF");
        rd_check(x"80000004", x"CAFEBABE");
        rd_check(x"80000008", x"12345678");

        report "--- a different row and bank ---";
        wr      (x"80001000", x"A5A5A5A5");
        wr      (x"80400000", x"5A5A5A5A");
        rd_check(x"80001000", x"A5A5A5A5");
        rd_check(x"80400000", x"5A5A5A5A");
        rd_check(x"80000000", x"DEADBEEF");

        report "--- back-to-back reads, bus never released ---";
        -- A gap-free request stream: the moment one access acks, the next
        -- address is already on the bus with stb still high, so ST_IDLE
        -- re-arms immediately after ST_PRECHARGE.
        wr(x"8000000C", x"0F0F0F0F");
        wait until rising_edge(clk);
        wb_sel <= "1111";
        wb_we  <= '0';
        wb_cyc <= '1';
        wb_stb <= '1';
        for i in B2B'range loop
            wb_adr <= B2B(i);
            cyc := 0;
            loop
                wait until rising_edge(clk);
                exit when wb_ack = '1';
                cyc := cyc + 1;
                if cyc > ack_timeout then
                    fails <= fails + 1;
                    report "FAIL  back-to-back access " & integer'image(i) &
                           " never acked" severity warning;
                    exit;
                end if;
            end loop;
            report "      back-to-back read 0x" & h(B2B(i)) &
                   " = 0x" & h(wb_dat_r) & "  (" & integer'image(cyc) & " cycles)";
        end loop;
        wb_stb <= '0';
        wb_cyc <= '0';

        report "--- request already pending when boot finishes (tMRD) ---";
        -- Hold a request asserted across reset so it is waiting the
        -- instant the FSM reaches ST_IDLE after LOAD MODE REGISTER.
        wb_adr <= x"80000000";
        wb_we  <= '0';
        wb_sel <= "1111";
        reset_n <= '0';
        wait for 200 ns;
        wait until rising_edge(clk);
        reset_n <= '1';
        wb_cyc <= '1';
        wb_stb <= '1';
        cyc := 0;
        loop
            wait until rising_edge(clk);
            exit when wb_ack = '1';
            cyc := cyc + 1;
            if cyc > ack_timeout then
                fails <= fails + 1;
                report "FAIL  post-boot access never acked" severity warning;
                exit;
            end if;
        end loop;
        got := wb_dat_r;
        wb_stb <= '0';
        wb_cyc <= '0';
        if got = x"DEADBEEF" then
            report "PASS  post-boot read 0x80000000 = 0x" & h(got) &
                   "  (" & integer'image(cyc) & " cycles)";
        else
            fails <= fails + 1;
            report "FAIL  post-boot read 0x80000000 = 0x" & h(got) &
                   ", expected 0xDEADBEEF" severity warning;
        end if;

        report "================ FAILURES: " & integer'image(fails) &
               " ================";
        done <= true;
        wait for 100 ns;
        std.env.stop;
    end process;

end architecture sim;
