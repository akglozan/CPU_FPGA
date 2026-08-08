library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;


entity ID_EX_Register is
    port(
        clk             : in std_logic;
        rst_n             : in std_logic;
        
        -- Hazard control signal. When stall = '1', holds current values (freezes execution).
        stall           : in std_logic;
        
        -- Control hazard signal (e.g., taken branch/jump misprediction).
        -- When flush = '1', clears control signals to insert a NOP bubble into EX stage.
        flush           : in std_logic;
        
        -- Program Counter & Immediate Pathways
        pc_in           : in std_logic_vector(31 downto 0); -- PC from ID stage
        pc_plus4_in     : in std_logic_vector(31 downto 0); -- Sequential PC+4 for JAL/JALR link WB
        imm_ext_in      : in std_logic_vector(31 downto 0); -- Sign-extended immediate from ImmGen
        
        pc_out          : out std_logic_vector(31 downto 0);
        pc_plus4_out    : out std_logic_vector(31 downto 0);
        imm_ext_out     : out std_logic_vector(31 downto 0);
        
        -- Register File Data & Field Indexes
        reg_data1_in    : in std_logic_vector(31 downto 0); -- rs1 data from RegFile
        reg_data2_in    : in std_logic_vector(31 downto 0); -- rs2 data from RegFile
        rs1_addr_in     : in std_logic_vector(4 downto 0);  -- rs1 address (for Forwarding Unit)
        rs2_addr_in     : in std_logic_vector(4 downto 0);  -- rs2 address (for Forwarding Unit)
        rd_addr_in      : in std_logic_vector(4 downto 0);  -- rd destination address
        funct3_in       : in std_logic_vector(2 downto 0);  -- funct3 (for EX branch checks)
        
        reg_data1_out   : out std_logic_vector(31 downto 0);
        reg_data2_out   : out std_logic_vector(31 downto 0);
        rs1_addr_out    : out std_logic_vector(4 downto 0);
        rs2_addr_out    : out std_logic_vector(4 downto 0);
        rd_addr_out     : out std_logic_vector(4 downto 0);
        funct3_out      : out std_logic_vector(2 downto 0);
        
        -- Execution Stage Control Inputs
        alu_src_in      : in std_logic;                     -- 0: RegB, 1: Imm
        alu_ctrl_in     : in std_logic_vector(3 downto 0);  -- ALU opcode selector
        is_m_ext_in     : in std_logic;                     -- 1: Trigger M-extension unit
        
        -- Memory Stage Control Inputs
        mem_read_in     : in std_logic;                     -- Memory Read Enable
        mem_write_in    : in std_logic;                     -- Memory Write Enable
        branch_in       : in std_logic;                     -- Branch decoded
        jump_in         : in std_logic;                     -- Unconditional Jump (JAL/JALR)
        
        -- Write-Back Stage Control Inputs
        reg_write_in    : in std_logic;                     -- RegFile Write Enable
        wb_sel_in       : in std_logic_vector(1 downto 0);  -- 00: ALU, 01: Mem, 10: PC+4
        
        -- Execution Stage Control Outputs
        alu_src_out     : out std_logic;
        alu_ctrl_out    : out std_logic_vector(3 downto 0);
        is_m_ext_out    : out std_logic;
        
        -- Memory Stage Control Outputs
        mem_read_out    : out std_logic;
        mem_write_out   : out std_logic;
        branch_out      : out std_logic;
        jump_out        : out std_logic;
        
        -- Write-Back Stage Control Outputs
        reg_write_out   : out std_logic;
        wb_sel_out      : out std_logic_vector(1 downto 0)
    );
end entity ID_EX_Register;


architecture Behavioral of ID_EX_Register is
begin

process(clk)
begin

	if rising_edge(clk) then
		if rst_n = '0' then
			 -- Reset ALL control outputs to safe defaults (NOP)
			 alu_src_out     <= '0';
			 alu_ctrl_out    <= (others => '0');
			 is_m_ext_out    <= '0';
			 mem_read_out    <= '0';
			 mem_write_out   <= '0';
			 branch_out      <= '0';
			 jump_out        <= '0';
			 reg_write_out   <= '0';
			 wb_sel_out      <= (others => '0');

			 -- Reset data pathways & addresses
			 pc_out          <= (others => '0');
			 pc_plus4_out    <= (others => '0');
			 imm_ext_out     <= (others => '0');
			 reg_data1_out   <= (others => '0');
			 reg_data2_out   <= (others => '0');
			 rs1_addr_out    <= (others => '0');
			 rs2_addr_out    <= (others => '0');
			 rd_addr_out     <= (others => '0');
			 funct3_out      <= (others => '0');

			elsif flush = '1' then
			 -- Flush ALL control outputs to insert a complete NOP bubble
			 alu_src_out     <= '0';
			 alu_ctrl_out    <= (others => '0');
			 is_m_ext_out    <= '0';
			 mem_read_out    <= '0';
			 mem_write_out   <= '0';
			 branch_out      <= '0';
			 jump_out        <= '0';
			 reg_write_out   <= '0';
			 wb_sel_out      <= (others => '0');

			elsif stall = '1' then
			 null; -- Explicitly hold register state
			else
			-- Program Counter & Immediates
			pc_out          <= pc_in;
			pc_plus4_out    <= pc_plus4_in;
			imm_ext_out     <= imm_ext_in;

			-- Register Data & Addresses
			reg_data1_out   <= reg_data1_in;
			reg_data2_out   <= reg_data2_in;
			rs1_addr_out    <= rs1_addr_in;
			rs2_addr_out    <= rs2_addr_in;
			rd_addr_out     <= rd_addr_in;
			funct3_out      <= funct3_in;

			-- Execution Controls
			alu_src_out     <= alu_src_in;
			alu_ctrl_out    <= alu_ctrl_in;
			is_m_ext_out    <= is_m_ext_in;

			-- Memory Controls
			mem_read_out    <= mem_read_in;
			mem_write_out   <= mem_write_in;
			branch_out      <= branch_in;
			jump_out        <= jump_in;

			-- Write-Back Controls
			reg_write_out   <= reg_write_in;
			wb_sel_out      <= wb_sel_in;
		end if;
	end if;
end process;


end architecture Behavioral;