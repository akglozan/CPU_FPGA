library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;

entity MEM_Stage is
    port (
        clk                 : in  std_logic;
        rst_n               : in  std_logic;
        
        -- Inputs from EX/MEM Pipeline Register
        mem_result_in       : in  std_logic_vector(31 downto 0);
        mem_write_data_in   : in  std_logic_vector(31 downto 0);
        mem_rd_addr_in      : in  std_logic_vector(4 downto 0);
        mem_pc_plus4_in     : in  std_logic_vector(31 downto 0);
        mem_reg_write_in    : in  std_logic;
        mem_mem_read_in     : in  std_logic;
        mem_mem_write_in    : in  std_logic;
        mem_wb_sel_in       : in  std_logic_vector(1 downto 0);
        mem_funct3_in       : in  std_logic_vector(2 downto 0);
        
        -- External Memory Data Input
        mem_rdata_ext_in    : in  std_logic_vector(31 downto 0);
        
        -- Feedback Output for EX Stage Forwarding Unit
        mem_result_fwd_out  : out std_logic_vector(31 downto 0);
        
        -- Outputs to WB Stage
        wb_result_out       : out std_logic_vector(31 downto 0);
        wb_read_data_out    : out std_logic_vector(31 downto 0);
        wb_rd_addr_out      : out std_logic_vector(4 downto 0);
        wb_reg_write_out    : out std_logic;
        wb_sel_out          : out std_logic_vector(1 downto 0);
        wb_pc_plus4_out     : out std_logic_vector(31 downto 0)
    );
end entity MEM_Stage;

architecture Structural of MEM_Stage is

    component MEM_WB_Register is
        port (
            clk              : in  std_logic;
            rst_n            : in  std_logic;
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

    signal selected_byte   : std_logic_vector(7 downto 0);
    signal selected_half   : std_logic_vector(15 downto 0);
    signal formatted_rdata : std_logic_vector(31 downto 0);

begin

    mem_result_fwd_out <= mem_result_in;
    wb_pc_plus4_out    <= mem_pc_plus4_in;

    with mem_result_in(1 downto 0) select
        selected_byte <= mem_rdata_ext_in(7 downto 0)   when "00",
                         mem_rdata_ext_in(15 downto 8)  when "01",
                         mem_rdata_ext_in(23 downto 16) when "10",
                         mem_rdata_ext_in(31 downto 24) when others;

    selected_half <= mem_rdata_ext_in(15 downto 0) when mem_result_in(1) = '0' 
                     else mem_rdata_ext_in(31 downto 16);

    process(mem_funct3_in, selected_byte, selected_half, mem_rdata_ext_in)
    begin
        case mem_funct3_in is
            when "000"  => formatted_rdata <= std_logic_vector(resize(signed(selected_byte), 32));
            when "001"  => formatted_rdata <= std_logic_vector(resize(signed(selected_half), 32));
            when "010"  => formatted_rdata <= mem_rdata_ext_in;
            when "100"  => formatted_rdata <= std_logic_vector(resize(unsigned(selected_byte), 32));
            when "101"  => formatted_rdata <= std_logic_vector(resize(unsigned(selected_half), 32));
            when others => formatted_rdata <= mem_rdata_ext_in;
        end case;
    end process;

    U_MEM_WB : MEM_WB_Register
        port map (
            clk              => clk,
            rst_n            => rst_n,
            stall            => '0',
            flush            => '0',
            mem_result_in    => mem_result_in,
            mem_read_data_in => formatted_rdata,
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