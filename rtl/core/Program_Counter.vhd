library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;

entity Program_Counter is
	generic(
	
	data_width:integer :=32
	
	);
	
	port(
		clk		:	in	std_logic;
		
		rst		:	in	std_logic;
		
		pc_write :	in	std_logic; -- Write Enable / Stall Signal
		
		pc_src	:	in std_logic; -- Jump/Branch Control
		
		target_pc:	in std_logic_vector(DATA_WIDTH-1 downto 0); --Target Address
		
	
      pc_out   :	out std_logic_vector(DATA_WIDTH-1 downto 0); --Current PC

		pc_plus4	:	out std_logic_vector(DATA_WIDTH-1 downto 0)  --Next PC / PC+4
	
	);
end entity Program_Counter;


architecture Behavioral of Program_Counter is
	signal pc_reg : unsigned (DATA_WIDTH-1 downto 0) := (others => '0');
	
begin 

process(clk)
begin
	if rising_edge(clk) then
		if rst = '1' then
				pc_reg <= (others => '0');
		elsif pc_write = '1' then
				if pc_src ='1' then
					pc_reg <= unsigned(target_pc);
				else
					pc_reg <= pc_reg + 4; ---'4' indicates a 4 byte(32 bit) 
				end if;	
		end if;
	end if;		
end process;

pc_out <= std_logic_vector(pc_reg);
pc_plus4 <= std_logic_vector(pc_reg +4);

end architecture Behavioral;