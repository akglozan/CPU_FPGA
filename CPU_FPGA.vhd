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

    -- 1. Program Counter (Using YOUR exact entity port list)
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

    -------------------------------------------------------------------
    -- Internal Interconnect Signals
    -------------------------------------------------------------------
    
    -- IF Stage Signals
    signal pc_current      : std_logic_vector(DATA_WIDTH-1 downto 0);
    signal pc_plus4_wire   : std_logic_vector(DATA_WIDTH-1 downto 0);
    signal if_instruction  : std_logic_vector(DATA_WIDTH-1 downto 0);
    
    -- Default/Control placeholders for PC
    signal pc_write_enable : std_logic := '1';
    signal pc_src_select   : std_logic := '0';
    signal pc_target_addr  : std_logic_vector(DATA_WIDTH-1 downto 0) := (others => '0');

    -- IF/ID Register Controls
    signal if_id_stall     : std_logic := '0';
    signal if_id_flush     : std_logic := '0';

    -- ID Stage Signals
    signal id_pc           : std_logic_vector(31 downto 0);
    signal id_instruction  : std_logic_vector(31 downto 0);
    signal id_rs1_data     : std_logic_vector(31 downto 0);
    signal id_rs2_data     : std_logic_vector(31 downto 0);

    -- Temporary Writeback signals (Will be driven by WB stage later)
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

    -------------------------------------------------------------------
    -- Output Debug Assignments
    -------------------------------------------------------------------
    pc_debug    <= pc_current;
    instr_debug <= id_instruction;
    rs1_debug   <= id_rs1_data;
    rs2_debug   <= id_rs2_data;

end architecture Structural;