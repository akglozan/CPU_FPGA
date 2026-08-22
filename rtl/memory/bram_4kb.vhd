-- SPDX-License-Identifier: Apache-2.0
-- Copyright 2026 Ozan Akgül

library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;

library altera_mf;
use altera_mf.altera_mf_components.all;

entity bram_4kb is
    generic (
        HEX_FILE : string := "boot_bram.mif"
    );
    port (
        clk     : in  std_logic;
        
        -- Port A: Instruction Bus (Read-Only)
        addr_a  : in  std_logic_vector(9 downto 0);
        rdata_a : out std_logic_vector(31 downto 0);
        
        -- Port B: Data Bus (Read/Write)
        addr_b  : in  std_logic_vector(9 downto 0);
        wdata_b : in  std_logic_vector(31 downto 0);
        we_b    : in  std_logic_vector(3 downto 0);
        rdata_b : out std_logic_vector(31 downto 0)
    );
end entity bram_4kb;

architecture rtl of bram_4kb is

    signal wren_b_sig : std_logic;

begin

    wren_b_sig <= '1' when unsigned(we_b) /= 0 else '0';

    U_ALTSYNCRAM : altsyncram
    generic map (
        address_reg_b                      => "CLOCK0",
        byte_size                          => 8,
        byteena_reg_b                      => "CLOCK0",
        indata_reg_b                       => "CLOCK0",
        init_file                          => HEX_FILE,
        intended_device_family             => "Cyclone IV E",
        lpm_type                           => "altsyncram",
        numwords_a                         => 1024,
        numwords_b                         => 1024,
        operation_mode                     => "BIDIR_DUAL_PORT",
        outdata_reg_a                      => "UNREGISTERED",
        outdata_reg_b                      => "UNREGISTERED",
        widthad_a                          => 10,
        widthad_b                          => 10,
        width_a                            => 32,
        width_b                            => 32,
        width_byteena_b                    => 4,
        wrcontrol_wraddress_reg_b          => "CLOCK0"
    )
    port map (
        clock0          => clk,
        
        -- Port A (Instruction Fetch)
        address_a       => addr_a,
        q_a             => rdata_a,
        
        -- Port B (Data Read / Write)
        address_b       => addr_b,
        data_b          => wdata_b,
        wren_b          => wren_b_sig,
        byteena_b       => we_b,
        q_b             => rdata_b
    );

end architecture rtl;