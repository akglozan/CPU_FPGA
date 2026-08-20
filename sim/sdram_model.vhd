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

    -- Memory Array: 64K x 16-bit words (indexed by word address)
    type ram_type is array (0 to 65535) of std_logic_vector(15 downto 0);
    signal ram_block : ram_type := (others => (others => '0'));

    type row_array is array (0 to 3) of std_logic_vector(11 downto 0);
    signal active_row   : row_array := (others => (others => '0'));
    signal bank_active  : std_logic_vector(3 downto 0) := (others => '0');

    -- CAS Latency 2 / Burst Length 2 Pipeline Registers
    signal pipe_valid_1 : std_logic := '0';
    signal pipe_valid_2 : std_logic := '0';
    signal pipe_data_1  : std_logic_vector(15 downto 0) := (others => '0');
    signal pipe_data_2  : std_logic_vector(15 downto 0) := (others => '0');

    signal dq_out : std_logic_vector(15 downto 0) := (others => 'Z');
    signal dq_oe  : std_logic := '0';

begin

    dq <= dq_out when (dq_oe = '1') else (others => 'Z');

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

                -- Advance Read Output Pipeline
                pipe_valid_1 <= '0';
                pipe_valid_2 <= pipe_valid_1;
                pipe_data_2  <= pipe_data_1;

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
                        -- addr(9 downto 1) is the 16-bit word column offset
                        col_word  := to_integer(unsigned(addr(8 downto 1)));
                        full_addr := (to_integer(unsigned(active_row(bank_idx)(5 downto 0))) * 256) + col_word;

                        pipe_valid_1 <= '1';
                        pipe_data_1  <= ram_block((full_addr + 1) mod 65536);
                        
                        -- First word queued for CAS=2 arrival
                        dq_out <= ram_block(full_addr mod 65536);

                    when "0100" => -- WRITE
                        col_word  := to_integer(unsigned(addr(8 downto 1)));
                        full_addr := (to_integer(unsigned(active_row(bank_idx)(5 downto 0))) * 256) + col_word;

                        if dqm(0) = '0' then
                            ram_block(full_addr mod 65536)(7 downto 0) <= dq(7 downto 0);
                        end if;
                        if dqm(1) = '0' then
                            ram_block(full_addr mod 65536)(15 downto 8) <= dq(15 downto 8);
                        end if;

                    when others =>
                        null;
                end case;

                -- Drive Data Bus during Active Burst Cycles (CAS=2, BL=2)
                if pipe_valid_1 = '1' then
                    dq_oe <= '1';
                    -- dq_out already holds Word 0 from the READ cycle
                elsif pipe_valid_2 = '1' then
                    dq_oe  <= '1';
                    dq_out <= pipe_data_2; -- Drive Word 1
                else
                    dq_oe  <= '0';
                    dq_out <= (others => 'Z');
                end if;

            end if;
        end if;
    end process;

end architecture sim;