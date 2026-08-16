-- SPDX-License-Identifier: Apache-2.0
-- Copyright 2026 Ozan Akgül

library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;

entity IF_Stage is
    generic (
        DATA_WIDTH : integer := 32
    );
    port (
        clk             : in  std_logic;
        rst_n           : in  std_logic;
        
        -- Hazard Controls
        pc_write        : in  std_logic;
        if_id_stall     : in  std_logic;
        if_id_flush     : in  std_logic;
        
        -- Branch / Jump Controls
        pc_src          : in  std_logic;
        target_pc       : in  std_logic_vector(31 downto 0);
        
        -- External Instruction Memory / BRAM Interface
        pc_fetch_out    : out std_logic_vector(31 downto 0);
        instr_fetch_in  : in  std_logic_vector(31 downto 0);
        
        -- Outputs to ID Stage & Debug
        pc_current_out  : out std_logic_vector(31 downto 0);
        id_pc_out       : out std_logic_vector(31 downto 0);
        id_instr_out    : out std_logic_vector(31 downto 0)
    );
end entity IF_Stage;

architecture Structural of IF_Stage is

    signal pc_wire       : std_logic_vector(31 downto 0);
    signal pc_plus4_wire : std_logic_vector(31 downto 0);

begin

    pc_current_out <= pc_wire;
    pc_fetch_out   <= pc_wire;

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

    -- IF/ID Pipeline Register (receives data directly from external BRAM)
    U_IF_ID : entity work.IF_ID_Register
        port map (
            clk             => clk,
            rst_n           => rst_n,
            stall           => if_id_stall,
            flush           => if_id_flush,
            pc_in           => pc_wire,
            instruction_in  => instr_fetch_in,
            pc_out          => id_pc_out,
            instruction_out => id_instr_out
        );

end architecture Structural;