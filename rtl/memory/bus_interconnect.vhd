library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;

entity bus_interconnect is
    port (
        clk         : in  std_logic;
        
        -- CPU Stage Interface (From/To MEM Stage)
        addr        : in  std_logic_vector(31 downto 0);
        write_data  : in  std_logic_vector(31 downto 0);
        mem_read    : in  std_logic;
        mem_write   : in  std_logic;
        funct3      : in  std_logic_vector(2 downto 0);
        read_data   : out std_logic_vector(31 downto 0); 
        
        -- BRAM Interface (Port B)
        bram_addr   : out std_logic_vector(9 downto 0);
        bram_wdata  : out std_logic_vector(31 downto 0); 
        bram_we_b   : out std_logic_vector(3 downto 0);
        bram_rdata  : in  std_logic_vector(31 downto 0); 
        
        -- Peripheral Inputs (Read Data From MMIO Cores)
        uart_rdata  : in  std_logic_vector(31 downto 0); 
        gpio_rdata  : in  std_logic_vector(31 downto 0); 
        timer_rdata : in  std_logic_vector(31 downto 0)  
    );
end entity;

architecture rtl of bus_interconnect is

begin

process(mem_write, addr, funct3, write_data)
begin
    -- Default outputs to prevent synthesis latches
    bram_we_b  <= "0000";
    bram_wdata <= write_data;
    
    if (mem_write = '1') and (addr(31 downto 12) = x"00000") then
        case funct3 is
            -- SW: Store Word
            when "010" =>
                bram_we_b  <= "1111";
                bram_wdata <= write_data;

            -- SH: Store Half-word
            when "001" =>
                bram_wdata <= write_data(15 downto 0) & write_data(15 downto 0);
                if addr(1) = '0' then
                    bram_we_b <= "0011";
                else
                    bram_we_b <= "1100";
                end if;

            -- SB: Store Byte
            when "000" =>
                bram_wdata <= write_data(7 downto 0) & write_data(7 downto 0) & 
                              write_data(7 downto 0) & write_data(7 downto 0);
                case addr(1 downto 0) is
                    when "00"   => bram_we_b <= "0001";
                    when "01"   => bram_we_b <= "0010";
                    when "10"   => bram_we_b <= "0100";
                    when others => bram_we_b <= "1000";
                end case;

            when others =>
                bram_we_b <= "0000";
        end case;
    end if;
end process;

end architecture;