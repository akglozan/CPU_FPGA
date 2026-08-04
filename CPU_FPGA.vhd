library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;

entity CPU_FPGA is
    generic (
        DATA_WIDTH : integer := 32
    );
    port (
        clk         : in  std_logic;
        rst         : in  std_logic;
        
        -- External debug outputs for simulation/RTL Viewer
        pc_debug    : out std_logic_vector(DATA_WIDTH-1 downto 0);
        instr_debug : out std_logic_vector(DATA_WIDTH-1 downto 0);
        rs1_debug   : out std_logic_vector(DATA_WIDTH-1 downto 0);
        rs2_debug   : out std_logic_vector(DATA_WIDTH-1 downto 0)
    );
end entity CPU_FPGA;

architecture Structural of CPU_FPGA is

    -------------------------------------------------------------------
    -- Component Declarations
    -------------------------------------------------------------------

    -- 1. Program Counter
    component Program_Counter is
        generic (
            DATA_WIDTH : integer := 32
        );
        port (
            clk       : in  std_logic;
            rst       : in  std_logic;
            pc_write  : in  std_logic;
            pc_src    : in  std_logic;
            target_pc : in  std_logic_vector(DATA_WIDTH-1 downto 0);
            pc_out    : out std_logic_vector(DATA_WIDTH-1 downto 0);
            pc_plus4  : out std_logic_vector(DATA_WIDTH-1 downto 0)
        );
    end component;

    -- 2. Instruction Memory
    component Instruction_Memory is
        port (
            clk         : in  std_logic;
            addr        : in  std_logic_vector(31 downto 0);
            instruction : out std_logic_vector(31 downto 0)
        );
    end component;

    -- 3. IF/ID Pipeline Register
    component IF_ID_Register is
        port (
            clk             : in  std_logic;
            rst             : in  std_logic;
            stall           : in  std_logic;
            flush           : in  std_logic;
            pc_in           : in  std_logic_vector(31 downto 0);
            instruction_in  : in  std_logic_vector(31 downto 0);
            pc_out          : out std_logic_vector(31 downto 0);
            instruction_out : out std_logic_vector(31 downto 0)
        );
    end component;

    -- 4. Register File
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

    -- 5. Control Unit
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

    -- 6. Immediate Generator
    component ImmGen is
        port (
            inst    : in  std_logic_vector(31 downto 0);
            imm_src : in  std_logic_vector(2 downto 0);
            imm_ext : out std_logic_vector(31 downto 0)
        );
    end component;

    -- 7. ID/EX Pipeline Register
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

    -- 8. Base Integer ALU
    component ALU is
        port (
            alu_ctrl   : in  std_logic_vector(3 downto 0);
            operand_a  : in  std_logic_vector(31 downto 0);
            operand_b  : in  std_logic_vector(31 downto 0);
            alu_result : out std_logic_vector(31 downto 0);
            zero_flag  : out std_logic
        );
    end component;

    -- 9. RV32M Extension Unit
    component M_Extension_Unit is
        port (
            clk       : in  std_logic;
            reset     : in  std_logic;
            is_m_ext  : in  std_logic;
            funct3    : in  std_logic_vector(2 downto 0);
            operand_a : in  std_logic_vector(31 downto 0);
            operand_b : in  std_logic_vector(31 downto 0);
            m_result  : out std_logic_vector(31 downto 0);
            stall_m   : out std_logic
        );
    end component;

    -------------------------------------------------------------------
    -- Internal Interconnect Signals
    -------------------------------------------------------------------
    
    -- IF Stage Signals
    signal pc_current      : std_logic_vector(DATA_WIDTH-1 downto 0);
    signal pc_plus4_wire   : std_logic_vector(DATA_WIDTH-1 downto 0);
    signal if_instruction  : std_logic_vector(DATA_WIDTH-1 downto 0);
    
    -- Control placeholders for PC
    signal pc_write_enable : std_logic := '1';
    signal pc_src_select   : std_logic := '0';
    signal pc_target_addr  : std_logic_vector(DATA_WIDTH-1 downto 0) := (others => '0');

    -- IF/ID Pipeline Register Controls
    signal if_id_stall     : std_logic := '0';
    signal if_id_flush     : std_logic := '0';

    -- ID Stage Signals
    signal id_pc           : std_logic_vector(31 downto 0);
    signal id_instruction  : std_logic_vector(31 downto 0);
    signal id_rs1_data     : std_logic_vector(31 downto 0);
    signal id_rs2_data     : std_logic_vector(31 downto 0);
    signal id_imm_ext      : std_logic_vector(31 downto 0);

    -- Control Unit ID Stage Signals
    signal id_imm_src      : std_logic_vector(2 downto 0);
    signal id_alu_src      : std_logic;
    signal id_reg_write    : std_logic;
    signal id_mem_read     : std_logic;
    signal id_mem_write    : std_logic;
    signal id_wb_sel       : std_logic_vector(1 downto 0);
    signal id_branch       : std_logic;
    signal id_jump         : std_logic;
    signal id_alu_ctrl     : std_logic_vector(3 downto 0);
    signal id_is_m_ext     : std_logic;

    -- ID/EX Pipeline Register Controls
    signal id_ex_stall     : std_logic := '0';
    signal id_ex_flush     : std_logic := '0';

    -- EX Stage Interconnect Signals (Outputs of ID_EX_Register)
    signal ex_pc           : std_logic_vector(31 downto 0);
    signal ex_pc_plus4     : std_logic_vector(31 downto 0);
    signal ex_imm_ext      : std_logic_vector(31 downto 0);
    signal ex_reg_data1    : std_logic_vector(31 downto 0);
    signal ex_reg_data2    : std_logic_vector(31 downto 0);
    signal ex_rs1_addr     : std_logic_vector(4 downto 0);
    signal ex_rs2_addr     : std_logic_vector(4 downto 0);
    signal ex_rd_addr      : std_logic_vector(4 downto 0);
    signal ex_funct3       : std_logic_vector(2 downto 0);
    signal ex_alu_src      : std_logic;
    signal ex_alu_ctrl     : std_logic_vector(3 downto 0);
    signal ex_is_m_ext     : std_logic;
    signal ex_mem_read     : std_logic;
    signal ex_mem_write    : std_logic;
    signal ex_branch       : std_logic;
    signal ex_jump         : std_logic;
    signal ex_reg_write    : std_logic;
    signal ex_wb_sel       : std_logic_vector(1 downto 0);

    -- EX Stage Datapath & Execution Results
    signal ex_alu_operand_b: std_logic_vector(31 downto 0);
    signal ex_base_alu_res : std_logic_vector(31 downto 0);
    signal ex_zero_flag    : std_logic;
    signal ex_m_ext_res    : std_logic_vector(31 downto 0);
    signal ex_final_result : std_logic_vector(31 downto 0);
    signal stall_m_wire    : std_logic;

    -- Temporary Writeback signals (Driven by WB stage in later steps)
    signal wb_reg_write    : std_logic := '0';
    signal wb_rd_addr      : std_logic_vector(4 downto 0) := (others => '0');
    signal wb_rd_data      : std_logic_vector(31 downto 0) := (others => '0');

begin

    -------------------------------------------------------------------
    -- IF Stage Logic & Port Maps
    -------------------------------------------------------------------

    -- Program Counter Instance
    U_PC : Program_Counter
        generic map (
            DATA_WIDTH => DATA_WIDTH
        )
        port map (
            clk       => clk,
            rst       => rst,
            pc_write  => pc_write_enable,
            pc_src    => pc_src_select,
            target_pc => pc_target_addr,
            pc_out    => pc_current,
            pc_plus4  => pc_plus4_wire
        );

    -- Instruction Memory Instance
    U_IMEM : Instruction_Memory
        port map (
            clk         => clk,
            addr        => pc_current,
            instruction => if_instruction
        );

    -------------------------------------------------------------------
    -- Pipeline Register: IF / ID
    -------------------------------------------------------------------

    U_IF_ID : IF_ID_Register
        port map (
            clk             => clk,
            rst             => rst,
            stall           => if_id_stall,
            flush           => if_id_flush,
            pc_in           => pc_current,
            instruction_in  => if_instruction,
            pc_out          => id_pc,
            instruction_out => id_instruction
        );

    -------------------------------------------------------------------
    -- ID Stage Logic & Port Maps
    -------------------------------------------------------------------

    -- Register File Instance
    U_REGFILE : RegFile
        port map (
            clk       => clk,
            rst       => rst,
            reg_write => wb_reg_write,
            rd_addr   => wb_rd_addr,
            rs1_addr  => id_instruction(19 downto 15),
            rs2_addr  => id_instruction(24 downto 20),
            rd_data   => wb_rd_data,
            rs1_data  => id_rs1_data,
            rs2_data  => id_rs2_data
        );

    -- Control Unit Instance
    U_CONTROL : Control_Unit
        port map (
            opcode    => id_instruction(6 downto 0),
            funct3    => id_instruction(14 downto 12),
            funct7    => id_instruction(31 downto 25),
            imm_src   => id_imm_src,
            alu_src   => id_alu_src,
            reg_write => id_reg_write,
            mem_read  => id_mem_read,
            mem_write => id_mem_write,
            wb_sel    => id_wb_sel,
            branch    => id_branch,
            jump      => id_jump,
            alu_ctrl  => id_alu_ctrl,
            is_m_ext  => id_is_m_ext
        );

    -- Immediate Generator Instance
    U_IMMGEN : ImmGen
        port map (
            inst    => id_instruction,
            imm_src => id_imm_src,
            imm_ext => id_imm_ext
        );

    -------------------------------------------------------------------
    -- Pipeline Register: ID / EX
    -------------------------------------------------------------------

    U_ID_EX : ID_EX_Register
        port map (
            clk           => clk,
            rst           => rst,
            stall         => id_ex_stall,
            flush         => id_ex_flush,
            
            pc_in         => id_pc,
            pc_plus4_in   => pc_plus4_wire,
            imm_ext_in    => id_imm_ext,
            reg_data1_in  => id_rs1_data,
            reg_data2_in  => id_rs2_data,
            rs1_addr_in   => id_instruction(19 downto 15),
            rs2_addr_in   => id_instruction(24 downto 20),
            rd_addr_in    => id_instruction(11 downto 7),
            funct3_in     => id_instruction(14 downto 12),
            
            alu_src_in    => id_alu_src,
            alu_ctrl_in   => id_alu_ctrl,
            is_m_ext_in   => id_is_m_ext,
            mem_read_in   => id_mem_read,
            mem_write_in  => id_mem_write,
            branch_in     => id_branch,
            jump_in       => id_jump,
            reg_write_in  => id_reg_write,
            wb_sel_in     => id_wb_sel,
            
            pc_out        => ex_pc,
            pc_plus4_out  => ex_pc_plus4,
            imm_ext_out   => ex_imm_ext,
            reg_data1_out => ex_reg_data1,
            reg_data2_out => ex_reg_data2,
            rs1_addr_out  => ex_rs1_addr,
            rs2_addr_out  => ex_rs2_addr,
            rd_addr_out   => ex_rd_addr,
            funct3_out    => ex_funct3,
            
            alu_src_out   => ex_alu_src,
            alu_ctrl_out  => ex_alu_ctrl,
            is_m_ext_out  => ex_is_m_ext,
            mem_read_out  => ex_mem_read,
            mem_write_out => ex_mem_write,
            branch_out    => ex_branch,
            jump_out      => ex_jump,
            reg_write_out => ex_reg_write,
            wb_sel_out    => ex_wb_sel
        );

    -------------------------------------------------------------------
    -- EX Stage Datapath & Hardware Units
    -------------------------------------------------------------------

    -- ALU Operand B MUX (Register Data vs Extended Immediate)
    ex_alu_operand_b <= ex_imm_ext when ex_alu_src = '1' else ex_reg_data2;

    -- Base Integer ALU Instance
    U_ALU : ALU
        port map (
            alu_ctrl   => ex_alu_ctrl,
            operand_a  => ex_reg_data1,
            operand_b  => ex_alu_operand_b,
            alu_result => ex_base_alu_res,
            zero_flag  => ex_zero_flag
        );

    -- M-Extension Hardware Unit Instance
    U_M_EXT : M_Extension_Unit
        port map (
            clk       => clk,
            reset     => rst,
            is_m_ext  => ex_is_m_ext,
            funct3    => ex_funct3,
            operand_a => ex_reg_data1,
            operand_b => ex_reg_data2,
            m_result  => ex_m_ext_res,
            stall_m   => stall_m_wire
        );

    -- Execution Stage Result Multiplexer (ALU vs M-Extension)
    ex_final_result <= ex_m_ext_res when ex_is_m_ext = '1' else ex_base_alu_res;

    -------------------------------------------------------------------
    -- Output Debug Assignments
    -------------------------------------------------------------------
    pc_debug    <= pc_current;
    instr_debug <= id_instruction;
    rs1_debug   <= id_rs1_data;
    rs2_debug   <= id_rs2_data;

end architecture Structural;