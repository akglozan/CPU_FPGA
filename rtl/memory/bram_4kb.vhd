library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;
use STD.TEXTIO.all;

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

    -- Helper function to convert 8-character hex string to std_logic_vector(31 downto 0)
    function hex_to_slv32(s : string) return std_logic_vector is
        variable result : std_logic_vector(31 downto 0) := (others => '0');
        variable nibble : std_logic_vector(3 downto 0);
        variable c      : character;
        variable idx    : integer := 0;
    begin
        for i in s'range loop
            c := s(i);
            case c is
                when '0' => nibble := "0000";
                when '1' => nibble := "0001";
                when '2' => nibble := "0010";
                when '3' => nibble := "0011";
                when '4' => nibble := "0100";
                when '5' => nibble := "0101";
                when '6' => nibble := "0110";
                when '7' => nibble := "0111";
                when '8' => nibble := "1000";
                when '9' => nibble := "1001";
                when 'a' | 'A' => nibble := "1010";
                when 'b' | 'B' => nibble := "1011";
                when 'c' | 'C' => nibble := "1100";
                when 'd' | 'D' => nibble := "1101";
                when 'e' | 'E' => nibble := "1110";
                when 'f' | 'F' => nibble := "1111";
                when others => nibble := "0000";
            end case;
            
            if idx < 8 then
                result(31 - idx*4 downto 28 - idx*4) := nibble;
                idx := idx + 1;
            end if;
        end loop;
        return result;
    end function;

    -- Load memory contents from hex file in simulation; return zero array in synthesis
    impure function init_ram_from_hex(file_name : in string) return ram_type is
        variable ram_data : ram_type := (others => (others => '0'));
-- synthesis translate_off
        file hex_f        : text;
        variable line_buf : line;
        variable str_buf  : string(1 to 8);
        variable status   : file_open_status;
        variable i        : integer := 0;
-- synthesis translate_on
    begin
-- synthesis translate_off
        file_open(status, hex_f, file_name, read_mode);
        if status = open_ok then
            while not endfile(hex_f) and i < 1024 loop
                readline(hex_f, line_buf);
                if line_buf'length >= 8 then
                    read(line_buf, str_buf);
                    ram_data(i) := hex_to_slv32(str_buf);
                    i := i + 1;
                end if;
            end loop;
            file_close(hex_f);
        end if;
-- synthesis translate_on
        return ram_data;
    end function;
    
    -- Synthesis attributes for Intel / Quartus Prime
    attribute ram_init_file : string;
    attribute syn_ramstyle  : string;
    
    signal ram : ram_type := init_ram_from_hex(HEX_FILE);

    attribute ram_init_file of ram : signal is HEX_FILE;
    attribute syn_ramstyle  of ram : signal is "no_rw_check, M9K";

begin
    
   -- ==========================================
    -- Port A: Instruction Fetch Channel 
    -- Combinatorial (0-cycle) Read
    -- ==========================================
    rdata_a <= ram(to_integer(unsigned(addr_a)));
    
    -- ==========================================
    -- Port B: Data Channel
    -- Synchronous Write, Combinatorial Read
    -- ==========================================
    process(clk)
    begin
        if rising_edge(clk) then 
            -- Synchronous Byte-Wise Writes
            if we_b(0) = '1' then ram(to_integer(unsigned(addr_b)))(7 downto 0)   <= wdata_b(7 downto 0);   end if;
            if we_b(1) = '1' then ram(to_integer(unsigned(addr_b)))(15 downto 8)  <= wdata_b(15 downto 8);  end if;
            if we_b(2) = '1' then ram(to_integer(unsigned(addr_b)))(23 downto 16) <= wdata_b(23 downto 16); end if;
            if we_b(3) = '1' then ram(to_integer(unsigned(addr_b)))(31 downto 24) <= wdata_b(31 downto 24); end if;
        end if;
    end process;

    -- Combinatorial (0-cycle) Read
    rdata_b <= ram(to_integer(unsigned(addr_b)));

end architecture rtl;