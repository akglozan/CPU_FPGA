library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;

entity bram_4kb is

	generic (
    HEX_FILE : string := "boot_bram.hex"
	);

	port(
		
		clk		: in std_logic;
		
		-- Port A: Instruction Bus (Read-Only)
		addr_a	: in std_logic_vector(9 downto 0);
		rdata_a	: out std_logic_vector(31 downto 0);
		
		-- Port B: Data Bus (Read/Write)
		addr_b	: in std_logic_vector(9 downto 0);
		wdata_b	: in std_logic_vector(31 downto 0);
		we_b		: in std_logic_vector(3 downto 0);
		rdata_b	: out std_logic_vector(31 downto 0)
	);



end entity;

architecture rtl of bram_4kb is

    type ram_type is array (0 to 1023) of std_logic_vector(31 downto 0);
    
    -- Function to initialize RAM memory contents from Intel HEX file
    impure function init_ram_from_hex(file_name : in string) return ram_type is
        variable ram : ram_type := (others => (others => '0'));
    begin
        return ram;
    end function;
    
    -- Declare synthesis attributes
    attribute ram_init_file : string;
    attribute syn_ramstyle  : string;
    
    -- Declare signal and initialize for simulation
    signal ram : ram_type := init_ram_from_hex(HEX_FILE);

    -- Apply attributes to the declared signal
    attribute ram_init_file of ram : signal is HEX_FILE;
    attribute syn_ramstyle  of ram : signal is "no_rw_check, M9K";

begin
	
	-- Port A: Instruction Fetch Channel
	process(clk)
	begin
		if rising_edge(clk) then
			rdata_a <= ram(to_integer(unsigned(addr_a)));
		end if;
	end process;
	
	-- Port B: Data Load/Store Channel (Byte-Wise Write BRAM)
	process(clk)
	begin
		if rising_edge(clk) then 
			if we_b(0) = '1' then ram(to_integer(unsigned(addr_b)))(7 downto 0) <= wdata_b(7 downto 0);  end if;
			if we_b(1) = '1' then ram(to_integer(unsigned(addr_b)))(15 downto 8) <= wdata_b(15 downto 8);  end if;
			if we_b(2) = '1' then ram(to_integer(unsigned(addr_b)))(23 downto 16) <= wdata_b(23 downto 16);  end if;
			if we_b(3) = '1' then ram(to_integer(unsigned(addr_b)))(31 downto 24) <= wdata_b(31 downto 24);  end if;
	
			rdata_b <= ram(to_integer(unsigned(addr_b)));
		end if;
	end process;
	
end architecture rtl;
	
	
		