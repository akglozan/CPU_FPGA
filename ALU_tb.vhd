library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;

entity ALU_tb is
end entity ALU_tb;

architecture Behavior of ALU_tb is

	component ALU is
		port (
			alu_ctrl   : in  std_logic_vector(3 downto 0);
			operand_a  : in  std_logic_vector(31 downto 0);
			operand_b  : in  std_logic_vector(31 downto 0);
			alu_result : out std_logic_vector(31 downto 0);
			zero_flag  : out std_logic
		);
	end component ALU;
	
	signal tb_alu_ctrl   : std_logic_vector(3 downto 0) := (others => '0');
	signal tb_operand_a  : std_logic_vector(31 downto 0) := (others => '0');
	signal tb_operand_b  : std_logic_vector(31 downto 0) := (others => '0');
	signal tb_alu_result : std_logic_vector(31 downto 0);
	signal tb_zero_flag  : std_logic;
	
begin
	
	DUT: entity work.ALU
		port map (
			alu_ctrl   => tb_alu_ctrl,
			operand_a  => tb_operand_a,
			operand_b  => tb_operand_b,
			alu_result => tb_alu_result,
			zero_flag  => tb_zero_flag
		);
		
	test_process : process
	begin
		
		-----------------------------------------------------------------------
		-- 1. ADD: Positive + Positive
		-----------------------------------------------------------------------
		tb_alu_ctrl  <= "0000";
		tb_operand_a <= x"0000000F"; -- 15
		tb_operand_b <= x"00000001"; -- 1
		wait for 10 ns;
		assert (tb_alu_result = x"00000010" and tb_zero_flag = '0')
			report "ADD Test 1 Failed: 15 + 1" severity error;
			
		-----------------------------------------------------------------------
		-- 2. ADD: Two's complement addition with overflow bit ignored (-5 + 5)
		-----------------------------------------------------------------------
		tb_alu_ctrl  <= "0000";
		tb_operand_a <= x"FFFFFFFB"; -- -5
		tb_operand_b <= x"00000005"; -- +5
		wait for 10 ns;
		assert (tb_alu_result = x"00000000" and tb_zero_flag = '1')
			report "ADD Test 2 (Zero Flag) Failed: -5 + 5" severity error;

		-----------------------------------------------------------------------
		-- 3. SUB: Standard Subtraction (20 - 5)
		-----------------------------------------------------------------------
		tb_alu_ctrl  <= "0001";
		tb_operand_a <= x"00000014"; -- 20
		tb_operand_b <= x"00000005"; -- 5
		wait for 10 ns;
		assert (tb_alu_result = x"0000000F" and tb_zero_flag = '0')
			report "SUB Test 1 Failed: 20 - 5" severity error;

		-----------------------------------------------------------------------
		-- 4. SUB: Branch equal comparison resulting in zero (10 - 10)
		-----------------------------------------------------------------------
		tb_alu_ctrl  <= "0001";
		tb_operand_a <= x"0000000A"; -- 10
		tb_operand_b <= x"0000000A"; -- 10
		wait for 10 ns;
		assert (tb_alu_result = x"00000000" and tb_zero_flag = '1')
			report "SUB Test 2 (Zero Flag) Failed: 10 - 10" severity error;

		-----------------------------------------------------------------------
		-- 5. SLL: Shift Left Logical (0x0000000F shifted left by 4)
		-----------------------------------------------------------------------
		tb_alu_ctrl  <= "0010";
		tb_operand_a <= x"0000000F";
		tb_operand_b <= x"00000004"; -- Shift by 4
		wait for 10 ns;
		assert (tb_alu_result = x"000000F0")
			report "SLL Test Failed" severity error;

		-----------------------------------------------------------------------
		-- 6. SLT: Signed Set-Less-Than (-1 < +1 -> True)
		-----------------------------------------------------------------------
		tb_alu_ctrl  <= "0011";
		tb_operand_a <= x"FFFFFFFE"; -- -2
		tb_operand_b <= x"00000001"; -- +1
		wait for 10 ns;
		assert (tb_alu_result = x"00000001")
			report "SLT Signed Test Failed: -2 < 1 should be True" severity error;

		-----------------------------------------------------------------------
		-- 7. SLTU: Unsigned Set-Less-Than (0xFFFFFFFF < 0x00000001 -> False)
		-----------------------------------------------------------------------
		tb_alu_ctrl  <= "0100";
		tb_operand_a <= x"FFFFFFFE"; -- 4294967294 unsigned
		tb_operand_b <= x"00000001"; -- 1 unsigned
		wait for 10 ns;
		assert (tb_alu_result = x"00000000")
			report "SLTU Unsigned Test Failed: MAX_UINT < 1 should be False" severity error;

		-----------------------------------------------------------------------
		-- 8. XOR: Bitwise XOR
		-----------------------------------------------------------------------
		tb_alu_ctrl  <= "0101";
		tb_operand_a <= x"FF00FF00";
		tb_operand_b <= x"0F0F0F0F";
		wait for 10 ns;
		assert (tb_alu_result = x"F00FF00F")
			report "XOR Test Failed" severity error;

		-----------------------------------------------------------------------
		-- 9. SRL: Shift Right Logical (Zero-extension check)
		-----------------------------------------------------------------------
		tb_alu_ctrl  <= "0110";
		tb_operand_a <= x"80000000";
		tb_operand_b <= x"00000004"; -- Shift by 4
		wait for 10 ns;
		assert (tb_alu_result = x"08000000")
			report "SRL Test Failed: Should zero-extend MSB" severity error;

		-----------------------------------------------------------------------
		-- 10. SRA: Shift Right Arithmetic (Sign-extension check)
		-----------------------------------------------------------------------
		tb_alu_ctrl  <= "0111";
		tb_operand_a <= x"80000000"; -- Negative MSB = 1
		tb_operand_b <= x"00000004"; -- Shift by 4
		wait for 10 ns;
		assert (tb_alu_result = x"F8000000")
			report "SRA Test Failed: Should sign-extend MSB" severity error;

		-----------------------------------------------------------------------
		-- 11. OR: Bitwise OR
		-----------------------------------------------------------------------
		tb_alu_ctrl  <= "1000";
		tb_operand_a <= x"12340000";
		tb_operand_b <= x"00005678";
		wait for 10 ns;
		assert (tb_alu_result = x"12345678")
			report "OR Test Failed" severity error;

		-----------------------------------------------------------------------
		-- 12. AND: Bitwise AND
		-----------------------------------------------------------------------
		tb_alu_ctrl  <= "1001";
		tb_operand_a <= x"FFFF0000";
		tb_operand_b <= x"12345678";
		wait for 10 ns;
		assert (tb_alu_result = x"12340000")
			report "AND Test Failed" severity error;

		-----------------------------------------------------------------------
		-- 13. LUI: Direct Pass Operand B
		-----------------------------------------------------------------------
		tb_alu_ctrl  <= "1010";
		tb_operand_a <= x"AAAAAAAA"; -- Should be ignored
		tb_operand_b <= x"12345000"; -- Immediate payload
		wait for 10 ns;
		assert (tb_alu_result = x"12345000")
			report "LUI Pass-Through Test Failed" severity error;

		-----------------------------------------------------------------------
		-- Complete Verification
		-----------------------------------------------------------------------
		assert false report "=== ALL ALU TEST CASES PASSED SUCCESSFULLY ===" severity note;
		wait; -- Suspends process indefinitely to end simulation cleanly
		
	end process;

end architecture Behavior;