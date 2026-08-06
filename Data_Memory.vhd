library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;


entity Data_Memory is

	port(
	
		clk			:	in std_logic;
		mem_write	:	in std_logic;
		mem_read		:	in std_logic;
		func3			:	in std_logic_vector(2 downto 0);
		addr			:	in	std_logic_vector(31 downto 0);
		write_data	:	in	std_logic_vector(31 downto 0);
		read_data	:	out	std_logic_vector(31 downto 0)
	
	);


end entity;

architecture Behavioral of Data_Memory is

begin




end architecture;