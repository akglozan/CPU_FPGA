library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;

entity Bus_Decoder is
    
    port (
		
		 --CPU Address Bus
       addr			:	in std_logic_vector(31 downto 0);
		 --CPU Write Data
		 wdata		:	in std_logic_vector(31 downto 0);
		 --CPU Write Enable
		 mem_we		:	in std_logic;
		 --CPU Read Enable
		 mem_re		:	in std_logic;
		 --Data RAM Read Port
		 ram_rdata	:	in	std_logic_vector(31 downto 0);
		 --Peripheral Read Inputs
		 key_rdata			:	in std_logic_vector(31 downto 0);
		 uart_busy_rdata	:	in std_logic_vector(31 downto 0);
		 timer_rdata		:	in std_logic_vector(31 downto 0);
		 
		 --CPU Read Data Bus
		 rdata		:	out std_logic_vector(31 downto 0);
		 
		 --Data RAM Controls
		 ram_cs		:	out std_logic;
		 ram_we		:	out std_logic;
		 --Peripheral Write Strobes
		 led_we		:	out std_logic;
		 uart_tx_we	:	out std_logic
		 
    );
end entity Bus_Decoder;

architecture Behavioral of Bus_Decoder is

	--Address Region Indicator
	signal is_mmio	:	std_logic;
	--Local Offset Vector
	signal offset	:	std_logic_vector(7 downto 0);
	
begin

	is_mmio <= addr(31);
   offset  <= addr(7 downto 0);

--Write & Control Decoding Process (Combinational)
process(all)
begin
	
	

	--Default Signal Assignments
	ram_cs 		<= '0';
	ram_we		<= '0';
	led_we		<= '0';
	uart_tx_we	<= '0';
	
	--RAM Select Logic
	if is_mmio = '0' then
		ram_we <= mem_we;
		if mem_re = '1' or mem_we = '1' then
			ram_cs <= '1';
		end if;
	--MMIO Write Decode Tree	
	else
		if mem_we = '1' then
			case offset is
				when x"00" =>
					led_we <= '1';
				when x"08" =>
					uart_tx_we <= '1';
				when others =>
					null;
			end case;
		else
			null;
		end if;
	end if;
	
end process;	

--Read Data Multiplexer Process (Combinational)
process(all)
begin

	--Default Multiplexer Output
	rdata <= (others => '0');
	
	--Region Slicing Mux Logic
	if is_mmio = '0' then
	rdata <= ram_rdata;
	else
		case offset is
			when x"04" =>
				rdata <= key_rdata;
			when x"0C" =>
				rdata <= uart_busy_rdata;
			when x"10" =>
				rdata <=	timer_rdata;
			when others =>
				rdata <= (others => '0');
		end case;
	end if;	
	


end process;


end architecture;