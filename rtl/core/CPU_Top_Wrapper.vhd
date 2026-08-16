-- SPDX-License-Identifier: Apache-2.0
-- Copyright 2026 Ozan Akgül
--
-- Licensed under the Apache License, Version 2.0 (the "License");
-- you may not use this file except in compliance with the License.
-- You may obtain a copy of the License at
--
--     http://www.apache.org/licenses/LICENSE-2.0
--
-- Unless required by applicable law or agreed to in writing, software
-- distributed under the License is distributed on an "AS IS" BASIS,
-- WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
-- See the License for the specific language governing permissions and
-- limitations under the License.

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
            rs2_debug   : out std_logic_vector(31 downto 0);
				mem_addr_out	: out std_logic_vector(DATA_WIDTH-1 downto 0);
			   mem_wdata_out: out std_logic_vector(DATA_WIDTH-1 downto 0);
			   mem_we_out	: out std_logic;
			   mem_re_out	: out std_logic;
			   mem_rdata_in	: in std_logic_vector(DATA_WIDTH-1 downto 0);
				funct3_out : out std_logic_vector(2 downto 0)
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

component Data_Memory is

	port(
	
		clk			:	in std_logic;
		mem_write	:	in std_logic;
		mem_read		:	in std_logic;
		funct3		:	in std_logic_vector(2 downto 0);
		addr			:	in	std_logic_vector(31 downto 0);
		write_data	:	in	std_logic_vector(31 downto 0);
		read_data	:	out	std_logic_vector(31 downto 0)
	
	);


end component;



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
	 
	 signal mmio_led_out : std_logic_vector(3 downto 0);
	 signal cpu_mem_funct3 : std_logic_vector(2 downto 0);
	 signal uart_tx_busy_bit : std_logic;
	 
	 
	 

begin

	-- Instantiate the Core Processor
	U_CPU : CPU_FPGA
	  port map (
			clk         => clk,
			rst_n         => rst_n,
			pc_debug    => pc_dbg,
			instr_debug => instr_dbg,
			rs1_debug   => rs1_dbg,
			rs2_debug   => rs2_dbg,
			mem_addr_out => cpu_mem_addr,
			mem_wdata_out => cpu_mem_wdata,
			mem_we_out => cpu_mem_we,
			mem_re_out => cpu_mem_re,
			mem_rdata_in => cpu_mem_rdata,
			funct3_out => cpu_mem_funct3
			
	  );
	
	U_BUS_DECODER	:	Bus_Decoder
		port map (
			addr => cpu_mem_addr,
			wdata => cpu_mem_wdata,
			mem_we => cpu_mem_we,
			mem_re => cpu_mem_re,
			ram_rdata => ram_rdata,
			key_rdata => key_rdata,
			uart_busy_rdata => uart_busy_rdata,
			timer_rdata => timer_rdata,
			rdata => cpu_mem_rdata,
			ram_cs => ram_cs,
			ram_we => ram_we,
			led_we => led_we,
			uart_tx_we => uart_tx_we
		
		
		);
		
	U_DATA_RAM : Data_Memory--to be declared component
		port map(
			clk => clk,
			mem_read  => ram_cs,
			mem_write => ram_we,
			addr       => cpu_mem_addr,
			write_data => cpu_mem_wdata,
			read_data  => ram_rdata,
			funct3	=> cpu_mem_funct3
		
		);
		
	U_GPIO_LED : gpio_led
		port map(
			clk => clk,
			rst_n => rst_n,
			we =>led_we,
			wdata => cpu_mem_wdata,
			led_out => mmio_led_out
		
		);
	
		--led_out <= mmio_led_out;	
		--it seems i need to deactivate the debug leds in order to connect these
		--to be checked later
		
	
	U_GPIO_KEY	: gpio_key
		port map (
			clk => clk,
			rst_n => rst_n,
			key_in => key_in, --top-level port
			key_rdata => key_rdata
		
		);
		
	U_TIMER	: timer
		port map(
			clk => clk,
			rst_n => rst_n,
			timer_rdata => timer_rdata
				
		);
	U_UART_TX	:	uart_tx
		port map (
			clk => clk,
			rst_n => rst_n,
			tx_data => cpu_mem_wdata(7 downto 0),
			tx_start => uart_tx_we,
			tx_busy => uart_tx_busy_bit,
			tx_out => uart_tx_pin --top-level port
		
		
		);
		
	uart_busy_rdata <= (31 downto 1 => '0') & uart_tx_busy_bit;	

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