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

-- RV32M multiply/divide extension unit. MUL/MULH/MULHSU/MULHU are
-- computed combinationally in a single cycle via a 33x33-bit signed
-- multiplier; DIV/DIVU/REM/REMU run through a 32-cycle
-- restoring-division FSM (IDLE -> COMPUTE -> DONE), asserting stall_m
-- for the duration so the pipeline holds until the result is ready.
-- Division by zero and the INT_MIN / -1 overflow case are special-
-- cased per the RISC-V spec (quotient = all-ones or INT_MIN,
-- remainder = dividend or zero).
entity M_Extension_Unit is

	port(
	
	--System Inputs
		clk	:	in std_logic;
		-- Active-low synchronous reset.
		rst_n	:	in std_logic;
		
	--Control Inputs
		-- Asserted for RV32M multiply/divide instructions.
		is_m_ext	: 	in std_logic;
		-- funct3 field: selects MUL/MULH/MULHSU/MULHU or
		-- DIV/DIVU/REM/REMU and their signedness.
		funct3	:	in std_logic_vector(2 downto 0);
		
	--Data Inputs
		operand_a	: in std_logic_vector(31 downto 0);
		operand_b	: in std_logic_vector(31 downto 0);
		
	--Data Outputs
		-- Selected multiply or divide/remainder result.
		m_result		: out std_logic_vector(31 downto 0);
		
	--Status Outputs
		-- Asserted while a multi-cycle divide is still in progress.
		stall_m		: out std_logic
		
	
	);


end entity;


architecture Behavioral of M_Extension_Unit is

    -- FSM States
    type state_type is (IDLE, COMPUTE, DONE);
    signal current_state, next_state : state_type;
    
    -- Datapath Registers
    signal quotient_reg : std_logic_vector(31 downto 0);
    signal divisor_reg  : std_logic_vector(31 downto 0);
    signal accumulator  : std_logic_vector(32 downto 0);
    
    -- Counter
    signal count : std_logic_vector(5 downto 0);
    
    -- Flags
    signal sign_quotient  : std_logic;
    signal sign_remainder : std_logic;
    signal div_by_zero    : std_logic;
    signal overflow       : std_logic;
    
    -- Multiplier signals
    signal mult_prod : std_logic_vector(65 downto 0);

begin

-- Combinational Multiplier Process
process(funct3, operand_a, operand_b)
    variable v_a_ext : std_logic_vector(32 downto 0);
    variable v_b_ext : std_logic_vector(32 downto 0);
begin
    case funct3 is
        when "000" | "001" =>  -- MUL, MULH (Signed x Signed)
            v_a_ext := operand_a(31) & operand_a;
            v_b_ext := operand_b(31) & operand_b;
            
        when "010" =>         -- MULHSU (Signed x Unsigned)
            v_a_ext := operand_a(31) & operand_a;
            v_b_ext := '0' & operand_b;
            
        when "011" =>         -- MULHU (Unsigned x Unsigned)
            v_a_ext := '0' & operand_a;
            v_b_ext := '0' & operand_b;
                
        when others =>        -- Default
            v_a_ext := (others => '0');
            v_b_ext := (others => '0');
    end case;

    mult_prod <= std_logic_vector(signed(v_a_ext) * signed(v_b_ext));
end process;


-- Sequential Process (Clocked)
process(clk, rst_n)
    variable v_shift_acc  : unsigned(32 downto 0);
    variable v_shift_quot : std_logic_vector(31 downto 0);
    variable v_trial_sub  : unsigned(32 downto 0);
    variable v_final_quot : std_logic_vector(31 downto 0);
    variable v_final_rem  : std_logic_vector(31 downto 0);
begin
    if rising_edge(clk) then
        if rst_n = '0' then
            current_state  <= IDLE; 
            quotient_reg   <= (others => '0');
            divisor_reg    <= (others => '0');
            accumulator    <= (others => '0');
            count          <= (others => '0');
            sign_quotient  <= '0';
            sign_remainder <= '0';
            div_by_zero    <= '0';
            overflow       <= '0';

        else
            current_state <= next_state;
        
            case current_state is
                when IDLE =>
                    overflow       <= '0';
                    div_by_zero    <= '0';
                    sign_quotient  <= '0';
                    sign_remainder <= '0';
                    count          <= (others => '0');
                    accumulator    <= (others => '0');
                    
                    quotient_reg   <= operand_a;
                    divisor_reg    <= operand_b;

                    if is_m_ext = '1' and funct3(2) = '1' then
                        if operand_b = x"00000000" then
                            div_by_zero <= '1';
                        end if;

                        if funct3(0) = '0' then
                            sign_quotient  <= operand_a(31) xor operand_b(31);
                            sign_remainder <= operand_a(31);

                            quotient_reg   <= std_logic_vector(abs(signed(operand_a)));
                            divisor_reg    <= std_logic_vector(abs(signed(operand_b)));

                            if operand_a = x"80000000" and operand_b = x"FFFFFFFF" then
                                overflow <= '1';
                            end if;
                        else
                            sign_quotient  <= '0';
                            sign_remainder <= '0';
                        end if;
                    end if;
                    
                when COMPUTE =>
                    v_shift_acc  := unsigned(accumulator(31 downto 0) & quotient_reg(31));
                    v_shift_quot := quotient_reg(30 downto 0) & '0';
                    v_trial_sub  := v_shift_acc - unsigned('0' & divisor_reg);
                    
                    if v_trial_sub(32) = '0' then
                        accumulator  <= std_logic_vector(v_trial_sub);
                        quotient_reg <= v_shift_quot(31 downto 1) & '1';
                    else
                        accumulator  <= std_logic_vector(v_shift_acc);
                        quotient_reg <= v_shift_quot(31 downto 1) & '0';
                    end if;
                    
                    count <= std_logic_vector(unsigned(count) + 1);

                when DONE =>
                    count <= (others => '0');
                    
                    v_final_quot := quotient_reg;
                    v_final_rem  := accumulator(31 downto 0);
                     
                    if div_by_zero = '1' then
                        v_final_quot := x"FFFFFFFF";
                        v_final_rem  := operand_a;
                    elsif overflow = '1' then
                        v_final_quot := x"80000000";
                        v_final_rem  := (others => '0');
                    else
                        if sign_quotient = '1' then
                            v_final_quot := std_logic_vector(-signed(v_final_quot));
                        end if;
                        if sign_remainder = '1' then
                            v_final_rem := std_logic_vector(-signed(v_final_rem));
                        end if;
                    end if;
                    
                    -- Update registers for holding
                    quotient_reg             <= v_final_quot;
                    accumulator(31 downto 0) <= v_final_rem;
                
                when others =>
                    null;
            end case;   
        end if;
    end if;
end process;


-- Next State FSM Process
process (current_state, is_m_ext, funct3, count)
begin
    case current_state is
        when IDLE =>
            if is_m_ext = '1' and funct3(2) = '1' then
                next_state <= COMPUTE;
            else 
                next_state <= IDLE;
            end if;
        
        when COMPUTE =>
            if unsigned(count) = "011111" then
                next_state <= DONE;
            else
                next_state <= COMPUTE;
            end if;
                
        when DONE =>
            next_state <= IDLE;
        
        when others =>
            next_state <= IDLE;
    end case;
end process;


-- Stall Assignment
stall_m <= '1' when (is_m_ext = '1' and funct3(2) = '1' and current_state /= DONE) else '0';


-- Output Mux Assignment
with funct3 select
    m_result <= mult_prod(31 downto 0)     when "000",
                mult_prod(63 downto 32)   when "001" | "010" | "011",
                quotient_reg              when "100" | "101",
                accumulator(31 downto 0)  when "110" | "111",
                (others => '0')           when others;

end architecture;