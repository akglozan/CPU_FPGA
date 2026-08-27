-- Minimal simulation-only stand-in for Altera's altsyncram, configured
-- to match exactly what CPU_FPGA.map.rpt reports for u_bram:
--   address register always present on both ports,
--   outdata_reg_a / outdata_reg_b selectable,
--   BIDIR_DUAL_PORT, byte enables on port B, read-old-data.
-- Includes a write monitor that flags any write into the code region.
--
-- Also supports operation_mode = "DUAL_PORT" (simple dual port: port A
-- write-only on clock0, port B read-only on clock1), added for Phase
-- 4.2's vga_line_buffer.vhd -- see that file's header for why it
-- instantiates altsyncram directly rather than relying on inference.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package altera_mf_components is
    component altsyncram is
        generic (
            operation_mode                     : string  := "BIDIR_DUAL_PORT";
            intended_device_family             : string  := "";
            init_file                          : string  := "";
            width_a                            : natural := 32;
            widthad_a                          : natural := 10;
            numwords_a                         : natural := 1024;
            outdata_reg_a                      : string  := "UNREGISTERED";
            width_byteena_a                    : natural := 1;
            width_b                            : natural := 32;
            widthad_b                          : natural := 10;
            numwords_b                         : natural := 1024;
            address_reg_b                      : string  := "CLOCK1";
            indata_reg_b                       : string  := "CLOCK1";
            rdcontrol_reg_b                    : string  := "CLOCK1";
            wrcontrol_wraddress_reg_b          : string  := "CLOCK1";
            byteena_reg_b                      : string  := "CLOCK1";
            outdata_reg_b                      : string  := "UNREGISTERED";
            width_byteena_b                    : natural := 1;
            read_during_write_mode_mixed_ports : string  := "DONT_CARE"
        );
        port (
            clock0    : in  std_logic;
            -- COMPONENT. Only used when operation_mode = "DUAL_PORT" (port B is
            -- then a read port in its own clock domain). Defaulted so
            -- single-clock BIDIR_DUAL_PORT users need not connect it.
            clock1    : in  std_logic := '0';
            address_a : in  std_logic_vector(widthad_a - 1 downto 0);
            data_a    : in  std_logic_vector(width_a - 1 downto 0);
            wren_a    : in  std_logic := '0';
            byteena_a : in  std_logic_vector(width_byteena_a - 1 downto 0) := (others => '1');
            q_a       : out std_logic_vector(width_a - 1 downto 0);
            address_b : in  std_logic_vector(widthad_b - 1 downto 0);
            data_b    : in  std_logic_vector(width_b - 1 downto 0);
            wren_b    : in  std_logic := '0';
            byteena_b : in  std_logic_vector(width_byteena_b - 1 downto 0) := (others => '1');
            q_b       : out std_logic_vector(width_b - 1 downto 0)
        );
    end component;
end package altera_mf_components;

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;

entity altsyncram is
    generic (
        operation_mode                     : string  := "BIDIR_DUAL_PORT";
        intended_device_family             : string  := "";
        init_file                          : string  := "";
        width_a                            : natural := 32;
        widthad_a                          : natural := 10;
        numwords_a                         : natural := 1024;
        outdata_reg_a                      : string  := "UNREGISTERED";
        width_byteena_a                    : natural := 1;
        width_b                            : natural := 32;
        widthad_b                          : natural := 10;
        numwords_b                         : natural := 1024;
        address_reg_b                      : string  := "CLOCK1";
        indata_reg_b                       : string  := "CLOCK1";
        rdcontrol_reg_b                    : string  := "CLOCK1";
        wrcontrol_wraddress_reg_b          : string  := "CLOCK1";
        byteena_reg_b                      : string  := "CLOCK1";
        outdata_reg_b                      : string  := "UNREGISTERED";
        width_byteena_b                    : natural := 1;
        read_during_write_mode_mixed_ports : string  := "DONT_CARE"
    );
    port (
        clock0    : in  std_logic;
        -- Only used when operation_mode = "DUAL_PORT" (port B is then a
        -- read port in its own clock domain). Defaulted so single-clock
        -- BIDIR_DUAL_PORT users need not connect it.
        clock1    : in  std_logic := '0';
        address_a : in  std_logic_vector(widthad_a - 1 downto 0);
        data_a    : in  std_logic_vector(width_a - 1 downto 0);
        wren_a    : in  std_logic := '0';
        byteena_a : in  std_logic_vector(width_byteena_a - 1 downto 0) := (others => '1');
        q_a       : out std_logic_vector(width_a - 1 downto 0);
        address_b : in  std_logic_vector(widthad_b - 1 downto 0);
        data_b    : in  std_logic_vector(width_b - 1 downto 0);
        wren_b    : in  std_logic := '0';
        byteena_b : in  std_logic_vector(width_byteena_b - 1 downto 0) := (others => '1');
        q_b       : out std_logic_vector(width_b - 1 downto 0)
    );
end entity altsyncram;

architecture sim of altsyncram is

    -- Only words 1022/1023 (0xFF8/0xFFC) are legitimate stack slots.
    -- Anything below that is an unexpected write.
    constant code_top : natural := 1021;

    type mem_t is array (0 to numwords_a - 1) of std_logic_vector(width_a - 1 downto 0);

    impure function load_mif return mem_t is
        file     f       : text;
        variable l       : line;
        variable status  : file_open_status;
        variable m       : mem_t := (others => (others => '0'));
        variable s       : string(1 to 256);
        variable slen    : natural;
        variable started : boolean := false;
        variable colon   : natural;
        variable semi    : natural;
        variable addr    : natural;
        variable datv    : unsigned(width_a - 1 downto 0);
        variable ok      : boolean;

        function hex_val (c : character) return integer is
        begin
            case c is
                when '0' to '9' => return character'pos(c) - character'pos('0');
                when 'a' to 'f' => return character'pos(c) - character'pos('a') + 10;
                when 'A' to 'F' => return character'pos(c) - character'pos('A') + 10;
                when others     => return -1;
            end case;
        end function;
    begin
        if init_file = "" then
            return m;
        end if;
        file_open(status, f, init_file, read_mode);
        if status /= open_ok then
            report "altsyncram: could not open init_file " & init_file severity failure;
            return m;
        end if;

        while not endfile(f) loop
            readline(f, l);
            slen := l'length;
            if slen > 256 then
                slen := 256;
            end if;
            s := (others => ' ');
            for i in 1 to slen loop
                s(i) := l.all(i);
            end loop;

            if not started then
                for i in 1 to slen - 12 loop
                    if s(i to i + 12) = "CONTENT BEGIN" then
                        started := true;
                    end if;
                end loop;
            else
                colon := 0;
                semi  := 0;
                for i in 1 to slen loop
                    if s(i) = ':' and colon = 0 then
                        colon := i;
                    end if;
                    if s(i) = ';' and semi = 0 then
                        semi := i;
                    end if;
                end loop;

                if colon > 1 and semi > colon then
                    addr := 0;
                    ok   := true;
                    for i in 1 to colon - 1 loop
                        if s(i) /= ' ' then
                            if hex_val(s(i)) < 0 then
                                ok := false;
                            else
                                addr := addr * 16 + hex_val(s(i));
                            end if;
                        end if;
                    end loop;

                    datv := (others => '0');
                    for i in colon + 1 to semi - 1 loop
                        if s(i) /= ' ' then
                            if hex_val(s(i)) < 0 then
                                ok := false;
                            else
                                datv := shift_left(datv, 4) or
                                        to_unsigned(hex_val(s(i)), width_a);
                            end if;
                        end if;
                    end loop;

                    if ok and addr < numwords_a then
                        m(addr) := std_logic_vector(datv);
                    end if;
                end if;
            end if;
        end loop;

        file_close(f);
        return m;
    end function;

    signal mem : mem_t := load_mif;

    signal q_a_core : std_logic_vector(width_a - 1 downto 0) := (others => '0');
    signal q_b_core : std_logic_vector(width_b - 1 downto 0) := (others => '0');
    signal q_a_reg  : std_logic_vector(width_a - 1 downto 0) := (others => '0');
    signal q_b_reg  : std_logic_vector(width_b - 1 downto 0) := (others => '0');

begin

    -- Sensitive to BOTH clocks, and mem is driven from this one process
    -- only, so the two operation modes can share the array without a
    -- multiple-driver conflict. In BIDIR_DUAL_PORT (bram_4kb's use)
    -- clock1 is never connected and never rises, so the clock1 branch
    -- below is simply dead -- that mode's behaviour is byte-for-byte
    -- what it was before DUAL_PORT support was added.
    process (clock0, clock1)
        variable ia, ib : natural;
        variable w      : std_logic_vector(width_a - 1 downto 0);
    begin
        if rising_edge(clock0) then
            ia := to_integer(unsigned(address_a));

            -- Read old data (address register + array read).
            q_a_core <= mem(ia);
            q_a_reg  <= q_a_core;

            if operation_mode = "DUAL_PORT" then
                -- Simple dual port: port A is write-only, port B is
                -- read-only and lives on clock1 (see below). No byte
                -- enables, no write monitor -- that monitor is specific
                -- to bram_4kb's code region, not to memories in general.
                if wren_a = '1' then
                    mem(ia) <= data_a;
                end if;
            else
                ib := to_integer(unsigned(address_b));
                q_b_core <= mem(ib);
                q_b_reg  <= q_b_core;

                if wren_b = '1' then
                    w := mem(ib);
                    for byte in 0 to width_byteena_b - 1 loop
                        if byteena_b(byte) = '1' then
                            w(byte * 8 + 7 downto byte * 8) :=
                                data_b(byte * 8 + 7 downto byte * 8);
                        end if;
                    end loop;
                    mem(ib) <= w;

                    if ib <= code_top then
                        report "*** UNEXPECTED BRAM WRITE *** word " &
                               integer'image(ib) &
                               " (byte addr " & integer'image(ib * 4) &
                               ")  old=" & to_string(mem(ib)) &
                               "  new=" & to_string(w) &
                               "  byteena=" & to_string(byteena_b)
                               severity warning;
                    end if;
                end if;

                if wren_a = '1' then
                    report "*** PORT-A WRITE (should never happen) ***" severity warning;
                end if;
            end if;
        end if;

        -- DUAL_PORT read port, in its own clock domain.
        if operation_mode = "DUAL_PORT" then
            if rising_edge(clock1) then
                ib := to_integer(unsigned(address_b));
                q_b_core <= mem(ib);
                q_b_reg  <= q_b_core;
            end if;
        end if;
    end process;

    q_a <= q_a_reg when outdata_reg_a = "CLOCK0" else q_a_core;
    q_b <= q_b_reg when outdata_reg_b = "CLOCK0" else q_b_core;

end architecture sim;

-------------------------------------------------------------------------------
-- Minimal simulation-only stand-in for Altera's altpll, added for Phase
-- 4.2 -- vga_pll.vhd (the wizard-generated ALTPLL wrapper for the 50->25
-- MHz VGA pixel clock) instantiates a component named "altpll" from this
-- same library, and nothing previously provided a matching entity, so no
-- testbench that elaborates the full rv32im_soc top level (which
-- instantiates vga_pll) could actually run under GHDL. Frequency
-- behaviour is generic, not hardcoded to 50/25 MHz: it measures inclk(0)'s
-- real period from two observed edges, then free-runs clk(0) scaled by
-- clk0_divide_by/clk0_multiply_by -- the same relationship a real ALTPLL
-- implements, just derived at runtime instead of needing an exact
-- structural PLL model. locked follows areset with a fixed 1 us stand-in
-- lock time (real lock time is on the order of tens of microseconds;
-- exact value doesn't matter for any consumer in this design, which only
-- waits for locked to go high once, via rst_sync).
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;

entity altpll is
    generic (
        bandwidth_type              : string  := "AUTO";
        clk0_divide_by               : natural := 1;
        clk0_duty_cycle              : natural := 50;
        clk0_multiply_by             : natural := 1;
        clk0_phase_shift             : string  := "0";
        compensate_clock             : string  := "CLK0";
        inclk0_input_frequency       : natural := 0;
        intended_device_family       : string  := "";
        lpm_hint                     : string  := "";
        lpm_type                     : string  := "altpll";
        operation_mode               : string  := "NORMAL";
        pll_type                     : string  := "AUTO";
        port_activeclock             : string  := "PORT_UNUSED";
        port_areset                  : string  := "PORT_UNUSED";
        port_clkbad0                 : string  := "PORT_UNUSED";
        port_clkbad1                 : string  := "PORT_UNUSED";
        port_clkloss                 : string  := "PORT_UNUSED";
        port_clkswitch               : string  := "PORT_UNUSED";
        port_configupdate            : string  := "PORT_UNUSED";
        port_fbin                    : string  := "PORT_UNUSED";
        port_inclk0                  : string  := "PORT_USED";
        port_inclk1                  : string  := "PORT_UNUSED";
        port_locked                  : string  := "PORT_UNUSED";
        port_pfdena                  : string  := "PORT_UNUSED";
        port_phasecounterselect      : string  := "PORT_UNUSED";
        port_phasedone               : string  := "PORT_UNUSED";
        port_phasestep               : string  := "PORT_UNUSED";
        port_phaseupdown             : string  := "PORT_UNUSED";
        port_pllena                  : string  := "PORT_UNUSED";
        port_scanaclr                : string  := "PORT_UNUSED";
        port_scanclk                 : string  := "PORT_UNUSED";
        port_scanclkena              : string  := "PORT_UNUSED";
        port_scandata                : string  := "PORT_UNUSED";
        port_scandataout             : string  := "PORT_UNUSED";
        port_scandone                : string  := "PORT_UNUSED";
        port_scanread                : string  := "PORT_UNUSED";
        port_scanwrite                : string  := "PORT_UNUSED";
        port_clk0                    : string  := "PORT_USED";
        port_clk1                    : string  := "PORT_UNUSED";
        port_clk2                    : string  := "PORT_UNUSED";
        port_clk3                    : string  := "PORT_UNUSED";
        port_clk4                    : string  := "PORT_UNUSED";
        port_clk5                    : string  := "PORT_UNUSED";
        port_clkena0                 : string  := "PORT_UNUSED";
        port_clkena1                 : string  := "PORT_UNUSED";
        port_clkena2                 : string  := "PORT_UNUSED";
        port_clkena3                 : string  := "PORT_UNUSED";
        port_clkena4                 : string  := "PORT_UNUSED";
        port_clkena5                 : string  := "PORT_UNUSED";
        port_extclk0                 : string  := "PORT_UNUSED";
        port_extclk1                 : string  := "PORT_UNUSED";
        port_extclk2                 : string  := "PORT_UNUSED";
        port_extclk3                 : string  := "PORT_UNUSED";
        self_reset_on_loss_lock      : string  := "OFF";
        width_clock                  : natural := 5
    );
    port (
        areset : in  std_logic := '0';
        inclk  : in  std_logic_vector(1 downto 0) := (others => '0');
        clk    : out std_logic_vector(4 downto 0);
        locked : out std_logic
    );
end entity altpll;

architecture sim of altpll is
    signal c0_int     : std_logic := '0';
    signal locked_int : std_logic := '0';
begin

    clk(0)          <= c0_int;
    clk(4 downto 1) <= (others => '0');
    locked          <= locked_int;

    gen_clk : process
        variable t_prev    : time := 0 ns;
        variable t_now     : time;
        variable in_period : time;
        variable half_out  : time;
    begin
        -- Measure inclk(0)'s real period from two consecutive edges
        -- (it free-runs regardless of areset, same as real hardware's
        -- reference input), then derive the scaled output half-period.
        wait until rising_edge(inclk(0));
        t_prev := now;
        wait until rising_edge(inclk(0));
        t_now  := now;
        in_period := t_now - t_prev;
        half_out  := (in_period * clk0_divide_by) / clk0_multiply_by / 2;

        loop
            if areset = '1' then
                c0_int <= '0';
                wait until areset = '0';
            end if;
            c0_int <= not c0_int;
            wait for half_out;
        end loop;
    end process;

    lock_proc : process
    begin
        locked_int <= '0';
        wait until areset = '0';
        wait for 1 us;
        locked_int <= '1';
        wait until areset = '1';
    end process;

end architecture sim;
