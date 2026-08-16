library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;

entity Forwarding_Unit is
    port (
        ex_rs1_addr   : in  std_logic_vector(4 downto 0);
        ex_rs2_addr   : in  std_logic_vector(4 downto 0);
        mem_rd_addr   : in  std_logic_vector(4 downto 0);
        mem_reg_write : in  std_logic;
        mem_mem_read  : in  std_logic;
        wb_rd_addr    : in  std_logic_vector(4 downto 0);
        wb_reg_write  : in  std_logic;
        
        forward_a     : out std_logic_vector(1 downto 0);
        forward_b     : out std_logic_vector(1 downto 0)
    );
end entity Forwarding_Unit;

architecture Behavioral of Forwarding_Unit is
begin

process(all)
begin
    -- Forward A: Inhibit MEM-stage forwarding if the instruction is a Load
    if mem_reg_write = '1' and mem_mem_read = '0' and mem_rd_addr /= "00000" and mem_rd_addr = ex_rs1_addr then
        forward_a <= "10";
    elsif wb_reg_write = '1' and wb_rd_addr /= "00000" and wb_rd_addr = ex_rs1_addr then
        forward_a <= "01";
    else
        forward_a <= "00";
    end if;
    
    -- Forward B: Inhibit MEM-stage forwarding if the instruction is a Load
    if mem_reg_write = '1' and mem_mem_read = '0' and mem_rd_addr /= "00000" and mem_rd_addr = ex_rs2_addr then
        forward_b <= "10";
    elsif wb_reg_write = '1' and wb_rd_addr /= "00000" and wb_rd_addr = ex_rs2_addr then
        forward_b <= "01";
    else
        forward_b <= "00";
    end if;

end process;

end architecture Behavioral;