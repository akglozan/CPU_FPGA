library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;

entity Hazard_Unit is 
    port (
        stall_m     : in  std_logic;
        id_rs1_addr : in  std_logic_vector(4 downto 0);
        id_rs2_addr : in  std_logic_vector(4 downto 0);
        ex_rd_addr  : in  std_logic_vector(4 downto 0);
        ex_mem_read : in  std_logic;
        take_branch : in  std_logic;
        pc_write    : out std_logic;
        if_id_stall : out std_logic;
        if_id_flush : out std_logic;
        id_ex_stall : out std_logic;
        id_ex_flush : out std_logic
    );
end entity Hazard_Unit;

architecture Behavioral of Hazard_Unit is
begin

process(all)
begin
    -- Default Assignments
    pc_write    <= '1';
    if_id_stall <= '0';
    id_ex_stall <= '0';
    if_id_flush <= '0';
    id_ex_flush <= '0';

    -- Multi-Cycle M-Extension Stall Handling
    if stall_m = '1' then
        pc_write    <= '0';
        if_id_stall <= '1';
        id_ex_stall <= '1';
        if_id_flush <= '0';
        id_ex_flush <= '0';
    
    -- Load-Use Data Hazard Detection (Freeze IF/ID, flush ID/EX with bubble)
    elsif ex_mem_read = '1' and (ex_rd_addr = id_rs1_addr or ex_rd_addr = id_rs2_addr) and ex_rd_addr /= "00000" then        
        pc_write    <= '0';
        if_id_stall <= '1';
        id_ex_stall <= '0';
        id_ex_flush <= '1';
    
    -- Control Hazards (Branch / Jump Flushes)
    elsif take_branch = '1' then
        pc_write    <= '1';
        if_id_flush <= '1';
        id_ex_flush <= '1';
    end if;

end process;

end architecture Behavioral;