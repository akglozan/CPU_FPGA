library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;

entity MEM_Stage is
    port (
        clk                 : in  std_logic;
        rst                 : in  std_logic;
        
        -- Inputs from EX/MEM Pipeline Register
        mem_result_in       : in  std_logic_vector(31 downto 0);
        mem_write_data_in   : in  std_logic_vector(31 downto 0);
        mem_rd_addr_in      : in  std_logic_vector(4 downto 0);
        mem_reg_write_in    : in  std_logic;
        mem_mem_read_in     : in  std_logic;
        mem_mem_write_in    : in  std_logic;
        mem_wb_sel_in       : in  std_logic_vector(1 downto 0);
        mem_funct3_in       : in  std_logic_vector(2 downto 0);
        
        -- Direct Feedback Output for EX Stage Forwarding Unit
        mem_result_fwd_out  : out std_logic_vector(31 downto 0);
        
        -- Outputs from MEM/WB Pipeline Register to WB Stage
        wb_result_out       : out std_logic_vector(31 downto 0);
        wb_read_data_out    : out std_logic_vector(31 downto 0);
        wb_rd_addr_out      : out std_logic_vector(4 downto 0);
        wb_reg_write_out    : out std_logic;
        wb_sel_out          : out std_logic_vector(1 downto 0)
    );
end entity MEM_Stage;

architecture Structural of MEM_Stage is

    -- Components
    component Data_Memory is
        port (
            clk        : in  std_logic;
            mem_write  : in  std_logic;
            mem_read   : in  std_logic;
            funct3     : in  std_logic_vector(2 downto 0);
            addr       : in  std_logic_vector(31 downto 0);
            write_data : in  std_logic_vector(31 downto 0);
            read_data  : out std_logic_vector(31 downto 0)
        );
    end component;

    component MEM_WB_Register is
        port (
            clk              : in  std_logic;
            reset            : in  std_logic;
            stall            : in  std_logic;
            flush            : in  std_logic;
            mem_result_in    : in  std_logic_vector(31 downto 0);
            mem_read_data_in : in  std_logic_vector(31 downto 0);
            rd_addr_in       : in  std_logic_vector(4 downto 0);
            reg_write_in     : in  std_logic;
            wb_sel_in        : in  std_logic_vector(1 downto 0);
            wb_result_out    : out std_logic_vector(31 downto 0);
            wb_read_data_out : out std_logic_vector(31 downto 0);
            wb_rd_addr_out   : out std_logic_vector(4 downto 0);
            wb_reg_write_out : out std_logic;
            wb_sel_out       : out std_logic_vector(1 downto 0)
        );
    end component;

    -- Internal Stage Signals
    signal mem_read_data_wire : std_logic_vector(31 downto 0);

begin

    -- Pass-through execution result for EX forwarding
    mem_result_fwd_out <= mem_result_in;

    -- Data Memory Instantiation
    U_DMEM : Data_Memory
        port map (
            clk        => clk,
            mem_write  => mem_mem_write_in,
            mem_read   => mem_mem_read_in,
            funct3     => mem_funct3_in,
            addr       => mem_result_in,
            write_data => mem_write_data_in,
            read_data  => mem_read_data_wire
        );

    -- MEM/WB Pipeline Register Instantiation
    U_MEM_WB : MEM_WB_Register
        port map (
            clk              => clk,
            reset            => rst,
            stall            => '0',
            flush            => '0',
            mem_result_in    => mem_result_in,
            mem_read_data_in => mem_read_data_wire,
            rd_addr_in       => mem_rd_addr_in,
            reg_write_in     => mem_reg_write_in,
            wb_sel_in        => mem_wb_sel_in,
            wb_result_out    => wb_result_out,
            wb_read_data_out => wb_read_data_out,
            wb_rd_addr_out   => wb_rd_addr_out,
            wb_reg_write_out => wb_reg_write_out,
            wb_sel_out       => wb_sel_out
        );

end architecture Structural;