-- SPDX-License-Identifier: Apache-2.0
-- Copyright 2026 Ozan Akgül

library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;

entity MEM_Stage is
    port (
        clk                 : in  std_logic;
        rst_n               : in  std_logic;
        stall_wb            : in  std_logic; -- From Hazard Unit
        
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
        
        -- Wishbone B4 Master Port (To bus_interconnect)
        wb_adr_o            : out std_logic_vector(31 downto 0);
        wb_dat_o            : out std_logic_vector(31 downto 0);
        wb_dat_i            : in  std_logic_vector(31 downto 0);
        wb_sel_o            : out std_logic_vector(3 downto 0);
        wb_we_o             : out std_logic;
        wb_stb_o            : out std_logic;
        wb_cyc_o            : out std_logic;
        wb_ack_i            : in  std_logic;
        
        -- Hazard Stall Output to Hazard Unit
        bus_stall_out       : out std_logic;

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

    signal is_bus_access   : std_logic;
    signal byte_enable     : std_logic_vector(3 downto 0);
    signal selected_byte   : std_logic_vector(7 downto 0);
    signal selected_half   : std_logic_vector(15 downto 0);
    signal formatted_rdata : std_logic_vector(31 downto 0);

begin

    mem_result_fwd_out <= mem_result_in;
    wb_pc_plus4_out    <= mem_pc_plus4_in;

    -- Bus control signals
    is_bus_access <= mem_mem_read_in or mem_mem_write_in;
    wb_adr_o      <= mem_result_in;
    wb_dat_o      <= mem_write_data_in;
    wb_we_o       <= mem_mem_write_in;
    wb_cyc_o      <= is_bus_access;
    wb_stb_o      <= is_bus_access;
    
    -- Stall the CPU pipeline if bus cycle is active and not acknowledged
    bus_stall_out <= is_bus_access and (not wb_ack_i);

    -- Generate Wishbone byte-select signals (SB, SH, SW)
    process(mem_funct3_in, mem_result_in(1 downto 0), mem_mem_write_in)
    begin
        if mem_mem_write_in = '1' then
            case mem_funct3_in is
                when "000" => -- SB
                    case mem_result_in(1 downto 0) is
                        when "00"   => byte_enable <= "0001";
                        when "01"   => byte_enable <= "0010";
                        when "10"   => byte_enable <= "0100";
                        when others => byte_enable <= "1000";
                    end case;
                when "001" => -- SH
                    if mem_result_in(1) = '0' then
                        byte_enable <= "0011";
                    else
                        byte_enable <= "1100";
                    end if;
                when others => -- SW
                    byte_enable <= "1111";
            end case;
        else
            byte_enable <= "1111"; -- Full read
        end if;
    end process;
    
    wb_sel_o <= byte_enable;

    -- Read Data Formatting (LB, LH, LW, LBU, LHU)
    with mem_result_in(1 downto 0) select
        selected_byte <= wb_dat_i(7 downto 0)   when "00",
                         wb_dat_i(15 downto 8)  when "01",
                         wb_dat_i(23 downto 16) when "10",
                         wb_dat_i(31 downto 24) when others;

    selected_half <= wb_dat_i(15 downto 0) when mem_result_in(1) = '0' 
                     else wb_dat_i(31 downto 16);

    process(mem_funct3_in, selected_byte, selected_half, wb_dat_i)
    begin
        case mem_funct3_in is
            when "000"  => formatted_rdata <= std_logic_vector(resize(signed(selected_byte), 32));
            when "001"  => formatted_rdata <= std_logic_vector(resize(signed(selected_half), 32));
            when "010"  => formatted_rdata <= wb_dat_i;
            when "100"  => formatted_rdata <= std_logic_vector(resize(unsigned(selected_byte), 32));
            when "101"  => formatted_rdata <= std_logic_vector(resize(unsigned(selected_half), 32));
            when others => formatted_rdata <= wb_dat_i;
        end case;
    end process;

    U_MEM_WB : MEM_WB_Register
        port map (
            clk              => clk,
            rst_n            => rst_n,
            stall            => stall_wb,
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