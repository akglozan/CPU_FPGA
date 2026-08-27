-- megafunction wizard: %ALTPLL%
-- GENERATION: STANDARD
-- VERSION: WM1.0
-- MODULE: altpll

-- ============================================================
-- File Name: sdram_pll.vhd
-- Megafunction Name(s):
-- 			altpll
--
-- Simulation Library Files(s):
-- 			altera_mf
-- ============================================================
--
-- Hand-adapted from vga_pll.vhd's wizard-generated structure (same
-- project, same board) rather than run through the MegaWizard GUI --
-- the only real differences from vga_pll.vhd are CLK0_DIVIDE_BY=1 /
-- CLK0_MULTIPLY_BY=1 (50 MHz in, 50 MHz out, same frequency, only the
-- phase changes) and a non-zero CLK0_PHASE_SHIFT.
--
-- PURPOSE (2026-08-27): added while chasing the "80 clean vertical
-- stripes" VGA bring-up bug. sdram_controller.vhd forwards sdram_clk
-- as a plain unregistered copy of the FPGA's internal clk (see that
-- file's header) -- zero phase margin between when the FPGA launches
-- a command/samples data and when the physical chip actually sees the
-- clock edge and drives its response back. Real-hardware debugging
-- (vga_line_fetch's dbg_word0_o/dbg_word1_o piped out over UART) found
-- burst-length-2 reads' FIRST 16-bit beat always correct but the
-- SECOND beat (the very next clock, zero gap) reads back as
-- unrepeatable garbage on every sample, but only under vga_line_fetch's
-- sustained back-to-back access pattern -- never under the CPU's own
-- occasional single accesses, which round-trip correctly using this
-- exact same capture logic. Three FSM-only fixes (widening tRP/tRCD
-- margin 3x, delaying the beat-2 sample point by a cycle, and page
-- mode -- skipping repeated ACTIVATE/PRECHARGE for same-row accesses)
-- all left the identical fingerprint unchanged, which rules out
-- sequencing/row-thrashing as the cause and points at a genuine
-- hardware timing-margin problem on the beat1->beat2 transition
-- itself -- exactly the class of problem a phase-shifted forwarded
-- clock is the standard fix for on this class of board. This PLL
-- advances the clock actually driven to the physical SD_CLK pin
-- relative to the clk edge the FPGA uses to launch commands and
-- sample sdram_dq, giving the chip's response more time to settle
-- before the FPGA's own capture edge.
--
-- CLK0_PHASE_SHIFT is set to -3000 (ps), i.e. a 3 ns advance, as a
-- first real-world value to try -- there is no way to measure the
-- actual trace/setup-hold margin without a scope, so this is a
-- reasoned starting guess (a few ns is the typical range used by SDR
-- SDRAM reference designs on Cyclone-family boards), not a calculated
-- optimum. Quartus's PLL hardware only supports phase shifts in
-- discrete steps of (VCO period / 8), so the compilation report may
-- show a slightly different achieved value than requested -- that is
-- normal, not an error. If -3000 doesn't resolve the stripes, other
-- magnitudes (e.g. -1500, -4500, or positive/delayed instead of
-- negative/advanced) are the next thing to sweep.
-- ************************************************************


--Copyright (C) 2025  Altera Corporation. All rights reserved.
--Your use of Altera Corporation's design tools, logic functions
--and other software and tools, and any partner logic
--functions, and any output files from any of the foregoing
--(including device programming or simulation files), and any
--associated documentation or information are expressly subject
--to the terms and conditions of the Altera Program License
--Subscription Agreement, the Altera Quartus Prime License Agreement,
--the Altera IP License Agreement, or other applicable license
--agreement, including, without limitation, that your use is for
--the sole purpose of programming logic devices manufactured by
--Altera and sold by Altera or its authorized distributors.  Please
--refer to the Altera Software License Subscription Agreements
--on the Quartus Prime software download page.


LIBRARY ieee;
USE ieee.std_logic_1164.all;

LIBRARY altera_mf;
USE altera_mf.all;

ENTITY sdram_pll IS
	PORT
	(
		areset		: IN STD_LOGIC  := '0';
		inclk0		: IN STD_LOGIC  := '0';
		c0		: OUT STD_LOGIC ;
		locked		: OUT STD_LOGIC
	);
END sdram_pll;


ARCHITECTURE SYN OF sdram_pll IS

	SIGNAL sub_wire0	: STD_LOGIC ;
	SIGNAL sub_wire1	: STD_LOGIC_VECTOR (1 DOWNTO 0);
	SIGNAL sub_wire2_bv	: BIT_VECTOR (0 DOWNTO 0);
	SIGNAL sub_wire2	: STD_LOGIC_VECTOR (0 DOWNTO 0);
	SIGNAL sub_wire3	: STD_LOGIC_VECTOR (4 DOWNTO 0);
	SIGNAL sub_wire4	: STD_LOGIC ;
	SIGNAL sub_wire5	: STD_LOGIC ;



	COMPONENT altpll
	GENERIC (
		bandwidth_type		: STRING;
		clk0_divide_by		: NATURAL;
		clk0_duty_cycle		: NATURAL;
		clk0_multiply_by		: NATURAL;
		clk0_phase_shift		: STRING;
		compensate_clock		: STRING;
		inclk0_input_frequency		: NATURAL;
		intended_device_family		: STRING;
		lpm_hint		: STRING;
		lpm_type		: STRING;
		operation_mode		: STRING;
		pll_type		: STRING;
		port_activeclock		: STRING;
		port_areset		: STRING;
		port_clkbad0		: STRING;
		port_clkbad1		: STRING;
		port_clkloss		: STRING;
		port_clkswitch		: STRING;
		port_configupdate		: STRING;
		port_fbin		: STRING;
		port_inclk0		: STRING;
		port_inclk1		: STRING;
		port_locked		: STRING;
		port_pfdena		: STRING;
		port_phasecounterselect		: STRING;
		port_phasedone		: STRING;
		port_phasestep		: STRING;
		port_phaseupdown		: STRING;
		port_pllena		: STRING;
		port_scanaclr		: STRING;
		port_scanclk		: STRING;
		port_scanclkena		: STRING;
		port_scandata		: STRING;
		port_scandataout		: STRING;
		port_scandone		: STRING;
		port_scanread		: STRING;
		port_scanwrite		: STRING;
		port_clk0		: STRING;
		port_clk1		: STRING;
		port_clk2		: STRING;
		port_clk3		: STRING;
		port_clk4		: STRING;
		port_clk5		: STRING;
		port_clkena0		: STRING;
		port_clkena1		: STRING;
		port_clkena2		: STRING;
		port_clkena3		: STRING;
		port_clkena4		: STRING;
		port_clkena5		: STRING;
		port_extclk0		: STRING;
		port_extclk1		: STRING;
		port_extclk2		: STRING;
		port_extclk3		: STRING;
		self_reset_on_loss_lock		: STRING;
		width_clock		: NATURAL
	);
	PORT (
			areset	: IN STD_LOGIC ;
			inclk	: IN STD_LOGIC_VECTOR (1 DOWNTO 0);
			clk	: OUT STD_LOGIC_VECTOR (4 DOWNTO 0);
			locked	: OUT STD_LOGIC
	);
	END COMPONENT;

BEGIN
	sub_wire2_bv(0 DOWNTO 0) <= "0";
	sub_wire2    <= To_stdlogicvector(sub_wire2_bv);
	sub_wire0    <= inclk0;
	sub_wire1    <= sub_wire2(0 DOWNTO 0) & sub_wire0;
	sub_wire4    <= sub_wire3(0);
	c0    <= sub_wire4;
	locked    <= sub_wire5;

	altpll_component : altpll
	GENERIC MAP (
		bandwidth_type => "AUTO",
		clk0_divide_by => 1,
		clk0_duty_cycle => 50,
		clk0_multiply_by => 1,
		clk0_phase_shift => "-3000",
		compensate_clock => "CLK0",
		inclk0_input_frequency => 20000,
		intended_device_family => "Cyclone IV E",
		lpm_hint => "CBX_MODULE_PREFIX=sdram_pll",
		lpm_type => "altpll",
		operation_mode => "NORMAL",
		pll_type => "AUTO",
		port_activeclock => "PORT_UNUSED",
		port_areset => "PORT_USED",
		port_clkbad0 => "PORT_UNUSED",
		port_clkbad1 => "PORT_UNUSED",
		port_clkloss => "PORT_UNUSED",
		port_clkswitch => "PORT_UNUSED",
		port_configupdate => "PORT_UNUSED",
		port_fbin => "PORT_UNUSED",
		port_inclk0 => "PORT_USED",
		port_inclk1 => "PORT_UNUSED",
		port_locked => "PORT_USED",
		port_pfdena => "PORT_UNUSED",
		port_phasecounterselect => "PORT_UNUSED",
		port_phasedone => "PORT_UNUSED",
		port_phasestep => "PORT_UNUSED",
		port_phaseupdown => "PORT_UNUSED",
		port_pllena => "PORT_UNUSED",
		port_scanaclr => "PORT_UNUSED",
		port_scanclk => "PORT_UNUSED",
		port_scanclkena => "PORT_UNUSED",
		port_scandata => "PORT_UNUSED",
		port_scandataout => "PORT_UNUSED",
		port_scandone => "PORT_UNUSED",
		port_scanread => "PORT_UNUSED",
		port_scanwrite => "PORT_UNUSED",
		port_clk0 => "PORT_USED",
		port_clk1 => "PORT_UNUSED",
		port_clk2 => "PORT_UNUSED",
		port_clk3 => "PORT_UNUSED",
		port_clk4 => "PORT_UNUSED",
		port_clk5 => "PORT_UNUSED",
		port_clkena0 => "PORT_UNUSED",
		port_clkena1 => "PORT_UNUSED",
		port_clkena2 => "PORT_UNUSED",
		port_clkena3 => "PORT_UNUSED",
		port_clkena4 => "PORT_UNUSED",
		port_clkena5 => "PORT_UNUSED",
		port_extclk0 => "PORT_UNUSED",
		port_extclk1 => "PORT_UNUSED",
		port_extclk2 => "PORT_UNUSED",
		port_extclk3 => "PORT_UNUSED",
		self_reset_on_loss_lock => "OFF",
		width_clock => 5
	)
	PORT MAP (
		areset => areset,
		inclk => sub_wire1,
		clk => sub_wire3,
		locked => sub_wire5
	);



END SYN;
