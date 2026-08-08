library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;

entity timer is

	port(
	
		clk		:	in std_logic;
		rst_n		: 	in std_logic;
		
		timer_rdata	: out std_logic_vector(31 downto 0)
	
	);


end entity;

architecture Behavioral of timer is

	signal counter_reg : unsigned(31 downto 0);

begin

process(clk)
begin

	if rising_edge(clk) then
		if rst_n = '0' then
			counter_reg <= (others => '0');
		else
		counter_reg <= counter_reg + 1;
		end if;
	end if;

end process;

timer_rdata <= std_logic_vector(counter_reg);

end architecture;
