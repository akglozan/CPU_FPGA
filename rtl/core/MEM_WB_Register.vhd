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


entity MEM_WB_Register is

	port(

	--System Inputs
		clk					:	in	std_logic;
		rst_n					:	in	std_logic;
		stall					:	in std_logic;
		flush					:	in std_logic;

	--Data Inputs (from MEM Stage)
		mem_result_in		:	in std_logic_vector(31 downto 0);
		mem_read_data_in	:	in std_logic_vector(31 downto 0);
		mem_pc_plus4_in		:	in std_logic_vector(31 downto 0); -- NEW: latched PC+4
		rd_addr_in			:	in	std_logic_vector(4 downto 0);

	--Control Inputs (from MEM Stage)
		reg_write_in		:	in	std_logic;
		wb_sel_in			:	in std_logic_vector(1 downto 0);

	--Outputs (to WB Stage & Forwarding Unit):
		wb_result_out		:	out	std_logic_vector(31 downto 0);
		wb_read_data_out	:	out	std_logic_vector(31 downto 0);
		wb_pc_plus4_out		:	out	std_logic_vector(31 downto 0); -- NEW: registered output
		wb_rd_addr_out		:	out	std_logic_vector(4 downto 0);
		wb_reg_write_out	:	out	std_logic;
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
