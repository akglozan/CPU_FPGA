-- SPDX-License-Identifier: Apache-2.0
-- Copyright 2026 Ozan Akgül

library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;

library altera_mf;
use altera_mf.altera_mf_components.all;

-- Combined instruction/data BRAM, backed directly by an altsyncram
-- megafunction instead of a plain behavioral array.
--
-- The previous behavioral version (a plain `array` signal with an
-- asynchronous read on port A and a synchronous byte-enabled write/read
-- on port B) relied on Quartus's RAM *inference* to turn it into a real
-- block RAM, and used a `ram_init_file` synthesis attribute to point
-- inference at boot_bram.mif. In practice, the mixed async/sync access
-- pattern caused Quartus to split the 32-bit memory into eight separate
-- 8-bit-wide altsyncram primitives, and the `ram_init_file` attribute
-- (placed once on the original, pre-split signal) did not propagate to
-- any of the automatically generated sub-blocks -- confirmed via
-- Quartus's own RAM Summary report, which listed "MIF: None" for every
-- one of them. The CPU was executing an all-zero instruction stream
-- (which decodes as NOP) and never reached any firmware code.
--
-- Directly instantiating altsyncram removes the inference ambiguity
-- entirely: its own init_file parameter is unambiguous and Quartus
-- always honors it for a single, explicitly-instantiated primitive.
--
-- Trade-off: altsyncram read ports are inherently registered (the
-- REGISTERED default for outdata_reg_*), so port A (instruction fetch)
-- is no longer combinational/asynchronous -- data for the address
-- presented in cycle N is valid in cycle N+1. IF_Stage.vhd and
-- Hazard_Unit.vhd were updated to account for this one-cycle latency.
entity bram_4kb is
    generic (
        -- Path to the .mif memory-init file loaded directly by the
        -- altsyncram primitive's init_file parameter.
        -- Path is relative to the Quartus project directory (the folder
        -- holding CPU_FPGA.qpf). All generated memory images live in sw/.
        hex_file : string := "sw/boot_bram.mif"
    );
    port (
        clk     : in  std_logic;

        -- Port A: instruction-fetch read address (word address, 1024
        -- words). Read-only; registered output (see outdata_reg_a
        -- above), one cycle of latency from address to rdata_a.
        addr_a  : in  std_logic_vector(9 downto 0);
        -- Registered read data for addr_a.
        rdata_a : out std_logic_vector(31 downto 0);

        -- Port B: CPU data read/write address (word address).
        addr_b  : in  std_logic_vector(9 downto 0);
        -- Write data for port B.
        wdata_b : in  std_logic_vector(31 downto 0);
        -- Per-byte write enable for port B; all-zero means read-only
        -- this cycle.
        we_b    : in  std_logic_vector(3 downto 0);
        -- Registered read data for addr_b.
        rdata_b : out std_logic_vector(31 downto 0)
    );
end entity bram_4kb;

architecture rtl of bram_4kb is

    -- Port B's overall write-enable: asserted whenever any byte lane is
    -- being written. byteena_b then selects which specific bytes within
    -- the addressed word actually get written.
    signal wren_b_i : std_logic;

begin

    wren_b_i <= '0' when we_b = "0000" else '1';

    u_altsyncram : altsyncram
        generic map (
            operation_mode          => "BIDIR_DUAL_PORT",
            intended_device_family  => "Cyclone IV E",
            init_file               => hex_file,

            width_a                  => 32,
            widthad_a                => 10,
            numwords_a               => 1024,
            -- UNREGISTERED, not CLOCK0. altsyncram ALWAYS registers the
            -- read address; outdata_reg_a => "CLOCK0" adds a SECOND
            -- register stage on the data output, making the real
            -- address-to-data latency two clock cycles, not one.
            -- IF_Stage.vhd's pc_delayed compensates for exactly one
            -- cycle and Hazard_Unit.vhd's branch_pending discards
            -- exactly one stale in-flight fetch, so with two cycles of
            -- latency id_pc/ex_pc ran one fetch step ahead of the
            -- instruction it was paired with (every PC-relative target
            -- -- AUIPC, JAL, JALR link, every branch -- off by 4) and
            -- one wrong-path instruction survived every taken branch.
            -- Dropping the output register makes the hardware match the
            -- one-cycle latency the pipeline was retimed for.
            outdata_reg_a            => "UNREGISTERED",
            width_byteena_a          => 4,

            width_b                  => 32,
            widthad_b                => 10,
            numwords_b               => 1024,

            -- This is a single-clock design (clock0 only, clock1 left
            -- unconnected). altsyncram's BIDIR_DUAL_PORT mode defaults
            -- every port-B register stage to CLOCK1, which both demands
            -- a clock1 connection and mixes clock domains between
            -- address_b and data_b/wren_b/byteena_b. All port-B register
            -- stages must be explicitly moved onto CLOCK0 to match.
            address_reg_b            => "CLOCK0",
            indata_reg_b              => "CLOCK0",
            rdcontrol_reg_b           => "CLOCK0",
            wrcontrol_wraddress_reg_b => "CLOCK0",
            byteena_reg_b             => "CLOCK0",
            -- UNREGISTERED for the same reason as outdata_reg_a: port B
            -- is the CPU's data port, and a second output register put
            -- rdata_b two cycles behind addr_b while rv32im_soc.vhd
            -- acknowledged the access in the same cycle it was
            -- presented, so every load latched a stale word into
            -- MEM_WB_Register. Now one cycle, matched by the registered
            -- s0_ack in rv32im_soc.vhd.
            outdata_reg_b            => "UNREGISTERED",
            width_byteena_b          => 4,

            read_during_write_mode_mixed_ports => "OLD_DATA"
        )
        port map (
            clock0     => clk,

            -- Port A: instruction fetch. Read-only -- data_a/wren_a tied
            -- off so this port can never write, byteena_a tied high so
            -- the (unused) write path is fully enabled if ever needed.
            address_a  => addr_a,
            data_a     => (others => '0'),
            wren_a     => '0',
            byteena_a  => (others => '1'),
            q_a        => rdata_a,

            -- Port B: CPU data read/write with per-byte write enables.
            address_b  => addr_b,
            data_b     => wdata_b,
            wren_b     => wren_b_i,
            byteena_b  => we_b,
            q_b        => rdata_b
        );

end architecture rtl;