library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;


entity MEM_WB_Register is

	port(
	
	--System Inputs
		clk					:	in	std_logic;
		reset					:	in	std_logic;
		stall					:	in std_logic;
		flush					:	in std_logic;
		
	--Data Inputs (from MEM Stage)
		mem_result_in		:	in std_logic_vector(31 downto 0);
		mem_read_data_in	:	in std_logic_vector(31 downto 0);
		rd_addr_in			:	in	std_logic_vector(4 downto 0);
		
	--Control Inputs (from MEM Stage)
		reg_write_in		:	in	std_logic;
		wb_sel_in			:	in std_logic_vector(1 downto 0);
		
	--Outputs (to WB Stage & Forwarding Unit):
		wb_result_out		:	out	std_logic_vector(31 downto 0);
		wb_read_data_out	:	out	std_logic_vector(31 downto 0);
		wb_rd_addr_out		:	out	std_logic_vector(4 downto 0);
		wb_reg_write_out	:	out	std_logic;
		wb_sel_out			:	out	std_logic_vector(1 downto 0) 

	
	);


end entity;

architecture Behavioral of MEM_WB_Register is

begin

process(clk)
begin

	if rising_edge(clk) then
		if reset = '1' or flush = '1' then
			wb_result_out    <= (others => '0');
			 wb_read_data_out <= (others => '0');
			 wb_rd_addr_out   <= (others => '0');
			 wb_reg_write_out <= '0';
			 wb_sel_out       <= (others => '0');
			 
		elsif stall = '1' then
                null;
		
		else
			 wb_result_out    <= mem_result_in;
			 wb_read_data_out <= mem_read_data_in;
			 wb_rd_addr_out   <= rd_addr_in;
			 wb_reg_write_out <= reg_write_in;
			 wb_sel_out       <= wb_sel_in;
		
		
		end if;
	end if;
end process;	
	




end architecture;