-- Synthesis-visualization-only stub for the Altera "altera_mf" megafunction
-- library. Real Quartus builds use Intel's own altera_mf; this file exists
-- solely so the open-source GHDL/Yosys schematic-generation pipeline
-- (.github/workflows/generate-rtl.yml) can elaborate designs that
-- instantiate altsyncram (see rtl/memory/bram_4kb.vhd), without needing
-- Intel's proprietary IP. It is never referenced by the Quartus project
-- and has no effect on synthesis, simulation, or the bitstream.

library ieee;
use ieee.std_logic_1164.all;

package altera_mf_components is
    component altsyncram
        generic (
            operation_mode                     : string;
            intended_device_family              : string := "Cyclone IV E";
            init_file                           : string := "UNUSED";
            width_a                             : natural;
            widthad_a                           : natural;
            numwords_a                          : natural;
            outdata_reg_a                       : string := "UNREGISTERED";
            width_byteena_a                     : natural := 1;
            width_b                              : natural := 1;
            widthad_b                            : natural := 1;
            numwords_b                           : natural := 1;
            address_reg_b                        : string := "CLOCK0";
            indata_reg_b                         : string := "CLOCK0";
            rdcontrol_reg_b                      : string := "CLOCK0";
            wrcontrol_wraddress_reg_b            : string := "CLOCK0";
            byteena_reg_b                        : string := "CLOCK0";
            outdata_reg_b                        : string := "UNREGISTERED";
            width_byteena_b                      : natural := 1;
            read_during_write_mode_mixed_ports   : string := "DONT_CARE"
        );
        port (
            clock0    : in  std_logic;
            address_a : in  std_logic_vector(widthad_a-1 downto 0);
            data_a    : in  std_logic_vector(width_a-1 downto 0);
            wren_a    : in  std_logic;
            byteena_a : in  std_logic_vector(width_byteena_a-1 downto 0);
            q_a       : out std_logic_vector(width_a-1 downto 0);
            address_b : in  std_logic_vector(widthad_b-1 downto 0);
            data_b    : in  std_logic_vector(width_b-1 downto 0);
            wren_b    : in  std_logic;
            byteena_b : in  std_logic_vector(width_byteena_b-1 downto 0);
            q_b       : out std_logic_vector(width_b-1 downto 0)
        );
    end component;
end package altera_mf_components;

library ieee;
use ieee.std_logic_1164.all;

entity altsyncram is
    generic (
        operation_mode                     : string;
        intended_device_family              : string := "Cyclone IV E";
        init_file                           : string := "UNUSED";
        width_a                             : natural;
        widthad_a                           : natural;
        numwords_a                          : natural;
        outdata_reg_a                       : string := "UNREGISTERED";
        width_byteena_a                     : natural := 1;
        width_b                              : natural := 1;
        widthad_b                            : natural := 1;
        numwords_b                           : natural := 1;
        address_reg_b                        : string := "CLOCK0";
        indata_reg_b                         : string := "CLOCK0";
        rdcontrol_reg_b                      : string := "CLOCK0";
        wrcontrol_wraddress_reg_b            : string := "CLOCK0";
        byteena_reg_b                        : string := "CLOCK0";
        outdata_reg_b                        : string := "UNREGISTERED";
        width_byteena_b                      : natural := 1;
        read_during_write_mode_mixed_ports   : string := "DONT_CARE"
    );
    port (
        clock0    : in  std_logic;
        address_a : in  std_logic_vector(widthad_a-1 downto 0);
        data_a    : in  std_logic_vector(width_a-1 downto 0);
        wren_a    : in  std_logic;
        byteena_a : in  std_logic_vector(width_byteena_a-1 downto 0);
        q_a       : out std_logic_vector(width_a-1 downto 0);
        address_b : in  std_logic_vector(widthad_b-1 downto 0);
        data_b    : in  std_logic_vector(width_b-1 downto 0);
        wren_b    : in  std_logic;
        byteena_b : in  std_logic_vector(width_byteena_b-1 downto 0);
        q_b       : out std_logic_vector(width_b-1 downto 0)
    );
end entity altsyncram;

architecture stub of altsyncram is
begin
    -- Behaviorally inert: exists only so the RTL-schematic pipeline can
    -- elaborate the structural hierarchy around it.
    q_a <= (others => '0');
    q_b <= (others => '0');
end architecture stub;
