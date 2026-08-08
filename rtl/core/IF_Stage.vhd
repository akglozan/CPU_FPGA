library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;
use IEEE.STD_LOGIC_TEXTIO.all;
use STD.textio.all;

entity IF_Stage is
    generic (
        DATA_WIDTH : integer := 32
    );
    port (
        clk             : in  std_logic;
        rst_n             : in  std_logic;
        
        -- Hazard Controls
        pc_write        : in  std_logic;
        if_id_stall     : in  std_logic;
        if_id_flush     : in  std_logic;
        
        -- Branch / Jump Controls
        pc_src          : in  std_logic;
        target_pc       : in  std_logic_vector(31 downto 0);
        
        -- Outputs to ID Stage & Debug
        pc_current_out  : out std_logic_vector(31 downto 0);
        id_pc_out       : out std_logic_vector(31 downto 0);
        id_instr_out    : out std_logic_vector(31 downto 0)
    );
end entity IF_Stage;

architecture Structural of IF_Stage is

    -- 1. Program Counter
    component Program_Counter is
        generic ( DATA_WIDTH : integer := 32 );
        port (
            clk       : in  std_logic;
            rst_n       : in  std_logic;
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
            rst_n             : in  std_logic;
            stall           : in  std_logic;
            flush           : in  std_logic;
            pc_in           : in  std_logic_vector(31 downto 0);
            instruction_in  : in  std_logic_vector(31 downto 0);
            pc_out          : out std_logic_vector(31 downto 0);
            instruction_out : out std_logic_vector(31 downto 0)
        );
    end component;

    -- Internal signals
    signal pc_wire          : std_logic_vector(31 downto 0);
    signal pc_plus4_wire    : std_logic_vector(31 downto 0);
    signal if_instruction   : std_logic_vector(31 downto 0);

begin

    pc_current_out <= pc_wire;

    -- Instantiations
    U_PC : Program_Counter
        generic map ( DATA_WIDTH => DATA_WIDTH )
        port map (
            clk       => clk,
            rst_n       => rst_n,
            pc_write  => pc_write,
            pc_src    => pc_src,
            target_pc => target_pc,
            pc_out    => pc_wire,
            pc_plus4  => pc_plus4_wire
        );

    U_IMEM : Instruction_Memory
        port map (
            clk         => clk,
            addr        => pc_wire,
            instruction => if_instruction
        );

    U_IF_ID : IF_ID_Register
        port map (
            clk             => clk,
            rst_n             => rst_n,
            stall           => if_id_stall,
            flush           => if_id_flush,
            pc_in           => pc_wire,
            instruction_in  => if_instruction,
            pc_out          => id_pc_out,
            instruction_out => id_instr_out
        );

end architecture Structural;