library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;

entity IF_ID_Register is

	port(
	
		clk		: in std_logic;
		rst		: in std_logic;

		/*Hazard control signal. 
		When stall = '1', the register holds its current value 
		freezes execution).*/
		stall 	: in std_logic; 
		
		
		/*Control hazard signal (e.g., taken branch/jump).
		When flush = '1', the register clears the instruction 
		to a NOP (0x00000013 in RISC-V, which is addi x0, x0, 0).
		*/
		flush 	: in std_logic;
		
		--Program Counter from IF stage.
		pc_in 	: in std_logic_vector(31 downto 0);
		
		--Instruction fetched from Instruction Memory.
		instruction_in	: in std_logic_vector(31 downto 0);
		
		--Program Counter passed to ID stage.
		pc_out	: out std_logic_vector(31 downto 0);
		
		--Instruction passed to ID stage.
		instruction_out	: out std_logic_vector(31 downto 0)
		
		
	
	);
end entity;
	
	
architecture Behavioral of IF_ID_Register is

begin

process(clk)
begin

	if rising_edge(clk) then
		if rst = '1' then
			pc_out <= (others => '0');
			instruction_out <= x"00000013";
		elsif flush = '1' then
			instruction_out <= x"00000013";
			pc_out <= (others => '0');
		elsif stall = '1' then
			null;
		else
			pc_out <= pc_in;
			instruction_out <= instruction_in;
		end if;
	end if;
end process;


end architecture Behavioral;


