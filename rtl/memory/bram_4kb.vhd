-- SPDX-License-Identifier: Apache-2.0
-- Copyright 2026 Ozan Akgül

library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;
use STD.TEXTIO.all;
use IEEE.STD_LOGIC_TEXTIO.all;

entity bram_4kb is
    generic (
        HEX_FILE : string := "boot_bram.hex"
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

    type ram_type is array (0 to 1023) of std_logic_vector(31 downto 0);

    -- Robust RAM initialization function using standard IEEE hread
    impure function init_ram_from_hex(file_name : in string) return ram_type is
        variable ram_data : ram_type := (others => (others => '0'));
-- synthesis translate_off
        file hex_f        : text;
        variable line_buf : line;
        variable word_val : std_logic_vector(31 downto 0);
        variable status   : file_open_status;
        variable i        : integer := 0;
        variable good     : boolean;
-- synthesis translate_on
    begin
-- synthesis translate_off
        file_open(status, hex_f, file_name, read_mode);
        if status = open_ok then
            while not endfile(hex_f) and i < 1024 loop
                readline(hex_f, line_buf);
                -- Skip empty or short lines
                if line_buf'length >= 8 then
                    hread(line_buf, word_val, good);
                    if good then
                        ram_data(i) := word_val;
                        i := i + 1;
                    end if;
                end if;
            end loop;
            file_close(hex_f);
        end if;
-- synthesis translate_on
        return ram_data;
    end function;
    
    -- Synthesis attributes for Intel Quartus Prime
    attribute ram_init_file : string;
    attribute syn_ramstyle  : string;
    
    signal ram : ram_type := init_ram_from_hex(HEX_FILE);

    attribute ram_init_file of ram : signal is HEX_FILE;
    attribute syn_ramstyle  of ram : signal is "no_rw_check, M9K";

begin
    
    -- ==========================================
    -- Port A: Instruction Fetch Channel (0-cycle)
    -- ==========================================
    rdata_a <= ram(to_integer(unsigned(addr_a)));
    
   -- ==========================================
    -- Port B: Data Channel (Corrected Byte-Enable Write)
    -- ==========================================
    process(clk)
        variable temp_word : std_logic_vector(31 downto 0);
        variable idx       : integer;
    begin
        if rising_edge(clk) then 
            idx := to_integer(unsigned(addr_b));
            
            -- Read current memory state
            temp_word := ram(idx);
            
            -- Apply byte-wise overwrites
            if we_b(0) = '1' then temp_word(7 downto 0)   := wdata_b(7 downto 0);   end if;
            if we_b(1) = '1' then temp_word(15 downto 8)  := wdata_b(15 downto 8);  end if;
            if we_b(2) = '1' then temp_word(23 downto 16) := wdata_b(23 downto 16); end if;
            if we_b(3) = '1' then temp_word(31 downto 24) := wdata_b(31 downto 24); end if;
            
            -- Write back the fully assembled 32-bit word atomically if any byte is enabled
            if unsigned(we_b) /= 0 then
                ram(idx) <= temp_word;
            end if;
        end if;
    end process;

    rdata_b <= ram(to_integer(unsigned(addr_b)));

end architecture rtl;