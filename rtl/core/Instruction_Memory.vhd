-- SPDX-License-Identifier: Apache-2.0
-- Copyright 2026 Ozan Akgül
--
-- Licensed under the Apache License, Version 2.0 (the "License");
-- you may not use this file except in compliance with the License.
-- You may obtain a copy of the License at
--
--     http://www.apache.org/licenses/LICENSE-2.0
--
-- Unless required by applicable law or agreed to in writing, software
-- distributed under the License is distributed on an "AS IS" BASIS,
-- WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
-- See the License for the specific language governing permissions and
-- limitations under the License.

library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;
use IEEE.STD_LOGIC_TEXTIO.all;
use STD.textio.all;

-- Bootloader instruction memory. 1024 x 32-bit words, initialized at
-- elaboration time from a hex-format file (HEX_FILE) rather than
-- loaded at runtime. The read path is purely combinational so its
-- output aligns with IF_ID_Register in a single cycle, with no extra
-- registered read latency to account for.
entity Instruction_Memory is
    generic (
        -- Path to the hex-format memory image loaded at elaboration,
        -- relative to the Quartus project directory (the folder holding
        -- CPU_FPGA.qpf). All generated memory images live in sw/.
        HEX_FILE : string := "sw/boot_bram.hex"
    );
    port (
        -- Present for interface consistency; the read path below is
        -- combinational and does not use clk.
        clk         : in  std_logic;
        -- Byte address; the word index is derived from addr(11 downto 2).
        addr        : in  std_logic_vector(31 downto 0);
        -- Combinationally read instruction word at addr, or zero if the
        -- address falls outside the 1024-word range.
        instruction : out std_logic_vector(31 downto 0)
    );
end entity Instruction_Memory;

architecture Behavioral of Instruction_Memory is

    type memory_type is array (0 to 1023) of std_logic_vector(31 downto 0);

    impure function init_ram_from_file(file_name : in string) return memory_type is
        file hex_file      : text open read_mode is file_name;
        variable hex_line  : line;
        variable temp_ram  : memory_type := (others => (others => '0'));
        variable temp_data : std_logic_vector(31 downto 0);
    begin
        for i in 0 to 1023 loop
            if not endfile(hex_file) then
                readline(hex_file, hex_line);
                if hex_line'length >= 8 then
                    hread(hex_line, temp_data);
                    temp_ram(i) := temp_data;
                end if;
            end if;
        end loop;
        return temp_ram;
    end function;
	
    signal ram : memory_type := init_ram_from_file(HEX_FILE);

begin

    -- Combinatorial read for immediate 0-cycle fetch to align with IF_ID_Register
    process(addr, ram)
        variable word_index : integer;
    begin
        word_index := to_integer(unsigned(addr(11 downto 2)));
        if word_index >= 0 and word_index <= 1023 then
            instruction <= ram(word_index);
        else
            instruction <= (others => '0');
        end if;
    end process;

end architecture Behavioral;