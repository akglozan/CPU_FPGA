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

    -- 64 Mbit Memory Array: 4 Banks x 4096 Rows x 512 Columns x 16-bit
    -- Behavioral model array: 64K x 16-bit
    type ram_type is array (0 to 65535) of std_logic_vector(15 downto 0);
    signal ram_block : ram_type := (others => (others => '0'));

    -- Active row per bank
    type row_array is array (0 to 3) of std_logic_vector(11 downto 0);
    signal active_row   : row_array := (others => (others => '0'));
    signal bank_active  : std_logic_vector(3 downto 0) := (others => '0');

    -- Pipeline registers for CAS latency = 2 and Burst = 2
    signal read_pipeline_valid : std_logic_vector(2 downto 0) := "000";
    signal read_pipeline_addr  : integer range 0 to 65535 := 0;
    signal read_pipeline_addr2 : integer range 0 to 65535 := 0;

    signal dq_out : std_logic_vector(15 downto 0) := (others => 'Z');
    signal dq_oe  : std_logic := '0';

begin

    dq <= dq_out when dq_oe = '1' else (others => 'Z');

    process(clk)
        variable cmd        : std_logic_vector(3 downto 0);
        variable bank_idx   : integer range 0 to 3;
        variable full_addr  : integer range 0 to 65535;
        variable addr_vec   : std_logic_vector(15 downto 0);
        variable row_slice  : std_logic_vector(5 downto 0);
    begin
        if rising_edge(clk) then
            if cke = '1' then
                cmd := cs_n & ras_n & cas_n & we_n;
                bank_idx := to_integer(unsigned(ba));

                -- Shift read pipeline
                read_pipeline_valid <= read_pipeline_valid(1 downto 0) & '0';

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
                        row_slice := active_row(bank_idx)(5 downto 0);
                        addr_vec  := ba & row_slice & addr(7 downto 0);
                        full_addr := to_integer(unsigned(addr_vec));

                        read_pipeline_addr     <= full_addr;
                        read_pipeline_addr2    <= (full_addr + 1) mod 65536;
                        read_pipeline_valid(0) <= '1';

                    when "0100" => -- WRITE
                        row_slice := active_row(bank_idx)(5 downto 0);
                        addr_vec  := ba & row_slice & addr(7 downto 0);
                        full_addr := to_integer(unsigned(addr_vec));

                        if dqm(0) = '0' then
                            ram_block(full_addr)(7 downto 0) <= dq(7 downto 0);
                        end if;
                        if dqm(1) = '0' then
                            ram_block(full_addr)(15 downto 8) <= dq(15 downto 8);
                        end if;

                    when others =>
                        null;
                end case;

                -- Read data drive on CAS Latency = 2
                if read_pipeline_valid(1) = '1' then
                    dq_oe  <= '1';
                    dq_out <= ram_block(read_pipeline_addr);
                elsif read_pipeline_valid(2) = '1' then
                    dq_oe  <= '1';
                    dq_out <= ram_block(read_pipeline_addr2);
                else
                    dq_oe  <= '0';
                    dq_out <= (others => 'Z');
                end if;

            end if;
        end if;
    end process;

end architecture sim;