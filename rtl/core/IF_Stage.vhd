-- SPDX-License-Identifier: Apache-2.0
-- Copyright 2026 Ozan Akgül

library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;

-- IF-stage top-level wrapper: instantiates the Program_Counter and
-- IF_ID_Register, and re-aligns the fetched instruction with the PC
-- that produced it to account for the instruction memory's one-cycle
-- registered read latency (see pc_delayed in the architecture body).
entity IF_Stage is
    generic (
        -- PC / address width in bits.
        DATA_WIDTH : integer := 32
    );
    port (
        clk             : in  std_logic;
        -- Active-low synchronous reset.
        rst_n           : in  std_logic;
        
        -- Hazard Controls
        -- Forwarded to Program_Counter; deasserted to freeze the PC
        -- during a pipeline stall.
        pc_write        : in  std_logic;
        -- Forwarded to IF_ID_Register; freezes the PC/instruction pair
        -- during a stall.
        if_id_stall     : in  std_logic;
        -- Forwarded to IF_ID_Register; inserts a NOP bubble.
        if_id_flush     : in  std_logic;
        
        -- Branch / Jump Controls
        -- Selects the next PC source: PC+4, or target_pc.
        pc_src          : in  std_logic;
        -- Branch/jump target address.
        target_pc       : in  std_logic_vector(31 downto 0);
        
        -- External Instruction Memory / BRAM Interface
        -- PC value driven out to the instruction memory this cycle.
        pc_fetch_out    : out std_logic_vector(31 downto 0);
        -- Instruction word returned by the instruction memory (one
        -- cycle after pc_fetch_out was presented).
        instr_fetch_in  : in  std_logic_vector(31 downto 0);
        
        -- Outputs to ID Stage & Debug
        -- Current PC value, exposed for debug.
        pc_current_out  : out std_logic_vector(31 downto 0);
        -- PC value passed into the ID stage.
        id_pc_out       : out std_logic_vector(31 downto 0);
        -- Instruction word passed into the ID stage.
        id_instr_out    : out std_logic_vector(31 downto 0)
    );
end entity IF_Stage;

architecture Structural of IF_Stage is

    signal pc_wire       : std_logic_vector(31 downto 0);
    signal pc_plus4_wire : std_logic_vector(31 downto 0);

    -- bram_4kb's instruction-fetch port is now a registered (synchronous)
    -- read: the data for the address presented on pc_fetch_out in cycle N
    -- only appears on instr_fetch_in in cycle N+1. pc_wire itself has
    -- already moved on to the *next* fetch address by then, so it can no
    -- longer be used directly as the PC that matches instr_fetch_in.
    -- pc_delayed re-aligns them: it captures pc_wire one cycle behind,
    -- so in the same cycle that instr_fetch_in becomes valid for a given
    -- fetch, pc_delayed holds the PC that produced it. It freezes under
    -- the same if_id_stall condition as IF_ID_Register so the two stay
    -- in lockstep during multi-cycle stalls (load-use hazards, bus
    -- wait-states) rather than sliding out of sync.
    signal pc_delayed    : std_logic_vector(31 downto 0) := (others => '0');

begin

    pc_current_out <= pc_wire;

    -- A stall drops an instruction unless the fetch address is rewound.
    --
    -- On the cycle a stall begins (bus wait-state or load-use hazard),
    -- instr_fetch_in is carrying the instruction for pc_delayed -- and
    -- IF_ID_Register is frozen, so it does NOT capture it. Meanwhile
    -- pc_write is also low, so pc_wire holds the NEXT address, whose
    -- data lands on instr_fetch_in the following cycle and overwrites
    -- the one that was never consumed. That instruction is then gone
    -- from the stream forever: the CPU silently skips one instruction
    -- per stall cycle, and pc_delayed no longer matches the instruction
    -- IF_ID_Register eventually latches.
    --
    -- Re-presenting pc_delayed while stalled re-fetches the un-consumed
    -- instruction, so it is still on instr_fetch_in when the stall lifts
    -- and IF_ID_Register finally captures it -- paired with the frozen
    -- pc_delayed that produced it. pc_wire is unchanged during the stall,
    -- so normal fetch resumes from the right place on the next cycle.
    pc_fetch_out   <= pc_delayed when if_id_stall = '1' else pc_wire;

    process(clk)
    begin
        if rising_edge(clk) then
            if rst_n = '0' then
                pc_delayed <= (others => '0');
            elsif if_id_stall = '0' then
                pc_delayed <= pc_wire;
            end if;
            -- when if_id_stall = '1', hold pc_delayed, matching
            -- IF_ID_Register's own freeze-on-stall behavior.
        end if;
    end process;

    -- Program Counter
    U_PC : entity work.Program_Counter
        generic map ( DATA_WIDTH => DATA_WIDTH )
        port map (
            clk       => clk,
            rst_n     => rst_n,
            pc_write  => pc_write,
            pc_src    => pc_src,
            target_pc => target_pc,
            pc_out    => pc_wire,
            pc_plus4  => pc_plus4_wire
        );

    -- IF/ID Pipeline Register
    U_IF_ID : entity work.IF_ID_Register
        port map (
            clk             => clk,
            rst_n           => rst_n,
            stall           => if_id_stall,
            flush           => if_id_flush,
            pc_in           => pc_delayed,
            instruction_in  => instr_fetch_in,
            pc_out          => id_pc_out,
            instruction_out => id_instr_out
        );

end architecture Structural;