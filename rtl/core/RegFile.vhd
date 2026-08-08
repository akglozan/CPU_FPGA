library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;

entity RegFile is

	port(
	
	clk	: in std_logic;
	rst_n	: in std_logic;
	reg_write	: in std_logic;
	rd_addr	: in std_logic_vector(4 downto 0);
	rs1_addr	: in std_logic_vector(4 downto 0);
	rs2_addr	: in std_logic_vector(4 downto 0);
	rd_data	: in std_logic_vector(31 downto 0);
	
	rs1_data	: out std_logic_vector(31 downto 0);
	rs2_data	: out std_logic_vector(31 downto 0)
	
	
	);
	




end entity;

architecture Behavioral of RegFile is
	
	-- a custom type is defined and what it should be made of
	type reg_array is array(0 to 31) of std_logic_vector(31 downto 0);
	-- the signal registers is defined as type 'reg_array'
	-- nested others do this, core others define the whole row as 0
	-- outer others assign that value to every other row which is 0
	signal registers : reg_array := (others => (others => '0'));
	
begin

process(clk)
begin

	if rising_edge(clk) then
		if rst_n ='1' then
			registers <= (others => (others => '0'));
		elsif reg_write = '1' and rd_addr /= "00000" then
			registers(to_integer(unsigned(rd_addr))) <= rd_data;
		end if;
	end if;
end process;
	
	rs1_data <= x"00000000" when rs1_addr = "00000" else 
            registers(to_integer(unsigned(rs1_addr)));

	rs2_data <= x"00000000" when rs2_addr = "00000" else 
            registers(to_integer(unsigned(rs2_addr)));
	
end architecture Behavioral;
	