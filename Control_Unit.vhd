library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;

entity Control_Unit is

	port(
	
		opcode	:	in std_logic_vector(6 downto 0);
		funct3	:	in std_logic_vector(2 downto 0);
		funct7	:	in std_logic_vector(6 downto 0 );
		
		imm_src	: 	out std_logic_vector(2 downto 0);
		alu_src 	:  out std_logic;
		reg_write:	out std_logic;
		mem_read :	out std_logic;
		mem_write:	out std_logic;
		wb_sel	:	out std_logic_vector(1 downto 0);
		branch	: 	out std_logic;
		jump		: 	out std_logic;
		alu_ctrl	: 	out std_logic_vector(3 downto 0);
		is_m_ext	: 	out std_logic
		
	
	);


end entity;

architecture Behavioral of Control_Unit is

signal alu_op : std_logic_vector(1 downto 0);

begin

process(opcode)

begin
		imm_src	<=	"000";
		alu_src 	<= '0';
		reg_write<= '0';
		mem_read <= '0';
		mem_write<= '0';
		wb_sel	<= "00";
		branch	<= '0';
		jump		<= '0';
	
	case opcode is
		when "0110011" => -- R-Type
			reg_write	<= '1';
			alu_src		<= '0';
			alu_op		<= "10";
		
		when "0010011" => -- I Type ALU
			reg_write	<= '1';
			alu_src		<= '1';
			imm_src <= "000";
			alu_op <= "11";
		
		when "0000011" => -- Load
			reg_write <= '1';
			alu_src <= '1';
			mem_read <= '1';
			wb_sel <= "01";
			imm_src <= "000";
			alu_op <= "00";
		
		when "0100011"	=> --Store
			alu_src <= '1';
			mem_write <= '1';
			imm_src <= "001";
			alu_op <= "00";
		
		when "1100011"	=> -- Branch
			branch <= '1';
			alu_src <= '0';
			imm_src <= "010";
			alu_op <= "01";
			
		when "1101111"	=> -- JAL
			reg_write <= '1';
			jump <= '1';
			wb_sel <= "10";
			imm_src <= "100";
			
		when "1100111" => -- JALR
			reg_write <= '1';
			jump <= '1';
			alu_src <= '1';
			wb_sel <= "10";
			imm_src <= "000";
			alu_op <= "00";
		
		when "0110111" => --LUI
			reg_write <= '1';
			alu_src <= '1';
			imm_src <= "011";
			alu_op <= "11";
			
		when "0010111" => -- AUIPC
			reg_write <= '1';
			alu_src <= '1';
			imm_src <= "011";
			alu_op <= "00";
			
		when others =>
			null;
			
	end case;
end process;

process(alu_op, funct3, funct7,opcode)

begin

	alu_ctrl <= "0000";
	is_m_ext <= '0';
	
	case alu_op is
		
		when "00" => --Memory addresses / JALR addition
			alu_ctrl <= "0000";
			
		when "01" => --Branch comparison subtraction
			alu_ctrl <= "0001";
			
		when "10" => -- R-Type
			if funct7 = "0000001" then
				is_m_ext <= '1';
				alu_ctrl <= '0' & funct3;
			else	
				case funct3 is
					 when "000" =>
						  if funct7(5) = '1' then
								alu_ctrl <= "0001"; -- SUB
						  else
								alu_ctrl <= "0000"; -- ADD
						  end if;
					 when "001" => alu_ctrl <= "0010"; -- SLL
					 when "010" => alu_ctrl <= "0011"; -- SLT
					 when "011" => alu_ctrl <= "0100"; -- SLTU
					 when "100" => alu_ctrl <= "0101"; -- XOR
					 when "101" =>
						  if funct7(5) = '1' then
								alu_ctrl <= "0111"; -- SRA
						  else
								alu_ctrl <= "0110"; -- SRL
						  end if;
					 when "110" => alu_ctrl <= "1000"; -- OR
					 when "111" => alu_ctrl <= "1001"; -- AND
					 when others => alu_ctrl <= "0000";
				end case;
			end if;
			
		when "11" => --I-Type & LUI
			if opcode = "0110111" then
				alu_ctrl <= "1010";
			else
				case funct3 is
					 when "000" => alu_ctrl <= "0000"; -- ADDI
					 when "001" => alu_ctrl <= "0010"; -- SLLI
					 when "010" => alu_ctrl <= "0011"; -- SLTI
					 when "011" => alu_ctrl <= "0100"; -- SLTIU
					 when "100" => alu_ctrl <= "0101"; -- XORI
					 when "101" =>
						  if funct7(5) = '1' then
								alu_ctrl <= "0111"; -- SRAI
						  else
								alu_ctrl <= "0110"; -- SRLI
						  end if;
					 when "110" => alu_ctrl <= "1000"; -- ORI
					 when "111" => alu_ctrl <= "1001"; -- ANDI
					 when others => alu_ctrl <= "0000";
				end case;
			end if;
		when others =>
			alu_ctrl <= "0000";
	end case;
end process;	
			
			
end architecture;