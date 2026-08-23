-- Minimal simulation-only stand-in for Altera's altsyncram, configured
-- to match exactly what CPU_FPGA.map.rpt reports for u_bram:
--   address register always present on both ports,
--   outdata_reg_a / outdata_reg_b selectable,
--   BIDIR_DUAL_PORT, byte enables on port B, read-old-data.
-- Includes a write monitor that flags any write into the code region.

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

    process (clock0)
        variable ia, ib : natural;
        variable w      : std_logic_vector(width_a - 1 downto 0);
    begin
        if rising_edge(clock0) then
            ia := to_integer(unsigned(address_a));
            ib := to_integer(unsigned(address_b));

            -- Read old data (address register + array read).
            q_a_core <= mem(ia);
            q_b_core <= mem(ib);

            -- Optional output register stage.
            q_a_reg <= q_a_core;
            q_b_reg <= q_b_core;

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
    end process;

    q_a <= q_a_reg when outdata_reg_a = "CLOCK0" else q_a_core;
    q_b <= q_b_reg when outdata_reg_b = "CLOCK0" else q_b_core;

end architecture sim;
