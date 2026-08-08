library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;

entity gpio_key is

	port(
		clk 	:	in std_logic;
		rst_n	:	in std_logic;
		key_in:	in std_logic_vector(3 downto 0);
		
		key_rdata	: out std_logic_vector(31 downto 0)
		
		
	);
end entity;


architecture Behavioral of gpio_key is

		signal key_sync1	: std_logic_vector(3 downto 0);
		signal key_sync2	: std_logic_vector(3 downto 0);

	
begin 

process(clk)

begin
	
	if rising_edge(clk) then
		if rst_n = '0' then
			key_sync1 <= (others => '0');--da vedere i valori rispetto ai pulsanti
			key_sync2 <= (others => '0');
		else 
		key_sync1 <= key_in;
		key_sync2 <= key_sync1;
		end if;
	end if;
		

end process;

key_rdata <= (31 downto 4 => '0') & key_sync2; 

end architecture Behavioral;