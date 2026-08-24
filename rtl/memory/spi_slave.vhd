-- SPI slave: assembles MOSI bits into bytes, safely crossing from the
-- ESP32's asynchronous SPI clock domain into the FPGA's system clock
-- domain. Mode 0 (CPOL=0, CPHA=0): data is sampled on the rising SCLK
-- edge. This module is deliberately "dumb" -- it knows nothing about
-- headers, addresses, or SDRAM. It just turns a serial bit stream into
-- a stream of parallel bytes with a one-cycle valid pulse, so it can
-- be reused as-is if the boot protocol on top of it ever changes.
library ieee;
use ieee.std_logic_1164.all;

entity spi_slave is

	port(

		clk		:	in	std_logic;  -- FPGA system clock (50 MHz)
		rst_n		:	in	std_logic;

		spi_sclk	:	in std_logic;  -- from ESP32 (async to clk)
		spi_mosi	:	in std_logic;  -- from ESP32 (async to clk)
		spi_cs_n	:	in std_logic;  -- from ESP32 (async to clk), active low

		rx_byte	:	out std_logic_vector(7 downto 0);  -- last byte received
		rx_valid	:	out std_logic  -- single-cycle pulse when rx_byte is valid


	);


end entity;


architecture rtl of spi_slave is

	-- Multi-flop synchronizers bring the async SPI signals safely into
	-- the clk domain before any logic acts on them. Sampling spi_sclk/
	-- spi_mosi/spi_cs_n directly (without these) risks metastability,
	-- since they're driven by a completely separate oscillator on the
	-- ESP32 with no fixed phase relationship to our 50 MHz clock.
	--
	-- sclk_sync is 3 bits wide (not the usual 2) because edge detection
	-- needs both the settled value AND the previous cycle's settled
	-- value: sclk_sync(2) is one cycle behind sclk_sync(1), so comparing
	-- them below detects a 0->1 transition on the synchronized clock.
	signal sclk_sync	:	std_logic_vector(2 downto 0) := (others => '0');
	signal mosi_sync	:	std_logic_vector(1 downto 0) := (others => '0');
	signal cs_n_sync	:	std_logic_vector(1 downto 0) := (others => '1');

	-- Shifts in one MOSI bit per detected SCLK rising edge; once 8 bits
	-- have arrived, its contents (plus the bit landing this same cycle)
	-- form the received byte.
	signal shift_reg	:	std_logic_vector(7 downto 0) := (others => '0');
	signal bit_count	:	natural range 0 to 7 := 0;
	signal rx_valid_r	:	std_logic := '0';

	-- Pulses for one clk cycle on the rising edge of the synchronized
	-- SPI clock.
	signal sclk_rising : std_logic;



begin

	-- Stage 1: synchronize the three async SPI signals into the clk
	-- domain. This process does nothing else -- keeping synchronization
	-- isolated from the logic that acts on the synchronized signals is
	-- what makes the CDC safe and easy to reason about.
	process(clk)
	begin
		if rising_edge(clk) then
			if rst_n = '0' then
				sclk_sync <= (others => '0');
				mosi_sync <= (others => '0');
				-- cs_n idles HIGH (deasserted / no transaction). Resetting
				-- it to all-'0' here would tell the byte-assembly process
				-- below that CS is asserted the instant reset releases,
				-- i.e. that a transaction is already under way -- wrong.
				cs_n_sync <= (others => '1');
			else
				sclk_sync <= sclk_sync(1 downto 0) & spi_sclk;
				mosi_sync <= mosi_sync(0) & spi_mosi;
				cs_n_sync <= cs_n_sync(0) & spi_cs_n;
			end if;
		end if;
	end process;

	-- Detects a 0->1 transition on the now-synchronized SPI clock: "01"
	-- read left-to-right as (previous, current) means the previous
	-- sample was low and the current one is high.
	sclk_rising <= '1' when sclk_sync(2 downto 1) = "01" else '0';


	-- Stage 2: byte assembly. Shifts in a bit on every synchronized
	-- SCLK rising edge; every 8th bit produces a one-cycle rx_valid
	-- pulse. Held in reset (bit_count = 0, no pulse) any time cs_n is
	-- high, i.e. whenever no transaction is in progress -- this means
	-- every new transaction (every CS falling edge) starts byte-aligned
	-- from bit 0, so a glitch or a short/malformed prior transfer can
	-- never permanently desync the byte framing.
	process(clk)
	begin
		if rising_edge(clk) then
			if rst_n = '0' or cs_n_sync(1) = '1' then
				bit_count <= 0;
				rx_valid_r <= '0';
			else
				rx_valid_r <= '0';

				if sclk_rising = '1' then
					shift_reg <= shift_reg(6 downto 0) & mosi_sync(1);

					if bit_count = 7 then
						bit_count <= 0;
						rx_valid_r <= '1';
					else
						bit_count <= bit_count +1;
					end if;
				end if;
			end if;
		end if;
	end process;

	-- rx_byte normally just mirrors shift_reg. On the exact cycle the
	-- 8th bit lands (sclk_rising = '1' and bit_count = 7), shift_reg
	-- itself hasn't registered that bit yet -- it updates on this same
	-- clock edge -- so this forward-path computes the complete byte
	-- combinationally instead of making rx_valid's consumer wait one
	-- extra cycle for shift_reg to catch up.
	rx_byte <= shift_reg(6 downto 0) & mosi_sync(1) when sclk_rising = '1' and bit_count = 7
					else shift_reg;

	rx_valid <= rx_valid_r;


end architecture;
