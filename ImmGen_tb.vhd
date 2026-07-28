library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;


entity ImmGen_tb is

end entity ImmGen_tb;


architecture Behavior of ImmGen_tb is

	component ImmGen is
		port(
	
		inst		: in		std_logic_vector(31 downto 0);
		imm_src	: in		std_logic_vector(2 downto 0);
		
		imm_ext 	: out 	std_logic_vector(31 downto 0)
	);
	end component immGen;
	
	signal tb_inst	:	std_logic_vector(31 downto 0) := (others => '0');
	signal tb_imm_src : std_logic_vector(2 downto 0) := (others => '0');
	
	signal tb_imm_ext : std_logic_vector(31 downto 0);
	
	begin
	
	DUT: entity work.ImmGen
		port map (
			inst => tb_inst,
			imm_src => tb_imm_src,
			imm_ext => tb_imm_ext
		);
		
		test_process : process
		begin
		
		-- Test Case 1: I-Type (ADDI x1, x2, -1)
		-- Expected Output: 0xFFFFFFFF (-1 sign-extended)
		tb_inst <= x"FFF10093";
		tb_imm_src <= "000";
		
		wait for 10 ns;
		
		assert(tb_imm_ext = x"FFFFFFFF")
			report "ERROR: I-Type failed!" severity error;
		
		-- Test Case 2: S-Type (SW x1, 4(x2))
		-- Expected Output: 0x00000004 (+4 sign-extended)	
		tb_inst <= x"00112223";
		tb_imm_src <= "001";
		
		wait for 10 ns;
		
		assert(tb_imm_ext = x"00000004")
			report "ERROR: S-Type failed!" severity error;
		
		-- Test Case 3: B-Type (BEQ x0, x0, -4)
		-- Expected Output: 0xFFFFFFFC (-4 sign-extended, LSB=0)
		tb_inst <= x"FE000EE3";
		tb_imm_src <= "010";
		
		wait for 10 ns;
		
		assert(tb_imm_ext = x"FFFFFFFC")
			report "ERROR: B-Type failed!" severity error;
			
		-- Test Case 4: U-Type (LUI x1, 0x12345)
		-- Expected Output: 0x12345000 (Upper 20 bits, lower 12 bits zero-padded)
		tb_inst <= x"123450B7";
		tb_imm_src <= "011";
		
		wait for 10 ns;
		
		assert(tb_imm_ext = x"12345000")
			report "ERROR: U-Type failed!" severity error;
		
		-- Test Case 5: J-Type (JAL x1, -2)
		-- Expected Output: 0xFFFFFFFE (-2 sign-extended, LSB=0)
		tb_inst <= x"FFFFF0EF";
		tb_imm_src <= "100";
		
		wait for 10 ns;
		-- result calculated: 111111111111.11111111.
		assert(tb_imm_ext = x"FFFFFFFE")
			report "ERROR: J-Type failed!" severity error;	
			
			
		
		report "ImmGen testbench completed successfully!";
		wait;
		
		end process;
		
end architecture Behavior;
		