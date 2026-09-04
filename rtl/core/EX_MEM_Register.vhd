library ieee;
use ieee.std_logic_1164.all;

-- EX/MEM pipeline register. Latches the ALU result (used both as the
-- MEM-stage data value and, for loads/stores, as the memory address),
-- the store data, and the associated control signals, so the MEM
-- stage sees a stable snapshot for exactly one cycle. Cleared to a
-- bubble on reset or flush; held unchanged on stall.
entity EX_MEM_Register is
    port (
        clk   : in std_logic;
        -- Active-low synchronous reset.
        rst_n : in std_logic;
        -- Clears all outputs to a bubble this cycle (control hazard).
        flush : in std_logic;
        -- Holds the register's current outputs unchanged this cycle.
        stall : in std_logic;

        -- ALU result; doubles as the memory address for loads/stores.
        ex_result       : in std_logic_vector(31 downto 0);
        -- Register value for rs2, used as store data.
        ex_operand_b    : in std_logic_vector(31 downto 0);
        -- Destination register address.
        ex_rd_addr      : in std_logic_vector(4 downto 0);
        -- PC+4, carried through for JAL/JALR write-back.
        ex_pc_plus4     : in std_logic_vector(31 downto 0);

        -- Register file write enable.
        ex_reg_write    : in std_logic;
        -- Asserted for load instructions.
        ex_mem_read     : in std_logic;
        -- Asserted for store instructions.
        ex_mem_write    : in std_logic;
        -- Write-back source select (ALU result / memory data / PC+4).
        ex_wb_sel       : in std_logic_vector(1 downto 0);
        -- funct3 field; selects load/store width and sign formatting.
        ex_funct3       : in std_logic_vector(2 downto 0);

        -- Registered ex_result, used as the data memory address.
        mem_addr        : out std_logic_vector(31 downto 0);
        -- Registered ex_result, carried through for write-back.
        mem_result      : out std_logic_vector(31 downto 0);
        -- Registered ex_operand_b, presented to Data_Memory as store data.
        mem_write_data  : out std_logic_vector(31 downto 0);
        -- Registered ex_rd_addr, presented to the MEM stage.
        mem_rd_addr     : out std_logic_vector(4 downto 0);
        -- Registered ex_pc_plus4, presented to the MEM stage.
        mem_pc_plus4    : out std_logic_vector(31 downto 0);

        -- Registered ex_reg_write, presented to the MEM stage.
        mem_reg_write   : out std_logic;
        -- Registered ex_mem_read, presented to the MEM stage.
        mem_read        : out std_logic;
        -- Registered ex_mem_write, presented to the MEM stage.
        mem_write       : out std_logic;
        -- Registered ex_wb_sel, presented to the MEM stage.
        mem_wb_sel      : out std_logic_vector(1 downto 0);
        -- Registered ex_funct3, presented to the MEM stage.
        mem_funct3      : out std_logic_vector(2 downto 0)
    );
end entity EX_MEM_Register;

architecture rtl of EX_MEM_Register is
begin
    process(clk)
    begin
        if rising_edge(clk) then
            if rst_n = '0' then
                mem_addr       <= (others => '0');
                mem_result     <= (others => '0');
                mem_write_data <= (others => '0');
                mem_rd_addr    <= (others => '0');
                mem_pc_plus4   <= (others => '0');
                mem_funct3     <= (others => '0');
                
                -- Control signals
                mem_read       <= '0';
                mem_write      <= '0';
                mem_reg_write  <= '0';
                mem_wb_sel     <= (others => '0');

            elsif flush = '1' then
                -- CRITICAL FIX: Zero out ONLY the control signals to create a bubble.
                -- Do NOT clear data payloads like mem_addr or mem_write_data.
                mem_read       <= '0';
                mem_write      <= '0';
                mem_reg_write  <= '0';
                mem_wb_sel     <= (others => '0');

            elsif stall = '0' then
                -- Normal pipeline advance
                mem_addr       <= ex_result;
                mem_result     <= ex_result;
                mem_write_data <= ex_operand_b;
                mem_rd_addr    <= ex_rd_addr;
                mem_pc_plus4   <= ex_pc_plus4;
                mem_funct3     <= ex_funct3;
                
                -- Control signals
                mem_read       <= ex_mem_read;
                mem_write      <= ex_mem_write;
                mem_reg_write  <= ex_reg_write;
                mem_wb_sel     <= ex_wb_sel;
            end if;
            -- If stall = '1' and flush = '0', no assignments occur,
            -- holding all outputs perfectly stable.
        end if;
    end process;
end architecture rtl;