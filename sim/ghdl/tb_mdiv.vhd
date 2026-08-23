-- Unit test for M_Extension_Unit's divide path.
--
-- Sampling matches the real datapath exactly: EX_Stage feeds
-- ex_final_result into EX_MEM_Register, whose enable is
-- (stall_m or stall_ex_mem_in). So the value that actually reaches the
-- pipeline is m_result in the first cycle where stall_m is LOW after the
-- operation began. That is what this testbench captures.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_mdiv is
end entity tb_mdiv;

architecture sim of tb_mdiv is

    signal clk       : std_logic := '0';
    signal rst_n     : std_logic := '0';
    signal is_m_ext  : std_logic := '0';
    signal funct3    : std_logic_vector(2 downto 0) := "100";
    signal operand_a : std_logic_vector(31 downto 0) := (others => '0');
    signal operand_b : std_logic_vector(31 downto 0) := (others => '0');
    signal m_result  : std_logic_vector(31 downto 0);
    signal stall_m   : std_logic;

    signal done : boolean := false;
    signal fails : natural := 0;

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

    dut : entity work.M_Extension_Unit
        port map (
            clk => clk, rst_n => rst_n,
            is_m_ext => is_m_ext, funct3 => funct3,
            operand_a => operand_a, operand_b => operand_b,
            m_result => m_result, stall_m => stall_m
        );

    stim : process
        variable cycles : natural;
        variable got    : std_logic_vector(31 downto 0);

        procedure run (
            name : string;
            f3   : std_logic_vector(2 downto 0);
            a, b : std_logic_vector(31 downto 0);
            expect : std_logic_vector(31 downto 0)
        ) is
        begin
            -- present the operation
            wait until rising_edge(clk);
            funct3    <= f3;
            operand_a <= a;
            operand_b <= b;
            is_m_ext  <= '1';
            wait for 1 ns;

            -- wait for the unit to release the pipeline
            cycles := 0;
            while stall_m = '1' loop
                wait until rising_edge(clk);
                wait for 1 ns;
                cycles := cycles + 1;
                assert cycles < 200
                    report "timeout waiting for stall_m" severity failure;
            end loop;

            -- this is the cycle EX_MEM_Register latches
            got := m_result;

            if got = expect then
                report "PASS  " & name & "  = 0x" & h(got) &
                       "   (" & integer'image(cycles) & " stall cycles)";
            else
                fails <= fails + 1;
                report "FAIL  " & name & "  got 0x" & h(got) &
                       "  expected 0x" & h(expect) &
                       "   (" & integer'image(cycles) & " stall cycles)"
                       severity warning;
            end if;

            -- return to idle for a few cycles between tests
            is_m_ext <= '0';
            for i in 1 to 4 loop
                wait until rising_edge(clk);
            end loop;
        end procedure;
    begin
        rst_n <= '0';
        wait for 100 ns;
        wait until rising_edge(clk);
        rst_n <= '1';
        wait for 100 ns;

        report "--- unsigned (expected to already work) ---";
        run("divu  100 /  7 ", "101", x"00000064", x"00000007", x"0000000E");
        run("remu  100 %  7 ", "111", x"00000064", x"00000007", x"00000002");
        run("divu  -1u /  2 ", "101", x"FFFFFFFF", x"00000002", x"7FFFFFFF");

        report "--- signed, both positive (expected to already work) ---";
        run("div   100 /  7 ", "100", x"00000064", x"00000007", x"0000000E");
        run("rem   100 %  7 ", "110", x"00000064", x"00000007", x"00000002");

        report "--- signed, negative operands ---";
        run("div  -100 /  7 ", "100", x"FFFFFF9C", x"00000007", x"FFFFFFF2"); -- -14
        run("div   100 / -7 ", "100", x"00000064", x"FFFFFFF9", x"FFFFFFF2"); -- -14
        run("div  -100 / -7 ", "100", x"FFFFFF9C", x"FFFFFFF9", x"0000000E"); --  14
        run("rem  -100 %  7 ", "110", x"FFFFFF9C", x"00000007", x"FFFFFFFE"); --  -2
        run("rem   100 % -7 ", "110", x"00000064", x"FFFFFFF9", x"00000002"); --   2
        run("rem  -100 % -7 ", "110", x"FFFFFF9C", x"FFFFFFF9", x"FFFFFFFE"); --  -2

        report "--- divide by zero (spec: div=-1, divu=all ones, rem=dividend) ---";
        run("div   100 /  0 ", "100", x"00000064", x"00000000", x"FFFFFFFF");
        run("divu  100 /  0 ", "101", x"00000064", x"00000000", x"FFFFFFFF");
        run("rem   100 %  0 ", "110", x"00000064", x"00000000", x"00000064");
        run("remu  100 %  0 ", "111", x"00000064", x"00000000", x"00000064");

        report "--- signed overflow: INT_MIN / -1 (spec: div=INT_MIN, rem=0) ---";
        run("div  MIN  / -1 ", "100", x"80000000", x"FFFFFFFF", x"80000000");
        run("rem  MIN  % -1 ", "110", x"80000000", x"FFFFFFFF", x"00000000");

        report "--- back-to-back divides, is_m_ext never deasserted ---";
        -- Mimics two consecutive div instructions: the moment stall_m
        -- drops the next operation is presented on the very next cycle.
        for k in 1 to 3 loop
            wait until rising_edge(clk);
            funct3    <= "100";
            operand_a <= x"FFFFFF9C";   -- -100
            operand_b <= x"00000007";   --    7
            is_m_ext  <= '1';
            wait for 1 ns;
            cycles := 0;
            while stall_m = '1' loop
                wait until rising_edge(clk);
                wait for 1 ns;
                cycles := cycles + 1;
                assert cycles < 200 report "timeout" severity failure;
            end loop;
            if m_result = x"FFFFFFF2" then
                report "PASS  back-to-back div #" & integer'image(k) &
                       " = 0x" & h(m_result);
            else
                fails <= fails + 1;
                report "FAIL  back-to-back div #" & integer'image(k) &
                       " got 0x" & h(m_result) & " expected 0xFFFFFFF2"
                       severity warning;
            end if;
            -- no idle gap at all: straight into the next one
        end loop;
        is_m_ext <= '0';

        report "================ FAILURES: " & integer'image(fails) &
               " ================";
        done <= true;
        wait for 100 ns;
        std.env.stop;
    end process;

end architecture sim;
