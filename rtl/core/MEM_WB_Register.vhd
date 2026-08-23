-- SPDX-License-Identifier: Apache-2.0
-- Copyright 2026 Ozan Akgul
--
-- FIX: Added mem_pc_plus4_in / wb_pc_plus4_out ports so that the PC+4
-- value for JAL/JALR is latched in lockstep with rd_addr / reg_write /
-- wb_sel. Previously wb_pc_plus4 was driven combinationally straight
-- from the EX/MEM register in MEM_Stage.vhd, bypassing this register
-- entirely. That caused a one-cycle skew: by the time JAL's rd_addr/
-- wb_sel="10" reached WB, wb_pc_plus4 reflected the PC+4 of whatever
-- instruction had since moved into MEM, corrupting `ra` on `jal ra, ...`.

library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;


-- MEM/WB pipeline register. Latches the memory-stage result -- either
-- the raw ALU result or the formatted memory read data, selected
-- later in WB by wb_sel_out -- along with the destination register
-- address and PC+4 (for JAL/JALR), so the WB stage and the
-- Forwarding Unit see a stable snapshot for exactly one cycle.
entity MEM_WB_Register is

	port(

	--System Inputs
		clk					:	in	std_logic;
		-- Active-low synchronous reset.
		rst_n					:	in	std_logic;
		-- Holds the register's current outputs unchanged this cycle.
		stall					:	in std_logic;
		-- Clears all outputs to a bubble this cycle.
		flush					:	in std_logic;

	--Data Inputs (from MEM Stage)
		-- ALU result, carried through for non-memory write-back.
		mem_result_in		:	in std_logic_vector(31 downto 0);
		-- Formatted memory read data, for load write-back.
		mem_read_data_in	:	in std_logic_vector(31 downto 0);
		mem_pc_plus4_in		:	in std_logic_vector(31 downto 0); -- NEW: latched PC+4
		-- Destination register address.
		rd_addr_in			:	in	std_logic_vector(4 downto 0);

	--Control Inputs (from MEM Stage)
		-- Register file write enable.
		reg_write_in		:	in	std_logic;
		-- Write-back source select (ALU result / memory data / PC+4).
		wb_sel_in			:	in std_logic_vector(1 downto 0);

	--Outputs (to WB Stage & Forwarding Unit):
		-- Registered mem_result_in.
		wb_result_out		:	out	std_logic_vector(31 downto 0);
		-- Registered mem_read_data_in.
		wb_read_data_out	:	out	std_logic_vector(31 downto 0);
		wb_pc_plus4_out		:	out	std_logic_vector(31 downto 0); -- NEW: registered output
		-- Registered rd_addr_in.
		wb_rd_addr_out		:	out	std_logic_vector(4 downto 0);
		-- Registered reg_write_in.
		wb_reg_write_out	:	out	std_logic;
		-- Registered wb_sel_in.
		wb_sel_out			:	out	std_logic_vector(1 downto 0)

	);


end entity;

architecture Behavioral of MEM_WB_Register is

begin

process(clk)
begin

	if rising_edge(clk) then
		if rst_n = '0' or flush = '1' then
			wb_result_out    <= (others => '0');
			 wb_read_data_out <= (others => '0');
			 wb_pc_plus4_out  <= (others => '0'); -- NEW
			 wb_rd_addr_out   <= (others => '0');
			 wb_reg_write_out <= '0';
			 wb_sel_out       <= (others => '0');

		elsif stall = '1' then
                null; -- holds all outputs, including wb_pc_plus4_out, on stall

		else
			 wb_result_out    <= mem_result_in;
			 wb_read_data_out <= mem_read_data_in;
			 wb_pc_plus4_out  <= mem_pc_plus4_in; -- NEW: now latched together with siblings
			 wb_rd_addr_out   <= rd_addr_in;
			 wb_reg_write_out <= reg_write_in;
			 wb_sel_out       <= wb_sel_in;


		end if;
	end if;
end process;	




end architecture;
