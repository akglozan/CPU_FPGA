library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;

entity CPU_Top_Wrapper is
    port (
        clk           : in	std_logic;                      -- Physical Board Clock
        rst_n         : in	std_logic;                      -- Physical Reset Switch
        debug_sel     : in	std_logic_vector(1 downto 0);   -- MUX Select (Switches)
        key_in			 : in	std_logic_vector(3 downto 0);
		  led_out       : out std_logic_vector(3 downto 0);    -- 4 Onboard Diagnostic LEDs
		  uart_tx_pin	 : out std_logic
	 );							

end entity CPU_Top_Wrapper;

architecture Structural of CPU_Top_Wrapper is

    component CPU_FPGA is
        generic ( DATA_WIDTH : integer := 32 );
        port (
            clk         : in  std_logic;
            rst_n       : in  std_logic;
            pc_debug    : out std_logic_vector(31 downto 0);
            instr_debug : out std_logic_vector(31 downto 0);
            rs1_debug   : out std_logic_vector(31 downto 0);
            rs2_debug   : out std_logic_vector(31 downto 0)
        );
    end component;
	 
	 component Bus_Decoder is
    
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
end component Bus_Decoder;

component gpio_led is

	port(
		clk 	:	in std_logic;
		rst_n	:	in std_logic;
		--Write Enable Strobe
		we		:	in std_logic;
		--CPU Write Data
		wdata	:	in std_logic_vector(31 downto 0);
		
		led_out	: out std_logic_vector(3 downto 0)--Have 4 leds available on the board, can be upgraded
			
	);
end component;


component gpio_key is

	port(
		clk 	:	in std_logic;
		rst_n	:	in std_logic;
		key_in:	in std_logic_vector(3 downto 0);
		
		key_rdata	: out std_logic_vector(31 downto 0)
		
		
	);
end component;

component timer is

	port(
	
		clk		:	in std_logic;
		rst_n		: 	in std_logic;
		
		timer_rdata	: out std_logic_vector(31 downto 0)
	
	);


end component;

component uart_tx is
    generic (
        CLK_FREQ  : integer := 50_000_000; -- 50 MHz system clock
        BAUD_RATE : integer := 115_200     -- Target baud rate
    );
    port (
        clk      : in  std_logic;
        rst_n      : in  std_logic;
        -- MMIO Interface
        tx_data  : in  std_logic_vector(7 downto 0);
        tx_start : in  std_logic;
        tx_busy  : out std_logic;
        -- Physical Output Pin
        tx_out   : out std_logic
    );
end component uart_tx;





    signal pc_dbg    : std_logic_vector(31 downto 0);
    signal instr_dbg : std_logic_vector(31 downto 0);
    signal rs1_dbg   : std_logic_vector(31 downto 0);
    signal rs2_dbg   : std_logic_vector(31 downto 0);
	 
	 --CPU / Bus Decoder Memory Interface
	 signal cpu_mem_addr	: std_logic_vector(31 downto 0);
	 signal cpu_mem_wdata: std_logic_vector(31 downto 0);
	 signal cpu_mem_we	: std_logic;
	 signal cpu_mem_re	: std_logic;
	 signal cpu_mem_rdata: std_logic_vector(31 downto 0);
	 
	 --Data RAM Interconnects
	 signal ram_cs		: std_logic;
	 signal ram_we		: std_logic;
	 signal ram_rdata	: std_logic_vector(31 downto 0);
	 
	 --MMIO Peripheral Write Strobes
	 signal led_we	: std_logic;
	 signal uart_tx_we	: std_logic;
	 
	 --MMIO Peripheral Read Buses
	 signal key_rdata			: std_logic_vector(31 downto 0);
	 signal uart_busy_rdata	: std_logic_vector(31 downto 0);
	 signal timer_rdata		: std_logic_vector(31 downto 0);
	 
	 
	 

begin

	-- Instantiate the Core Processor
	U_CPU : CPU_FPGA
	  port map (
			clk         => clk,
			rst_n         => rst_n,
			pc_debug    => pc_dbg,
			instr_debug => instr_dbg,
			rs1_debug   => rs1_dbg,
			rs2_debug   => rs2_dbg
	  );
	--have to start initiating other comps

    -- Time-Multiplex 128 Bits down to 8 Output Pins
    process(debug_sel, pc_dbg, instr_dbg, rs1_dbg, rs2_dbg)
    begin
        case debug_sel is
            when "00"   => led_out <= pc_dbg(3 downto 0);        -- Low byte of PC
            when "01"   => led_out <= instr_dbg(3 downto 0);     -- Low byte of Instruction
            when "10"   => led_out <= rs1_dbg(3 downto 0);       -- Low byte of RS1
            when "11"   => led_out <= rs2_dbg(3 downto 0);       -- Low byte of RS2
            when others => led_out <= (others => '0');
        end case;
    end process;

end architecture Structural;