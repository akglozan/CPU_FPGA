library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;

entity rv32im_soc is
    port (
        -- Clock and System Controls
        clk       : in  std_logic;
        rst_n     : in  std_logic;
        
        -- Physical Board Peripherals
        uart_rx   : in  std_logic;
        gpio_keys : in  std_logic_vector(3 downto 0);
        uart_tx   : out std_logic;
        gpio_leds : out std_logic_vector(3 downto 0)
    );
end entity rv32im_soc;

architecture Structural of rv32im_soc is

    -- Instruction Bus (IF Stage <-> BRAM Port A)
    signal pc          : std_logic_vector(31 downto 0);
    signal instr       : std_logic_vector(31 downto 0);
    
    -- Data Bus (MEM Stage <-> Bus Interconnect)
    signal mem_addr    : std_logic_vector(31 downto 0);
    signal mem_wdata   : std_logic_vector(31 downto 0);
    signal mem_rdata   : std_logic_vector(31 downto 0);
    signal mem_read    : std_logic;
    signal mem_write   : std_logic;
    signal mem_funct3  : std_logic_vector(2 downto 0);
    
    -- BRAM Port B Bus (Bus Interconnect <-> BRAM Port B)
    signal bram_addr   : std_logic_vector(9 downto 0);
    signal bram_wdata  : std_logic_vector(31 downto 0);
    signal bram_rdata  : std_logic_vector(31 downto 0);
    signal bram_we_b   : std_logic_vector(3 downto 0);
    
    -- Peripheral Read Buses
    signal uart_rdata  : std_logic_vector(31 downto 0);
    signal gpio_rdata  : std_logic_vector(31 downto 0);
    signal timer_rdata : std_logic_vector(31 downto 0);

    -- Internal MMIO Control Strobes
    signal uart_tx_data  : std_logic_vector(7 downto 0);
    signal uart_tx_start : std_logic;
    signal uart_tx_busy  : std_logic;
    signal gpio_we       : std_logic;
    signal timer_we      : std_logic;

begin

    -- 1. CPU Core Instantiation
    U_CPU : entity work.CPU_FPGA(Structural)
        port map (
            clk           => clk,
            rst_n         => rst_n,
            pc_debug      => pc,
            instr_debug   => instr,
            rs1_debug     => open,
            rs2_debug     => open,
            mem_addr_out  => mem_addr,
            mem_wdata_out => mem_wdata,
            mem_we_out    => mem_write,
            mem_re_out    => mem_read,
            mem_rdata_in  => mem_rdata,
            funct3_out    => mem_funct3
        );

    -- 2. Dual-Port 4 KB BRAM (Port A: Instruction, Port B: Data)
    U_BRAM : entity work.bram_4kb(rtl)
        generic map (
            HEX_FILE => "boot_bram.hex"
        )
        port map (
            clk     => clk,
            addr_a  => pc(11 downto 2),
            rdata_a => instr,
            addr_b  => bram_addr,
            wdata_b => bram_wdata,
            we_b    => bram_we_b,
            rdata_b => bram_rdata
        );

    -- 3. Bus Interconnect & MMIO Decoder
    U_BUS: entity work.bus_interconnect
        port map (
            clk         => clk,
            addr        => mem_addr,
            write_data  => mem_wdata,
            mem_read    => mem_read,
            mem_write   => mem_write,
            funct3      => mem_funct3,
            read_data   => mem_rdata,
            
            bram_addr   => bram_addr,
            bram_wdata  => bram_wdata,
            bram_we_b   => bram_we_b,
            bram_rdata  => bram_rdata,
            
            uart_data   => uart_tx_data,
            uart_we     => uart_tx_start,
            uart_rdata  => uart_rdata,
            
            gpio_we     => gpio_we,
            timer_we    => timer_we,
            gpio_rdata  => gpio_rdata,
            timer_rdata => timer_rdata
        );

    -- 4. UART Peripheral (0x80000000, 0x80000004)
    uart_rdata <= (31 downto 1 => '0') & uart_tx_busy;

    U_UART : entity work.uart_tx
        generic map (
            CLK_FREQ  => 50000000,
            BAUD_RATE => 115200
        )
        port map (
            clk      => clk,
            rst_n    => rst_n,
            tx_data  => uart_tx_data,
            tx_start => uart_tx_start,
            tx_busy  => uart_tx_busy,
            tx_out   => uart_tx
        );

    -- 5. GPIO Peripheral System (0x80000100)
    U_GPIO_LED : entity work.gpio_led(Behavioral)
        port map (
            clk     => clk,
            rst_n   => rst_n,
            we      => gpio_we,
            wdata   => mem_wdata,
            led_out => gpio_leds
        );

    U_GPIO_KEY : entity work.gpio_key(Behavioral)
        port map (
            clk       => clk,
            rst_n     => rst_n,
            key_in    => gpio_keys,
            key_rdata => gpio_rdata
        );

    -- 6. Hardware Cycle Timer (0x80000200)
    U_TIMER : entity work.timer(Behavioral)
        port map (
            clk         => clk,
            rst_n       => rst_n,
            timer_rdata => timer_rdata
        );

end architecture Structural;