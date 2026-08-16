library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;

entity bus_interconnect is
    port (
        clk         : in  std_logic;

        -- CPU Memory Interface
        addr        : in  std_logic_vector(31 downto 0);
        write_data  : in  std_logic_vector(31 downto 0);
        mem_write   : in  std_logic;
        mem_read    : in  std_logic;
        funct3      : in  std_logic_vector(2 downto 0);
        read_data   : out std_logic_vector(31 downto 0);

        -- BRAM Interface (Port B / Data Side: 1024 x 32-bit words)
        bram_addr   : out std_logic_vector(9 downto 0);
        bram_wdata  : out std_logic_vector(31 downto 0);
        bram_we_b   : out std_logic_vector(3 downto 0);
        bram_rdata  : in  std_logic_vector(31 downto 0);

        -- UART Interface
        uart_data   : out std_logic_vector(7 downto 0);
        uart_we     : out std_logic;
        uart_rdata  : in  std_logic_vector(31 downto 0);

        -- Peripheral Controls
        gpio_we     : out std_logic;
        timer_we    : out std_logic;
        gpio_rdata  : in  std_logic_vector(31 downto 0);
        timer_rdata : in  std_logic_vector(31 downto 0)
    );
end entity bus_interconnect;

architecture rtl of bus_interconnect is
    signal byte_enable : std_logic_vector(3 downto 0);
begin

    -- Word-aligned address indexing for 1024-word (4 KB) BRAM
    bram_addr  <= addr(11 downto 2);
    bram_wdata <= write_data;
    uart_data  <= write_data(7 downto 0);

    -- Generate byte-enables for store instructions (SB, SH, SW)
    process(funct3, addr, mem_write)
    begin
        if mem_write = '1' then
            case funct3 is
                when "000" => -- SB
                    case addr(1 downto 0) is
                        when "00"   => byte_enable <= "0001";
                        when "01"   => byte_enable <= "0010";
                        when "10"   => byte_enable <= "0100";
                        when others => byte_enable <= "1000";
                    end case;
                when "001" => -- SH
                    if addr(1) = '0' then
                        byte_enable <= "0011";
                    else
                        byte_enable <= "1100";
                    end if;
                when "010" => -- SW
                    byte_enable <= "1111";
                when others =>
                    byte_enable <= "1111";
            end case;
        else
            byte_enable <= "0000";
        end if;
    end process;

    -- Combinational bus decoding and read multiplexer
    process(addr, mem_write, mem_read, byte_enable, bram_rdata, uart_rdata, gpio_rdata, timer_rdata)
    begin
        bram_we_b <= (others => '0');
        uart_we   <= '0';
        gpio_we   <= '0';
        timer_we  <= '0';
        read_data <= (others => '0');

        if addr(31) = '0' then
            --------------------------------------------------------
            -- 0x00000000 - 0x00000FFF : 4 KB BRAM space
            --------------------------------------------------------
            bram_we_b <= byte_enable;
            read_data <= bram_rdata;

        elsif addr(31 downto 8) = x"800000" then
            --------------------------------------------------------
            -- 0x80000000 - 0x800000FF : UART Peripheral Range
            --------------------------------------------------------
            case addr(7 downto 0) is
                when x"00" =>
                    -- 0x80000000 : UART TX Data Register
                    if mem_write = '1' then
                        uart_we <= '1';
                    end if;
                    read_data <= (others => '0');

                when x"04" =>
                    -- 0x80000004 : UART Status Register
                    read_data <= uart_rdata;

                when others =>
                    read_data <= (others => '0');
            end case;

        elsif addr = x"80000100" then
            --------------------------------------------------------
            -- 0x80000100 : GPIO
            --------------------------------------------------------
            gpio_we   <= mem_write;
            read_data <= gpio_rdata;

        elsif addr = x"80000200" then
            --------------------------------------------------------
            -- 0x80000200 : Cycle Timer
            --------------------------------------------------------
            timer_we  <= mem_write;
            read_data <= timer_rdata;

        else
            read_data <= (others => '0');
        end if;
    end process;

end architecture rtl;