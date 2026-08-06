library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;


entity Data_Memory is

	port(
	
		clk			:	in std_logic;
		mem_write	:	in std_logic;
		mem_read		:	in std_logic;
		funct3			:	in std_logic_vector(2 downto 0);
		addr			:	in	std_logic_vector(31 downto 0);
		write_data	:	in	std_logic_vector(31 downto 0);
		read_data	:	out	std_logic_vector(31 downto 0)
	
	);


end entity;

architecture Behavioral of Data_Memory is

    -- 1,024 words x 32 bits = 4 KB BRAM array
    type ram_type is array (0 to 1023) of std_logic_vector(31 downto 0);
    signal ram : ram_type := (others => (others => '0'));

    -- Internal signals
    signal byte_enable        : std_logic_vector(3 downto 0);
    signal aligned_write_data : std_logic_vector(31 downto 0);
    signal raw_read_data      : std_logic_vector(31 downto 0);
    signal addr_latched       : std_logic_vector(1 downto 0);

begin

    -------------------------------------------------------------------
    -- 1. Combinational Write Byte-Enable & Alignment Decoder
    -------------------------------------------------------------------
    process(all)
    begin
        byte_enable <= "0000";
        
        if mem_write = '1' then
            case funct3 is
                when "010" => -- SW (Store Word)
                    byte_enable <= "1111";
                    
                when "001" => -- SH (Store Halfword)
                    if addr(1) = '0' then   
                        byte_enable <= "0011";
                    else
                        byte_enable <= "1100";
                    end if;
                    
                when "000" => -- SB (Store Byte)
                    case addr(1 downto 0) is
                        when "00"   => byte_enable <= "0001";
                        when "01"   => byte_enable <= "0010";
                        when "10"   => byte_enable <= "0100";
                        when "11"   => byte_enable <= "1000";
                        when others => byte_enable <= "0000";
                    end case;
                    
                when others =>
                    byte_enable <= "0000";
            end case;
        end if;
    end process;

    -- Byte Replication Shortcut: Replicates bytes across all lanes;
    -- hardware byte_enable handles targeting the exact lane.
    with funct3 select
        aligned_write_data <= write_data                                          when "010", -- SW
                              write_data(15 downto 0) & write_data(15 downto 0) when "001", -- SH
                              write_data(7 downto 0)  & write_data(7 downto 0) & 
                              write_data(7 downto 0)  & write_data(7 downto 0)  when "000", -- SB
                              (others => '0')                                     when others;

    -------------------------------------------------------------------
    -- 2. Synchronous BRAM Array (Sequential Read/Write)
    -------------------------------------------------------------------
    process(clk)
        variable ram_index : integer range 0 to 1023;
    begin
        if rising_edge(clk) then
            ram_index := to_integer(unsigned(addr(11 downto 2)));

            -- Byte-masked Write Operation
            for i in 0 to 3 loop
                if byte_enable(i) = '1' then
                    ram(ram_index)(8*i+7 downto 8*i) <= aligned_write_data(8*i+7 downto 8*i);
                end if;
            end loop;

            -- Synchronous Read Operation
            raw_read_data <= ram(ram_index);
            
            -- Latch address offset for read alignment on following cycle
            addr_latched <= addr(1 downto 0);
        end if;
    end process;

    -------------------------------------------------------------------
    -- 3. Combinational Read Data Formatting & Sign Extender
    -------------------------------------------------------------------
    process(all)
        variable selected_byte     : std_logic_vector(7 downto 0);
        variable selected_halfword : std_logic_vector(15 downto 0);
    begin
        -- Extract byte based on latched address offset
        case addr_latched is
            when "00"   => selected_byte := raw_read_data(7 downto 0);
            when "01"   => selected_byte := raw_read_data(15 downto 8);
            when "10"   => selected_byte := raw_read_data(23 downto 16);
            when "11"   => selected_byte := raw_read_data(31 downto 24);
            when others => selected_byte := (others => '0');
        end case;

        -- Extract halfword based on latched address offset bit 1
        if addr_latched(1) = '0' then
            selected_halfword := raw_read_data(15 downto 0);
        else
            selected_halfword := raw_read_data(31 downto 16);
        end if;

        -- Apply Sign / Zero Extension based on funct3
        case funct3 is
            when "000" => -- LB (Load Byte, Sign-Extended)
                read_data <= std_logic_vector(resize(signed(selected_byte), 32));
                
            when "100" => -- LBU (Load Byte Unsigned, Zero-Extended)
                read_data <= std_logic_vector(resize(unsigned(selected_byte), 32));
                
            when "001" => -- LH (Load Halfword, Sign-Extended)
                read_data <= std_logic_vector(resize(signed(selected_halfword), 32));
                
            when "101" => -- LHU (Load Halfword Unsigned, Zero-Extended)
                read_data <= std_logic_vector(resize(unsigned(selected_halfword), 32));
                
            when "010" => -- LW (Load Word)
                read_data <= raw_read_data;
                
            when others =>
                read_data <= (others => '0');
        end case;
    end process;

end architecture Behavioral;

