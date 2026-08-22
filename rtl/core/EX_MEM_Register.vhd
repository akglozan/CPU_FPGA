library ieee;
use ieee.std_logic_1164.all;

entity ex_mem_register is
    port (
        clk   : in std_logic;
        rst_n : in std_logic;
        flush : in std_logic;
        stall : in std_logic;

        ex_result       : in std_logic_vector(31 downto 0);
        ex_operand_b    : in std_logic_vector(31 downto 0);
        ex_rd_addr      : in std_logic_vector(4 downto 0);
        ex_pc_plus4     : in std_logic_vector(31 downto 0);

        ex_reg_write    : in std_logic;
        ex_mem_read     : in std_logic;
        ex_mem_write    : in std_logic;
        ex_wb_sel       : in std_logic_vector(1 downto 0);
        ex_funct3       : in std_logic_vector(2 downto 0);

        mem_addr        : out std_logic_vector(31 downto 0);
        mem_result      : out std_logic_vector(31 downto 0);
        mem_write_data  : out std_logic_vector(31 downto 0);
        mem_rd_addr     : out std_logic_vector(4 downto 0);
        mem_pc_plus4    : out std_logic_vector(31 downto 0);

        mem_reg_write   : out std_logic;
        mem_read        : out std_logic;
        mem_write       : out std_logic;
        mem_wb_sel      : out std_logic_vector(1 downto 0);
        mem_funct3      : out std_logic_vector(2 downto 0)
    );
end entity ex_mem_register;

architecture rtl of ex_mem_register is
begin

    process (clk)
    begin
        if rising_edge(clk) then
            if rst_n = '0' then
                mem_addr       <= (others => '0');
                mem_result     <= (others => '0');
                mem_write_data <= (others => '0');
                mem_rd_addr    <= (others => '0');
                mem_pc_plus4   <= (others => '0');

                mem_reg_write  <= '0';
                mem_read       <= '0';
                mem_write      <= '0';
                mem_wb_sel     <= (others => '0');
                mem_funct3     <= (others => '0');

            elsif stall = '1' then
                null;

            elsif flush = '1' then
                mem_addr       <= (others => '0');
                mem_result     <= (others => '0');
                mem_write_data <= (others => '0');
                mem_rd_addr    <= (others => '0');
                mem_pc_plus4   <= (others => '0');

                mem_reg_write  <= '0';
                mem_read       <= '0';
                mem_write      <= '0';
                mem_wb_sel     <= (others => '0');
                mem_funct3     <= (others => '0');

            else
                -- The ALU result is the complete 32-bit byte address.
                mem_addr       <= ex_result;
                mem_result     <= ex_result;
                mem_write_data <= ex_operand_b;
                mem_rd_addr    <= ex_rd_addr;
                mem_pc_plus4   <= ex_pc_plus4;

                mem_reg_write  <= ex_reg_write;
                mem_read       <= ex_mem_read;
                mem_write      <= ex_mem_write;
                mem_wb_sel     <= ex_wb_sel;
                mem_funct3     <= ex_funct3;
            end if;
        end if;
    end process;

end architecture rtl;