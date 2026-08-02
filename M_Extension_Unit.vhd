library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;

entity M_Extension_Unit is

	port(
	
	--System Inputs
		clk	:	in std_logic;
		reset	:	in std_logic;
		
	--Control Inputs
		is_m_ext	: 	in std_logic;
		funct3	:	in std_logic_vector(2 downto 0);
		
	--Data Inputs
		operand_a	: in std_logic_vector(31 downto 0);
		operand_b	: in std_logic_vector(31 downto 0);
		
	--Data Outputs
		m_result		: out std_logic_vector(31 downto 0);
		
	--Status Outputs
		stall_m		: out std_logic
		
	
	);


end entity;


architecture Behavioral of M_Extension_Unit is

begin

process(clk)



end architecture;