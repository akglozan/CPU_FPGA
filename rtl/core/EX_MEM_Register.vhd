library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;

entity EX_MEM_Register is
    port (
        clk                     : in  std_logic;
        rst_n                   : in  std_logic;
        flush                   : in  std_logic;
        stall                   : in  std_logic;
        
        -- Data Inputs
        ex_final_result         : in  std_logic_vector(31 downto 0);
        ex_operand_b_forwarded  : in  std_logic_vector(31 downto 0);
        ex_rd_addr              : in  std_logic_vector(4 downto 0);
        ex_pc_plus4             : in  std_logic_vector(31 downto 0);
        
        -- Control Inputs
        ex_reg_write            : in  std_logic;
        ex_mem_read             : in  std_logic;
        ex_mem_write            : in  std_logic;
        ex_wb_sel               : in  std_logic_vector(1 downto 0); -- previous comment mentioned that it could be increased to 2 bits if problems persisted and they did :)
        ex_funct3               : in  std_logic_vector(2 downto 0);
        
        -- Data Outputs
        mem_result              : out std_logic_vector(31 downto 0);
        mem_write_data          : out std_logic_vector(31 downto 0);
        mem_rd_addr             : out std_logic_vector(4 downto 0);
        mem_pc_plus4            : out std_logic_vector(31 downto 0);
        
        -- Control Outputs
        mem_reg_write           : out std_logic;
        mem_mem_read            : out std_logic;
        mem_mem_write           : out std_logic;
        mem_wb_sel              : out std_logic_vector(1 downto 0);
        mem_funct3              : out std_logic_vector(2 downto 0)
    );
end entity EX_MEM_Register;

architecture Behavioral of EX_MEM_Register is
begin

    process(clk, rst_n)
    begin
        if rst_n = '0' then
            mem_reg_write  <= '0';
            mem_mem_read   <= '0';
            mem_mem_write  <= '0';
            mem_wb_sel     <= "00";
            mem_rd_addr    <= (others => '0');
            mem_result     <= (others => '0');
            mem_write_data <= (others => '0');
            mem_pc_plus4   <= (others => '0');
            mem_funct3     <= (others => '0');

        elsif rising_edge(clk) then
            if stall = '1' then
                null;
            elsif flush = '1' then
                mem_reg_write  <= '0';
                mem_mem_read   <= '0';
                mem_mem_write  <= '0';
                mem_wb_sel     <= "00";
                mem_rd_addr    <= (others => '0');
                mem_result     <= (others => '0');
                mem_write_data <= (others => '0');
                mem_pc_plus4   <= (others => '0');
                mem_funct3     <= (others => '0');
            else
                mem_result     <= ex_final_result;
                mem_write_data <= ex_operand_b_forwarded;
                mem_rd_addr    <= ex_rd_addr;
                mem_pc_plus4   <= ex_pc_plus4;
                mem_reg_write  <= ex_reg_write;
                mem_mem_read   <= ex_mem_read;
                mem_mem_write  <= ex_mem_write;
                mem_wb_sel     <= ex_wb_sel;
                mem_funct3     <= ex_funct3;
            end if;
        end if;
    end process;

end architecture Behavioral;