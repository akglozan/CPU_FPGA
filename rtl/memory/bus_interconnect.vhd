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
end entity bus_interconnect;

architecture rtl of bus_interconnect is
begin

    -- Continuous word-aligned address mapping for 4 KB BRAM (1024 x 32-bit words)
    bram_addr <= addr(11 downto 2);

    -- Combinatorial Store Logic: Byte Enable & Write Data Steering
    process(mem_write, addr, funct3, write_data)
    begin
        -- Defaults to prevent synthesis latches
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

    -- Combinatorial Load Logic: Sub-word Extraction & MMIO Multiplexing
    process(addr, funct3, bram_rdata, uart_rdata, gpio_rdata, timer_rdata)
        variable v_byte : std_logic_vector(7 downto 0);
        variable v_half : std_logic_vector(15 downto 0);
    begin
        -- Default assignment to avoid floating signals or latches
        read_data <= (others => '0');

        -- BRAM Address Space (0x00000000 - 0x00000FFF)
        if addr(31 downto 12) = x"00000" then
            case funct3 is
                -- LW: Load Word
                when "010" =>
                    read_data <= bram_rdata;

                -- LH / LHU: Load Half-word
                when "001" | "101" =>
                    -- 1. Isolate target half-word
                    if addr(1) = '0' then
                        v_half := bram_rdata(15 downto 0);
                    else
                        v_half := bram_rdata(31 downto 16);
                    end if;

                    -- 2. Format output using v_half(15) as sign bit reference
                    if funct3(2) = '0' then  -- LH (Signed)
                        read_data <= (31 downto 16 => v_half(15)) & v_half;
                    else                     -- LHU (Unsigned)
                        read_data <= x"0000" & v_half;
                    end if;

                -- LB / LBU: Load Byte
                when "000" | "100" =>
                    -- 1. Isolate target byte
                    case addr(1 downto 0) is
                        when "00"   => v_byte := bram_rdata(7 downto 0);
                        when "01"   => v_byte := bram_rdata(15 downto 8);
                        when "10"   => v_byte := bram_rdata(23 downto 16);
                        when others => v_byte := bram_rdata(31 downto 24);
                    end case;

                    -- 2. Format output using v_byte(7) as sign bit reference
                    if funct3(2) = '0' then  -- LB (Signed)
                        read_data <= (31 downto 8 => v_byte(7)) & v_byte;
                    else                     -- LBU (Unsigned)
                        read_data <= x"000000" & v_byte;
                    end if;

                when others =>
                    read_data <= bram_rdata;
            end case;

        -- UART Peripheral Range (0x80000000 - 0x80000004)
        elsif addr(31 downto 12) = x"80000" and addr(11 downto 4) = x"00" then
            read_data <= uart_rdata;

        -- GPIO Peripheral Range (0x80000100 - 0x80000104)
        elsif addr(31 downto 12) = x"80000" and addr(11 downto 4) = x"10" then
            read_data <= gpio_rdata;

        -- Cycle Timer Register (0x80000200)
        elsif addr(31 downto 12) = x"80000" and addr(11 downto 4) = x"20" then
            read_data <= timer_rdata;

        -- Unmapped Address Space Catch-All
        else
            read_data <= (others => '0');
        end if;
    end process;

end architecture rtl;