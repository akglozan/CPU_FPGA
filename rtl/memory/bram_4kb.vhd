-- SPDX-License-Identifier: Apache-2.0
-- Copyright 2026 Ozan Akgül

library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;


entity bram_4kb is
    generic (
        hex_file : string := "boot_bram.mif"
    );
    port (
        clk     : in  std_logic;

        addr_a  : in  std_logic_vector(9 downto 0);
        rdata_a : out std_logic_vector(31 downto 0);

        addr_b  : in  std_logic_vector(9 downto 0);
        wdata_b : in  std_logic_vector(31 downto 0);
        we_b    : in  std_logic_vector(3 downto 0);
        rdata_b : out std_logic_vector(31 downto 0)
    );
end entity bram_4kb;

architecture rtl of bram_4kb is
    type ram_type is array (0 to 1023)
        of std_logic_vector(31 downto 0);

    signal ram : ram_type;
begin

    -- Asynchronous instruction read
    rdata_a <= ram(to_integer(unsigned(addr_a)));

    -- Synchronous data-port write/read
    process(clk)
        variable index : integer range 0 to 1023;
    begin
        if rising_edge(clk) then
            index := to_integer(unsigned(addr_b));

            for i in 0 to 3 loop
                if we_b(i) = '1' then
                    ram(index)(i*8+7 downto i*8)
                        <= wdata_b(i*8+7 downto i*8);
                end if;
            end loop;

            rdata_b <= ram(index);
        end if;
    end process;

end architecture;