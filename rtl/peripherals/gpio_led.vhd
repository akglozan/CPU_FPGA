library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;

entity gpio_led is

	port(
		clk 	:	in std_logic;
		rst_n	:	in std_logic;
		--Write Enable Strobe
		we		:	in std_logic;
		--CPU Write Data
		wdata	:	in std_logic_vector(31 downto 0);
		
		led_out	: out std_logic_vector(3 downto 0)--Have 4 leds available on the board, can be upgraded
			
	);
end entity;


architecture Behavioral of gpio_led is
	
	signal led_reg	: std_logic_vector(3 downto 0);
	
begin 

process(clk)

begin

	if rising_edge(clk) then
		if rst_n = '0' then
			led_reg <= (others => '0');
		elsif we = '1' then
			led_reg <= wdata(3 downto 0);
		end if;
	end if;
end process;

led_out <= led_reg;

end architecture Behavioral;