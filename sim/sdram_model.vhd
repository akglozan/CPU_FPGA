-- SPDX-License-Identifier: Apache-2.0
-- Copyright 2026 Ozan Akgül

library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;

entity sdram_model is
    port (
        clk     : in    std_logic;
        cke     : in    std_logic;
        cs_n    : in    std_logic;
        ras_n   : in    std_logic;
        cas_n   : in    std_logic;
        we_n    : in    std_logic;
        ba      : in    std_logic_vector(1 downto 0);
        addr    : in    std_logic_vector(11 downto 0);
        dqm     : in    std_logic_vector(1 downto 0);
        dq      : inout std_logic_vector(15 downto 0)
    );
end entity sdram_model;

architecture sim of sdram_model is

    type ram_type is array (0 to 65535) of std_logic_vector(15 downto 0);
    signal ram_block : ram_type := (others => (others => '0'));

    type row_array is array (0 to 3) of std_logic_vector(11 downto 0);
    signal active_row   : row_array := (others => (others => '0'));
    signal bank_active  : std_logic_vector(3 downto 0) := (others => '0');

    -- CAS Latency 2 Read Pipeline
    signal read_valid_0 : std_logic := '0';
    signal read_valid_1 : std_logic := '0';
    signal read_valid_2 : std_logic := '0';
    signal word0_reg    : std_logic_vector(15 downto 0) := (others => '0');
    signal word1_reg    : std_logic_vector(15 downto 0) := (others => '0');
    
    -- Burst Write Tracking
    signal write_active : std_logic := '0';
    signal write_addr   : integer range 0 to 65535 := 0;

begin

    -- Tri-state buffer for DQ (delayed by 1 clock to match CAS 2)
    dq <= word0_reg when (read_valid_1 = '1') else
          word1_reg when (read_valid_2 = '1') else
          (others => 'Z');

    process(clk)
        variable cmd       : std_logic_vector(3 downto 0);
        variable bank_idx  : integer range 0 to 3;
        variable full_addr : integer range 0 to 65535;
        variable col_word  : integer range 0 to 255;
    begin
        if rising_edge(clk) then
            if cke = '1' then
                cmd      := cs_n & ras_n & cas_n & we_n;
                bank_idx := to_integer(unsigned(ba));
                
                -- Shift read valid pipeline
                read_valid_2 <= read_valid_1;
                read_valid_1 <= read_valid_0;
                read_valid_0 <= '0';
                
                -- Execute Cycle 2 of Burst Write
                if write_active = '1' then
                    if dqm(0) = '0' then
                        ram_block((write_addr + 1) mod 65536)(7 downto 0) <= dq(7 downto 0);
                    end if;
                    if dqm(1) = '0' then
                        ram_block((write_addr + 1) mod 65536)(15 downto 8) <= dq(15 downto 8);
                    end if;
                    write_active <= '0';
                end if;

                case cmd is
                    when "0011" => -- ACTIVE
                        bank_active(bank_idx) <= '1';
                        active_row(bank_idx)  <= addr;

                    when "0010" => -- PRECHARGE
                        if addr(10) = '1' then
                            bank_active <= (others => '0');
                        else
                            bank_active(bank_idx) <= '0';
                        end if;

                    when "0101" => -- READ
                        col_word  := to_integer(unsigned(addr(8 downto 1)));
                        full_addr := (to_integer(unsigned(active_row(bank_idx)(5 downto 0))) * 256) + col_word;

                        word0_reg <= ram_block(full_addr mod 65536);
                        word1_reg <= ram_block((full_addr + 1) mod 65536);
                        
                        -- Trigger pipeline (data appears on pins at Latency Edge 2)
                        read_valid_0 <= '1';

                    when "0100" => -- WRITE (Cycle 1)
                        col_word  := to_integer(unsigned(addr(8 downto 1)));
                        full_addr := (to_integer(unsigned(active_row(bank_idx)(5 downto 0))) * 256) + col_word;

                        if dqm(0) = '0' then
                            ram_block(full_addr mod 65536)(7 downto 0) <= dq(7 downto 0);
                        end if;
                        if dqm(1) = '0' then
                            ram_block(full_addr mod 65536)(15 downto 8) <= dq(15 downto 8);
                        end if;
                        
                        -- Queue up Cycle 2
                        write_active <= '1';
                        write_addr   <= full_addr mod 65536;

                    when others =>
                        null;
                end case;
            end if;
        end if;
    end process;

end architecture sim;