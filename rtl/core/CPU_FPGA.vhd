library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;

entity CPU_FPGA is
    generic (
        DATA_WIDTH : integer := 32
    );
    port (
        clk          : in  std_logic;
        rst_n        : in  std_logic;
        
        -- External debug outputs
        pc_debug     : out std_logic_vector(DATA_WIDTH-1 downto 0);
        instr_debug  : out std_logic_vector(DATA_WIDTH-1 downto 0);
        rs1_debug    : out std_logic_vector(DATA_WIDTH-1 downto 0);
        rs2_debug    : out std_logic_vector(DATA_WIDTH-1 downto 0);
        
        -- Memory Bus Interface Ports
        mem_addr_out : out std_logic_vector(DATA_WIDTH-1 downto 0);
        mem_wdata_out: out std_logic_vector(DATA_WIDTH-1 downto 0);
        mem_we_out   : out std_logic;
        mem_re_out   : out std_logic;
        mem_rdata_in : in  std_logic_vector(DATA_WIDTH-1 downto 0);
        
        funct3_out   : out std_logic_vector(2 downto 0)
    );
end entity CPU_FPGA;

architecture Structural of CPU_FPGA is

    component IF_Stage is
        generic ( DATA_WIDTH : integer := 32 );
        port (
            clk             : in  std_logic;
            rst_n           : in  std_logic;
            pc_write        : in  std_logic;
            if_id_stall     : in  std_logic;
            if_id_flush     : in  std_logic;
            pc_src          : in  std_logic;
            target_pc       : in  std_logic_vector(31 downto 0);
            pc_current_out  : out std_logic_vector(31 downto 0);
            id_pc_out       : out std_logic_vector(31 downto 0);
            id_instr_out    : out std_logic_vector(31 downto 0)
        );
    end component;

    component ID_Stage is
        port (
            clk             : in  std_logic;
            rst_n           : in  std_logic;
            id_ex_stall     : in  std_logic;
            id_ex_flush     : in  std_logic;
            id_pc_in        : in  std_logic_vector(31 downto 0);
            id_pc_plus4_in  : in  std_logic_vector(31 downto 0);
            id_instr_in     : in  std_logic_vector(31 downto 0);
            wb_reg_write    : in  std_logic;
            wb_rd_addr      : in  std_logic_vector(4 downto 0);
            wb_rd_data      : in  std_logic_vector(31 downto 0);
            id_rs1_addr_out : out std_logic_vector(4 downto 0);
            id_rs2_addr_out : out std_logic_vector(4 downto 0);
            id_rs1_data_out : out std_logic_vector(31 downto 0);
            id_rs2_data_out : out std_logic_vector(31 downto 0);
            ex_pc_out       : out std_logic_vector(31 downto 0);
            ex_pc_plus4_out : out std_logic_vector(31 downto 0);
            ex_imm_ext_out  : out std_logic_vector(31 downto 0);
            ex_reg_data1_out: out std_logic_vector(31 downto 0);
            ex_reg_data2_out: out std_logic_vector(31 downto 0);
            ex_rs1_addr_out : out std_logic_vector(4 downto 0);
            ex_rs2_addr_out : out std_logic_vector(4 downto 0);
            ex_rd_addr_out  : out std_logic_vector(4 downto 0);
            ex_funct3_out   : out std_logic_vector(2 downto 0);
            ex_alu_src_out  : out std_logic;
            ex_alu_ctrl_out : out std_logic_vector(3 downto 0);
            ex_is_m_ext_out : out std_logic;
            ex_mem_read_out : out std_logic;
            ex_mem_write_out: out std_logic;
            ex_branch_out   : out std_logic;
            ex_jump_out     : out std_logic;
            ex_reg_write_out: out std_logic;
            ex_wb_sel_out   : out std_logic_vector(1 downto 0)
        );
    end component;

    component EX_Stage is
        port (
            clk                     : in  std_logic;
            rst_n                   : in  std_logic;
            ex_pc_in                : in  std_logic_vector(31 downto 0);
            ex_imm_ext_in           : in  std_logic_vector(31 downto 0);
            ex_reg_data1_in         : in  std_logic_vector(31 downto 0);
            ex_reg_data2_in         : in  std_logic_vector(31 downto 0);
            ex_rs1_addr_in          : in  std_logic_vector(4 downto 0);
            ex_rs2_addr_in          : in  std_logic_vector(4 downto 0);
            ex_rd_addr_in           : in  std_logic_vector(4 downto 0);
            ex_funct3_in            : in  std_logic_vector(2 downto 0);
            ex_alu_src_in           : in  std_logic;
            ex_alu_ctrl_in          : in  std_logic_vector(3 downto 0);
            ex_is_m_ext_in          : in  std_logic;
            ex_mem_read_in          : in  std_logic;
            ex_mem_write_in         : in  std_logic;
            ex_branch_in            : in  std_logic;
            ex_jump_in              : in  std_logic;
            ex_reg_write_in         : in  std_logic;
            ex_wb_sel_in            : in  std_logic_vector(1 downto 0);
            mem_rd_addr_in          : in  std_logic_vector(4 downto 0);
            mem_reg_write_in        : in  std_logic;
            mem_result_in           : in  std_logic_vector(31 downto 0);
            wb_rd_addr_in           : in  std_logic_vector(4 downto 0);
            wb_reg_write_in         : in  std_logic;
            wb_rd_data_in           : in  std_logic_vector(31 downto 0);
            take_branch_out         : out std_logic;
            target_pc_out           : out std_logic_vector(31 downto 0);
            stall_m_out             : out std_logic;
            mem_result_out          : out std_logic_vector(31 downto 0);
            mem_write_data_out      : out std_logic_vector(31 downto 0);
            mem_rd_addr_out         : out std_logic_vector(4 downto 0);
            mem_reg_write_out       : out std_logic;
            mem_mem_read_out        : out std_logic;
            mem_mem_write_out       : out std_logic;
            mem_wb_sel_out          : out std_logic_vector(1 downto 0);
            mem_funct3_out          : out std_logic_vector(2 downto 0)
        );
    end component;

    component MEM_Stage is
        port (
            clk                 : in  std_logic;
            rst_n               : in  std_logic;
            mem_result_in       : in  std_logic_vector(31 downto 0);
            mem_write_data_in   : in  std_logic_vector(31 downto 0);
            mem_rd_addr_in      : in  std_logic_vector(4 downto 0);
            mem_reg_write_in    : in  std_logic;
            mem_mem_read_in     : in  std_logic;
            mem_mem_write_in    : in  std_logic;
            mem_wb_sel_in       : in  std_logic_vector(1 downto 0);
            mem_funct3_in       : in  std_logic_vector(2 downto 0);
            mem_rdata_ext_in    : in  std_logic_vector(31 downto 0);
            mem_result_fwd_out  : out std_logic_vector(31 downto 0);
            wb_result_out       : out std_logic_vector(31 downto 0);
            wb_read_data_out    : out std_logic_vector(31 downto 0);
            wb_rd_addr_out      : out std_logic_vector(4 downto 0);
            wb_reg_write_out    : out std_logic;
            wb_sel_out          : out std_logic_vector(1 downto 0);
            wb_pc_plus4_out     : out std_logic_vector(31 downto 0)
        );
    end component;

    component Hazard_Unit is
        port (
            stall_m     : in std_logic;
            id_rs1_addr : in std_logic_vector(4 downto 0);
            id_rs2_addr : in std_logic_vector(4 downto 0);
            ex_rd_addr  : in std_logic_vector(4 downto 0);
            ex_mem_read : in std_logic;
            take_branch : in std_logic;
            pc_write    : out std_logic;
            if_id_stall : out std_logic;
            if_id_flush : out std_logic;
            id_ex_stall : out std_logic;
            id_ex_flush : out std_logic
        );
    end component;

    signal pc_write_wire     : std_logic;
    signal if_id_stall_wire  : std_logic;
    signal if_id_flush_wire  : std_logic;
    signal id_ex_stall_wire  : std_logic;
    signal id_ex_flush_wire  : std_logic;
    signal take_branch_wire  : std_logic;
    signal target_pc_wire    : std_logic_vector(31 downto 0);
    signal stall_m_wire      : std_logic;

    signal pc_current        : std_logic_vector(31 downto 0);
    signal id_pc             : std_logic_vector(31 downto 0);
    signal id_instr          : std_logic_vector(31 downto 0);
    signal id_rs1_addr       : std_logic_vector(4 downto 0);
    signal id_rs2_addr       : std_logic_vector(4 downto 0);
    signal id_rs1_data       : std_logic_vector(31 downto 0);
    signal id_rs2_data       : std_logic_vector(31 downto 0);

    signal ex_pc             : std_logic_vector(31 downto 0);
    signal ex_pc_plus4       : std_logic_vector(31 downto 0);
    signal ex_imm_ext        : std_logic_vector(31 downto 0);
    signal ex_reg_data1      : std_logic_vector(31 downto 0);
    signal ex_reg_data2      : std_logic_vector(31 downto 0);
    signal ex_rs1_addr       : std_logic_vector(4 downto 0);
    signal ex_rs2_addr       : std_logic_vector(4 downto 0);
    signal ex_rd_addr        : std_logic_vector(4 downto 0);
    signal ex_funct3         : std_logic_vector(2 downto 0);
    signal ex_alu_src        : std_logic;
    signal ex_alu_ctrl       : std_logic_vector(3 downto 0);
    signal ex_is_m_ext       : std_logic;
    signal ex_mem_read       : std_logic;
    signal ex_mem_write      : std_logic;
    signal ex_branch         : std_logic;
    signal ex_jump           : std_logic;
    signal ex_reg_write      : std_logic;
    signal ex_wb_sel         : std_logic_vector(1 downto 0);

    signal mem_result        : std_logic_vector(31 downto 0);
    signal mem_write_data    : std_logic_vector(31 downto 0);
    signal mem_rd_addr       : std_logic_vector(4 downto 0);
    signal mem_reg_write     : std_logic;
    signal mem_mem_read      : std_logic;
    signal mem_mem_write     : std_logic;
    signal mem_wb_sel        : std_logic_vector(1 downto 0);
    signal mem_funct3        : std_logic_vector(2 downto 0);
    signal mem_result_fwd    : std_logic_vector(31 downto 0);

    signal wb_result         : std_logic_vector(31 downto 0);
    signal wb_read_data      : std_logic_vector(31 downto 0);
    signal wb_rd_addr        : std_logic_vector(4 downto 0);
    signal wb_reg_write      : std_logic;
    signal wb_sel            : std_logic_vector(1 downto 0);
    signal wb_rd_data        : std_logic_vector(31 downto 0);
    signal wb_pc_plus4       : std_logic_vector(31 downto 0);

begin

    mem_addr_out  <= mem_result;
    mem_wdata_out <= mem_write_data;
    mem_we_out    <= mem_mem_write;
    mem_re_out    <= mem_mem_read;
    funct3_out    <= mem_funct3;

    U_STAGE_IF : IF_Stage
        port map (
            clk             => clk,
            rst_n           => rst_n,
            pc_write        => pc_write_wire,
            if_id_stall     => if_id_stall_wire,
            if_id_flush     => if_id_flush_wire,
            pc_src          => take_branch_wire,
            target_pc       => target_pc_wire,
            pc_current_out  => pc_current,
            id_pc_out       => id_pc,
            id_instr_out    => id_instr
        );

    U_STAGE_ID : ID_Stage
        port map (
            clk             => clk,
            rst_n           => rst_n,
            id_ex_stall     => id_ex_stall_wire,
            id_ex_flush     => id_ex_flush_wire,
            id_pc_in        => id_pc,
            id_pc_plus4_in  => std_logic_vector(unsigned(id_pc) + 4),
            id_instr_in     => id_instr,
            wb_reg_write    => wb_reg_write,
            wb_rd_addr      => wb_rd_addr,
            wb_rd_data      => wb_rd_data,
            id_rs1_addr_out => id_rs1_addr,
            id_rs2_addr_out => id_rs2_addr,
            id_rs1_data_out => id_rs1_data,
            id_rs2_data_out => id_rs2_data,
            ex_pc_out       => ex_pc,
            ex_pc_plus4_out => ex_pc_plus4,
            ex_imm_ext_out  => ex_imm_ext,
            ex_reg_data1_out=> ex_reg_data1,
            ex_reg_data2_out=> ex_reg_data2,
            ex_rs1_addr_out => ex_rs1_addr,
            ex_rs2_addr_out => ex_rs2_addr,
            ex_rd_addr_out  => ex_rd_addr,
            ex_funct3_out   => ex_funct3,
            ex_alu_src_out  => ex_alu_src,
            ex_alu_ctrl_out => ex_alu_ctrl,
            ex_is_m_ext_out => ex_is_m_ext,
            ex_mem_read_out => ex_mem_read,
            ex_mem_write_out=> ex_mem_write,
            ex_branch_out   => ex_branch,
            ex_jump_out     => ex_jump,
            ex_reg_write_out=> ex_reg_write,
            ex_wb_sel_out   => ex_wb_sel
        );

    U_STAGE_EX : EX_Stage
        port map (
            clk                     => clk,
            rst_n                   => rst_n,
            ex_pc_in                => ex_pc,
            ex_imm_ext_in           => ex_imm_ext,
            ex_reg_data1_in         => ex_reg_data1,
            ex_reg_data2_in         => ex_reg_data2,
            ex_rs1_addr_in          => ex_rs1_addr,
            ex_rs2_addr_in          => ex_rs2_addr,
            ex_rd_addr_in           => ex_rd_addr,
            ex_funct3_in            => ex_funct3,
            ex_alu_src_in           => ex_alu_src,
            ex_alu_ctrl_in          => ex_alu_ctrl,
            ex_is_m_ext_in          => ex_is_m_ext,
            ex_mem_read_in          => ex_mem_read,
            ex_mem_write_in         => ex_mem_write,
            ex_branch_in            => ex_branch,
            ex_jump_in              => ex_jump,
            ex_reg_write_in         => ex_reg_write,
            ex_wb_sel_in            => ex_wb_sel,
            mem_rd_addr_in          => mem_rd_addr,
            mem_reg_write_in        => mem_reg_write,
            mem_result_in           => mem_result_fwd,
            wb_rd_addr_in           => wb_rd_addr,
            wb_reg_write_in         => wb_reg_write,
            wb_rd_data_in           => wb_rd_data,
            take_branch_out         => take_branch_wire,
            target_pc_out           => target_pc_wire,
            stall_m_out             => stall_m_wire,
            mem_result_out          => mem_result,
            mem_write_data_out      => mem_write_data,
            mem_rd_addr_out         => mem_rd_addr,
            mem_reg_write_out       => mem_reg_write,
            mem_mem_read_out        => mem_mem_read,
            mem_mem_write_out       => mem_mem_write,
            mem_wb_sel_out          => mem_wb_sel,
            mem_funct3_out          => mem_funct3
        );

    U_STAGE_MEM : MEM_Stage
        port map (
            clk                 => clk,
            rst_n               => rst_n,
            mem_result_in       => mem_result,
            mem_write_data_in   => mem_write_data, 
            mem_rd_addr_in      => mem_rd_addr,
            mem_reg_write_in    => mem_reg_write,
            mem_mem_read_in     => mem_mem_read,
            mem_mem_write_in    => mem_mem_write,
            mem_wb_sel_in       => mem_wb_sel,
            mem_funct3_in       => mem_funct3,
            mem_rdata_ext_in    => mem_rdata_in,   
            mem_result_fwd_out  => mem_result_fwd,
            wb_result_out       => wb_result,
            wb_read_data_out    => wb_read_data,
            wb_rd_addr_out      => wb_rd_addr,
            wb_reg_write_out    => wb_reg_write,
            wb_sel_out          => wb_sel,
            wb_pc_plus4_out     => wb_pc_plus4
        );

    U_HAZARD : Hazard_Unit
        port map (
            stall_m     => stall_m_wire,
            id_rs1_addr => id_rs1_addr,
            id_rs2_addr => id_rs2_addr,
            ex_rd_addr  => ex_rd_addr,
            ex_mem_read => ex_mem_read,
            take_branch => take_branch_wire,
            pc_write    => pc_write_wire,
            if_id_stall => if_id_stall_wire,
            if_id_flush => if_id_flush_wire,
            id_ex_stall => id_ex_stall_wire,
            id_ex_flush => id_ex_flush_wire
        );

    with wb_sel select
        wb_rd_data <= wb_result       when "00",
                      wb_read_data    when "01",
                      wb_pc_plus4     when "10",
                      (others => '0') when others;

    pc_debug    <= pc_current;
    instr_debug <= id_instr;
    rs1_debug   <= id_rs1_data;
    rs2_debug   <= id_rs2_data;

end architecture Structural;