library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;

entity ID_Stage is
    port (
        clk             : in  std_logic;
        rst             : in  std_logic;
        
        -- Hazard Controls from Hazard_Unit
        id_ex_stall     : in  std_logic;
        id_ex_flush     : in  std_logic;
        
        -- Inputs from IF/ID Register
        id_pc_in        : in  std_logic_vector(31 downto 0);
        id_pc_plus4_in  : in  std_logic_vector(31 downto 0);
        id_instr_in     : in  std_logic_vector(31 downto 0);
        
        -- Inputs from WB Stage (Writeback Loop)
        wb_reg_write    : in  std_logic;
        wb_rd_addr      : in  std_logic_vector(4 downto 0);
        wb_rd_data      : in  std_logic_vector(31 downto 0);
        
        -- Outputs to Hazard Unit
        id_rs1_addr_out : out std_logic_vector(4 downto 0);
        id_rs2_addr_out : out std_logic_vector(4 downto 0);
		  id_rs1_data_out : out std_logic_vector(31 downto 0); -- NEW DEBUG OUTPUT
        id_rs2_data_out : out std_logic_vector(31 downto 0); -- NEW DEBUG OUTPUT
        
        -- Outputs from ID/EX Pipeline Register to EX Stage
        ex_pc_out       : out std_logic_vector(31 downto 0);
        ex_pc_plus4_out : out std_logic_vector(31 downto 0);
        ex_imm_ext_out  : out std_logic_vector(31 downto 0);
        ex_reg_data1_out: out std_logic_vector(31 downto 0);
        ex_reg_data2_out: out std_logic_vector(31 downto 0);
        ex_rs1_addr_out : out std_logic_vector(4 downto 0);
        ex_rs2_addr_out : out std_logic_vector(4 downto 0);
        ex_rd_addr_out  : out std_logic_vector(4 downto 0);
        ex_funct3_out   : out std_logic_vector(2 downto 0);
        
        -- EX Control Outputs
        ex_alu_src_out  : out std_logic;
        ex_alu_ctrl_out : out std_logic_vector(3 downto 0);
        ex_is_m_ext_out : out std_logic;  -- Matched port name
        ex_mem_read_out : out std_logic;
        ex_mem_write_out: out std_logic;
        ex_branch_out   : out std_logic;
        ex_jump_out     : out std_logic;
        ex_reg_write_out: out std_logic;
        ex_wb_sel_out   : out std_logic_vector(1 downto 0)
    );
end entity ID_Stage;

architecture Structural of ID_Stage is

    -- Components
    component RegFile is
        port (
            clk       : in  std_logic;
            rst       : in  std_logic;
            reg_write : in  std_logic;
            rd_addr   : in  std_logic_vector(4 downto 0);
            rs1_addr  : in  std_logic_vector(4 downto 0);
            rs2_addr  : in  std_logic_vector(4 downto 0);
            rd_data   : in  std_logic_vector(31 downto 0);
            rs1_data  : out std_logic_vector(31 downto 0);
            rs2_data  : out std_logic_vector(31 downto 0)
        );
    end component;

    component Control_Unit is
        port (
            opcode    : in  std_logic_vector(6 downto 0);
            funct3    : in  std_logic_vector(2 downto 0);
            funct7    : in  std_logic_vector(6 downto 0);
            imm_src   : out std_logic_vector(2 downto 0);
            alu_src   : out std_logic;
            reg_write : out std_logic;
            mem_read  : out std_logic;
            mem_write : out std_logic;
            wb_sel    : out std_logic_vector(1 downto 0);
            branch    : out std_logic;
            jump      : out std_logic;
            alu_ctrl  : out std_logic_vector(3 downto 0);
            is_m_ext  : out std_logic
        );
    end component;

    component ImmGen is
        port (
            inst    : in  std_logic_vector(31 downto 0);
            imm_src : in  std_logic_vector(2 downto 0);
            imm_ext : out std_logic_vector(31 downto 0)
        );
    end component;

    component ID_EX_Register is
        port (
            clk           : in  std_logic;
            rst           : in  std_logic;
            stall         : in  std_logic;
            flush         : in  std_logic;
            pc_in         : in  std_logic_vector(31 downto 0);
            pc_plus4_in   : in  std_logic_vector(31 downto 0);
            imm_ext_in    : in  std_logic_vector(31 downto 0);
            pc_out        : out std_logic_vector(31 downto 0);
            pc_plus4_out  : out std_logic_vector(31 downto 0);
            imm_ext_out   : out std_logic_vector(31 downto 0);
            reg_data1_in  : in  std_logic_vector(31 downto 0);
            reg_data2_in  : in  std_logic_vector(31 downto 0);
            rs1_addr_in   : in  std_logic_vector(4 downto 0);
            rs2_addr_in   : in  std_logic_vector(4 downto 0);
            rd_addr_in    : in  std_logic_vector(4 downto 0);
            funct3_in     : in  std_logic_vector(2 downto 0);
            reg_data1_out : out std_logic_vector(31 downto 0);
            reg_data2_out : out std_logic_vector(31 downto 0);
            rs1_addr_out  : out std_logic_vector(4 downto 0);
            rs2_addr_out  : out std_logic_vector(4 downto 0);
            rd_addr_out   : out std_logic_vector(4 downto 0);
            funct3_out    : out std_logic_vector(2 downto 0);
            alu_src_in    : in  std_logic;
            alu_ctrl_in   : in  std_logic_vector(3 downto 0);
            is_m_ext_in   : in  std_logic;
            mem_read_in   : in  std_logic;
            mem_write_in  : in  std_logic;
            branch_in     : in  std_logic;
            jump_in       : in  std_logic;
            reg_write_in  : in  std_logic;
            wb_sel_in     : in  std_logic_vector(1 downto 0);
            alu_src_out   : out std_logic;
            alu_ctrl_out  : out std_logic_vector(3 downto 0);
            is_m_ext_out  : out std_logic;
            mem_read_out  : out std_logic;
            mem_write_out : out std_logic;
            branch_out    : out std_logic;
            jump_out      : out std_logic;
            reg_write_out : out std_logic;
            wb_sel_out    : out std_logic_vector(1 downto 0)
        );
    end component;

    -- Internal signals
    signal rs1_addr_wire : std_logic_vector(4 downto 0);
    signal rs2_addr_wire : std_logic_vector(4 downto 0);
    signal rd_addr_wire  : std_logic_vector(4 downto 0);
    signal funct3_wire   : std_logic_vector(2 downto 0);
    
    signal reg_data1_wire: std_logic_vector(31 downto 0);
    signal reg_data2_wire: std_logic_vector(31 downto 0);
    signal imm_ext_wire  : std_logic_vector(31 downto 0);
    
    signal imm_src_wire  : std_logic_vector(2 downto 0);
    signal alu_src_wire  : std_logic;
    signal reg_write_wire: std_logic;
    signal mem_read_wire : std_logic;
    signal mem_write_wire: std_logic;
    signal wb_sel_wire   : std_logic_vector(1 downto 0);
    signal branch_wire   : std_logic;
    signal jump_wire     : std_logic;
    signal alu_ctrl_wire : std_logic_vector(3 downto 0);
    signal is_m_ext_wire : std_logic;

begin

    rs1_addr_wire <= id_instr_in(19 downto 15);
    rs2_addr_wire <= id_instr_in(24 downto 20);
    rd_addr_wire  <= id_instr_in(11 downto 7);
    funct3_wire   <= id_instr_in(14 downto 12);

    id_rs1_addr_out <= rs1_addr_wire;
    id_rs2_addr_out <= rs2_addr_wire;
	 
	 -- Drive Debug Data Outputs Directly
    id_rs1_data_out <= reg_data1_wire;
    id_rs2_data_out <= reg_data2_wire;

    U_REGFILE : RegFile
        port map (
            clk       => clk,
            rst       => rst,
            reg_write => wb_reg_write,
            rd_addr   => wb_rd_addr,
            rs1_addr  => rs1_addr_wire,
            rs2_addr  => rs2_addr_wire,
            rd_data   => wb_rd_data,
            rs1_data  => reg_data1_wire,
            rs2_data  => reg_data2_wire
        );

    U_CONTROL : Control_Unit
        port map (
            opcode    => id_instr_in(6 downto 0),
            funct3    => funct3_wire,
            funct7    => id_instr_in(31 downto 25),
            imm_src   => imm_src_wire,
            alu_src   => alu_src_wire,
            reg_write => reg_write_wire,
            mem_read  => mem_read_wire,
            mem_write => mem_write_wire,
            wb_sel    => wb_sel_wire,
            branch    => branch_wire,
            jump      => jump_wire,
            alu_ctrl  => alu_ctrl_wire,
            is_m_ext  => is_m_ext_wire
        );

    U_IMMGEN : ImmGen
        port map (
            inst    => id_instr_in,
            imm_src => imm_src_wire,
            imm_ext => imm_ext_wire
        );

    U_ID_EX : ID_EX_Register
        port map (
            clk           => clk,
            rst           => rst,
            stall         => id_ex_stall,
            flush         => id_ex_flush,
            pc_in         => id_pc_in,
            pc_plus4_in   => id_pc_plus4_in,
            imm_ext_in    => imm_ext_wire,
            pc_out        => ex_pc_out,
            pc_plus4_out  => ex_pc_plus4_out,
            imm_ext_out   => ex_imm_ext_out,
            reg_data1_in  => reg_data1_wire,
            reg_data2_in  => reg_data2_wire,
            rs1_addr_in   => rs1_addr_wire,
            rs2_addr_in   => rs2_addr_wire,
            rd_addr_in    => rd_addr_wire,
            funct3_in     => funct3_wire,
            reg_data1_out => ex_reg_data1_out,
            reg_data2_out => ex_reg_data2_out,
            rs1_addr_out  => ex_rs1_addr_out,
            rs2_addr_out  => ex_rs2_addr_out,
            rd_addr_out   => ex_rd_addr_out,
            funct3_out    => ex_funct3_out,
            alu_src_in    => alu_src_wire,
            alu_ctrl_in   => alu_ctrl_wire,
            is_m_ext_in   => is_m_ext_wire,
            mem_read_in   => mem_read_wire,
            mem_write_in  => mem_write_wire,
            branch_in     => branch_wire,
            jump_in       => jump_wire,
            reg_write_in  => reg_write_wire,
            wb_sel_in     => wb_sel_wire,
            alu_src_out   => ex_alu_src_out,
            alu_ctrl_out  => ex_alu_ctrl_out,
            is_m_ext_out  => ex_is_m_ext_out,  -- Mapped correctly to entity port
            mem_read_out  => ex_mem_read_out,
            mem_write_out => ex_mem_write_out,
            branch_out    => ex_branch_out,
            jump_out      => ex_jump_out,
            reg_write_out => ex_reg_write_out,
            wb_sel_out    => ex_wb_sel_out
        );

end architecture Structural;