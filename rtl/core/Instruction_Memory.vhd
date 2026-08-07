library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;
use IEEE.STD_LOGIC_TEXTIO.all;
use STD.textio.all;

entity Instruction_Memory is

generic (
        HEX_FILE_PATH : string := "sw/boot_bram.hex"
    );

port(
	clk		:	in std_logic;
	
	addr		:	in std_logic_vector(31 downto 0);
	
	instruction	: out std_logic_vector(31 downto 0)
	);	



end entity Instruction_Memory;

architecture Behavioral of Instruction_Memory is

type memory_type is array (0 to 1023) of std_logic_vector(31 downto 0);


impure function init_ram_from_file(file_name : in string) return memory_type is
    file hex_file       : text open read_mode is file_name;
    variable hex_line   : line;
    variable temp_ram   : memory_type := (others => (others => '0'));
    variable temp_data  : std_logic_vector(31 downto 0);
begin
    for i in 0 to 1023 loop
        if not endfile(hex_file) then
            readline(hex_file, hex_line);
            hread(hex_line, temp_data); -- Reads a 32-bit hex value from the line
            temp_ram(i) := temp_data;
        end if;
    end loop;
    return temp_ram;
end function;
	
	signal ram : memory_type := init_ram_from_file(HEX_FILE_PATH);
	
begin

	process(clk)
		variable word_index : integer;
	begin
		if rising_edge(clk) then
		word_index:= to_integer(unsigned(addr(11 downto 2)));
		
		instruction <= ram(word_index);
		end if;
		

	end process;

end architecture Behavioral;
