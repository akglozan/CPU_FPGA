library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- MEM-stage top-level wrapper. Drives a Wishbone-style bus transaction
-- for loads and stores (address, byte-lane select, write data,
-- cyc/stb/we, waiting on ack), and latches the result -- memory read
-- data or the carried-through ALU result -- into the MEM/WB pipeline
-- register via MEM_WB_Register.
entity mem_stage is
    port (
        clk   : in std_logic;
        -- Active-low synchronous reset.
        rst_n : in std_logic;

        -- Stall from the Hazard Unit (mirrors bus_stall_o upstream).
        stall_wb : in std_logic;

        -- Byte address of the memory access.
        mem_addr       : in std_logic_vector(31 downto 0);
        -- ALU result, carried through for non-memory write-back.
        mem_result     : in std_logic_vector(31 downto 0);
        -- rs2 data to store (pre-formatted, not yet lane-aligned).
        mem_write_data : in std_logic_vector(31 downto 0);
        -- Destination register address.
        mem_rd_addr    : in std_logic_vector(4 downto 0);
        -- PC+4, latched through for JAL/JALR write-back.
        mem_pc_plus4 : in std_logic_vector(31 downto 0);

        -- Register file write enable.
        mem_reg_write  : in std_logic;
        -- Asserted for load instructions.
        mem_read       : in std_logic;
        -- Asserted for store instructions.
        mem_write      : in std_logic;
        -- Write-back source select.
        mem_wb_sel      : in std_logic_vector(1 downto 0);
        -- funct3 field; selects byte lane and store data replication.
        mem_funct3      : in std_logic_vector(2 downto 0);

        -- Bus address output.
        wb_addr_o      : out std_logic_vector(31 downto 0);
        -- Byte-replicated store data output to the bus.
        wb_data_o      : out std_logic_vector(31 downto 0);
        -- Bus read data input.
        wb_data_i      : in  std_logic_vector(31 downto 0);
        -- Byte-lane select for the bus write.
        wb_sel_bus_o   : out std_logic_vector(3 downto 0);
        -- Bus write-enable.
        wb_we_o        : out std_logic;
        -- Bus strobe.
        wb_stb_o       : out std_logic;
        -- Bus cycle indicator.
        wb_cyc_o       : out std_logic;
        -- Bus acknowledge input.
        wb_ack_i       : in  std_logic;

        -- Asserted while a bus transaction is in progress without ack.
        bus_stall_o    : out std_logic;

        -- Registered write-back outputs from MEM_WB_Register, below.
        wb_result_o    : out std_logic_vector(31 downto 0);
        wb_read_data_o : out std_logic_vector(31 downto 0);
        wb_rd_addr_o   : out std_logic_vector(4 downto 0);
        wb_pc_plus4_o  : out std_logic_vector(31 downto 0);
        wb_reg_write_o : out std_logic;
        wb_sel_o       : out std_logic_vector(1 downto 0)
    );
end entity mem_stage;

architecture rtl of mem_stage is

    signal bus_access : std_logic;
    signal byte_sel   : std_logic_vector(3 downto 0);

begin

    bus_access <= mem_read or mem_write;

    -- Complete 32-bit byte address.
    wb_addr_o <= mem_addr;

    wb_we_o  <= mem_write;
    wb_cyc_o <= bus_access;
    wb_stb_o <= bus_access;

    bus_stall_o <= bus_access and not wb_ack_i;

    process (mem_funct3, mem_addr, mem_write)
    begin
        byte_sel <= "1111";

        if mem_write = '1' then
            case mem_funct3 is
                when "000" =>
                    case mem_addr(1 downto 0) is
                        when "00" => byte_sel <= "0001";
                        when "01" => byte_sel <= "0010";
                        when "10" => byte_sel <= "0100";
                        when others => byte_sel <= "1000";
                    end case;

                when "001" =>
                    if mem_addr(1) = '0' then
                        byte_sel <= "0011";
                    else
                        byte_sel <= "1100";
                    end if;

                when others =>
                    byte_sel <= "1111";
            end case;
        end if;
    end process;

    wb_sel_bus_o <= byte_sel;

    process (mem_funct3, mem_write_data)
    begin
        case mem_funct3 is
            when "000" =>
                wb_data_o <= mem_write_data(7 downto 0) &
                             mem_write_data(7 downto 0) &
                             mem_write_data(7 downto 0) &
                             mem_write_data(7 downto 0);

            when "001" =>
                wb_data_o <= mem_write_data(15 downto 0) &
                             mem_write_data(15 downto 0);

            when others =>
                wb_data_o <= mem_write_data;
        end case;
    end process;

    u_mem_wb_register : entity work.MEM_WB_Register
        port map (
            clk               => clk,
            rst_n             => rst_n,
            stall             => stall_wb,
            flush             => '0',

            mem_result_in     => mem_result,
            mem_read_data_in  => wb_data_i,
            mem_pc_plus4_in   => mem_pc_plus4,
            rd_addr_in        => mem_rd_addr,

            reg_write_in      => mem_reg_write,
            wb_sel_in         => mem_wb_sel,

            wb_result_out     => wb_result_o,
            wb_read_data_out  => wb_read_data_o,
            wb_pc_plus4_out   => wb_pc_plus4_o,
            wb_rd_addr_out    => wb_rd_addr_o,
            wb_reg_write_out  => wb_reg_write_o,
            wb_sel_out        => wb_sel_o
        );

end architecture rtl;