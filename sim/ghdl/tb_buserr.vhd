-- bus_interconnect watchdog testbench.
--
-- Proves that a slave which never acknowledges can no longer wedge the
-- CPU. Before the watchdog existed, mem_stage's bus_stall_o stayed high
-- forever and the pipeline froze with no outward sign -- indistinguishable
-- on the board from a dead CPU.
--
-- This is not hypothetical: slave 2 (VGA, 0xC000_0000) is hard-tied
-- s2_ack_i <= '0' in rv32im_soc.vhd, so any access there hangs. The
-- SDRAM slave is newly brought up and unproven on hardware.
--
-- TIMEOUT_CYCLES is overridden to something small so the test runs
-- quickly; the synthesised default is 65536 (~1.3 ms at 50 MHz), chosen
-- to clear the SDRAM controller's ~150 us power-on init.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_buserr is
    generic (
        TO_CK : natural := 32   -- watchdog limit under test
    );
end entity tb_buserr;

architecture sim of tb_buserr is

    signal clk   : std_logic := '0';
    signal rst_n : std_logic := '0';

    signal m_adr : std_logic_vector(31 downto 0) := (others => '0');
    signal m_dat_i : std_logic_vector(31 downto 0) := (others => '0');
    signal m_dat_o : std_logic_vector(31 downto 0);
    signal m_we  : std_logic := '0';
    signal m_sel : std_logic_vector(3 downto 0) := "1111";
    signal m_stb : std_logic := '0';
    signal m_cyc : std_logic := '0';
    signal m_ack : std_logic;
    signal bus_error : std_logic;

    -- Slave stubs. s0 (BRAM) and s3 (peripherals) acknowledge like the
    -- real ones; s1 (SDRAM) is deliberately mute to model a controller
    -- that has wedged; s2 (VGA) is tied low exactly as the SoC does.
    signal s0_stb, s0_cyc : std_logic;
    signal s1_stb, s1_cyc : std_logic;
    signal s2_stb, s2_cyc : std_logic;
    signal s3_stb, s3_cyc : std_logic;

    signal done  : boolean := false;
    signal fails : natural := 0;

begin

    clk <= not clk after 10 ns when not done else '0';

    dut : entity work.bus_interconnect
        generic map ( TIMEOUT_CYCLES => TO_CK )
        port map (
            clk => clk, rst_n => rst_n,
            m_adr_i => m_adr, m_dat_i => m_dat_i, m_dat_o => m_dat_o,
            m_we_i => m_we, m_sel_i => m_sel,
            m_stb_i => m_stb, m_cyc_i => m_cyc, m_ack_o => m_ack,
            bus_error_o => bus_error,

            s0_adr_o => open, s0_dat_o => open,
            s0_dat_i => x"11111111", s0_sel_o => open, s0_we_o => open,
            s0_stb_o => s0_stb, s0_cyc_o => s0_cyc,
            s0_ack_i => s0_stb,            -- BRAM-like: acks immediately

            s1_adr_o => open, s1_dat_o => open,
            s1_dat_i => x"22222222", s1_sel_o => open, s1_we_o => open,
            s1_stb_o => s1_stb, s1_cyc_o => s1_cyc,
            s1_ack_i => '0',               -- wedged SDRAM controller

            s2_adr_o => open, s2_dat_o => open,
            s2_dat_i => x"33333333", s2_sel_o => open, s2_we_o => open,
            s2_stb_o => s2_stb, s2_cyc_o => s2_cyc,
            s2_ack_i => '0',               -- VGA, as in rv32im_soc

            s3_adr_o => open, s3_dat_o => open,
            s3_dat_i => x"44444444", s3_sel_o => open, s3_we_o => open,
            s3_stb_o => s3_stb, s3_cyc_o => s3_cyc,
            s3_ack_i => s3_stb             -- periph_bridge-like
        );

    stim : process
        variable cyc : natural;

        procedure access_at (
            name      : string;
            addr      : std_logic_vector(31 downto 0);
            expect_to : boolean;                        -- expect a timeout?
            expect_dat: std_logic_vector(31 downto 0)
        ) is
        begin
            wait until rising_edge(clk);
            m_adr <= addr;
            m_stb <= '1';
            m_cyc <= '1';

            cyc := 0;
            loop
                wait until rising_edge(clk);
                exit when m_ack = '1';
                cyc := cyc + 1;
                if cyc > TO_CK * 4 then
                    fails <= fails + 1;
                    report "FAIL  " & name &
                           " -- never acked at all, watchdog did not fire"
                           severity warning;
                    exit;
                end if;
            end loop;

            if expect_to then
                -- Must have waited roughly the full watchdog interval and
                -- returned zeros rather than stale slave data.
                if cyc < TO_CK - 2 then
                    fails <= fails + 1;
                    report "FAIL  " & name & " acked after only " &
                           integer'image(cyc) & " cycles, expected ~" &
                           integer'image(TO_CK) severity warning;
                elsif m_dat_o /= x"00000000" then
                    fails <= fails + 1;
                    report "FAIL  " & name &
                           " timed out but returned non-zero data"
                           severity warning;
                else
                    report "PASS  " & name & " timed out after " &
                           integer'image(cyc) & " cycles, returned zero";
                end if;
            else
                if cyc > 2 then
                    fails <= fails + 1;
                    report "FAIL  " & name & " took " & integer'image(cyc) &
                           " cycles, expected an immediate ack"
                           severity warning;
                elsif m_dat_o /= expect_dat then
                    fails <= fails + 1;
                    report "FAIL  " & name & " returned wrong data"
                           severity warning;
                else
                    report "PASS  " & name & " acked in " &
                           integer'image(cyc) & " cycles";
                end if;
            end if;

            m_stb <= '0';
            m_cyc <= '0';
            wait until rising_edge(clk);
        end procedure;

        procedure check_err (name : string; expect : std_logic) is
        begin
            if bus_error = expect then
                report "PASS  " & name & " -- bus_error = " &
                       std_logic'image(expect);
            else
                fails <= fails + 1;
                report "FAIL  " & name & " -- bus_error = " &
                       std_logic'image(bus_error) & ", expected " &
                       std_logic'image(expect) severity warning;
            end if;
        end procedure;
    begin
        rst_n <= '0';
        wait for 100 ns;
        wait until rising_edge(clk);
        rst_n <= '1';
        wait until rising_edge(clk);

        report "--- healthy slaves are untouched by the watchdog ---";
        access_at("BRAM   0x00000000", x"00000000", false, x"11111111");
        access_at("periph 0xE0000000", x"E0000000", false, x"44444444");
        check_err("after healthy traffic", '0');

        report "--- unmapped address still self-acks (slave_none) ---";
        access_at("unmapped 0x40000000", x"40000000", false, x"00000000");
        check_err("after unmapped access", '0');

        report "--- VGA slave is tied low: must time out, not hang ---";
        access_at("VGA    0xC0000000", x"C0000000", true, x"00000000");
        check_err("after VGA timeout", '1');

        report "--- bus still usable afterwards, error stays sticky ---";
        access_at("BRAM   0x00000000", x"00000000", false, x"11111111");
        check_err("sticky after recovery", '1');

        report "--- wedged SDRAM slave also times out ---";
        access_at("SDRAM  0x80000000", x"80000000", true, x"00000000");

        report "================ FAILURES: " & integer'image(fails) &
               " ================";
        done <= true;
        wait for 100 ns;
        std.env.stop;
    end process;

end architecture sim;
