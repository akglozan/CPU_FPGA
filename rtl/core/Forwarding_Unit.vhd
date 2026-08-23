-- SPDX-License-Identifier: Apache-2.0
-- Copyright 2026 Ozan Akgül
--
-- Licensed under the Apache License, Version 2.0 (the "License");
-- you may not use this file except in compliance with the License.
-- You may obtain a copy of the License at
--
--     http://www.apache.org/licenses/LICENSE-2.0
--
-- Unless required by applicable law or agreed to in writing, software
-- distributed under the License is distributed on an "AS IS" BASIS,
-- WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
-- See the License for the specific language governing permissions and
-- limitations under the License.

library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;

-- EX-stage operand forwarding unit. Compares the EX-stage source
-- register addresses against the MEM- and WB-stage destination
-- registers to detect RAW hazards, and selects the correct forwarding
-- path for each ALU operand so in-flight results can be used before
-- they reach the register file. MEM-stage forwarding is inhibited
-- when the MEM-stage instruction is itself a load (its data isn't
-- ready yet); that case is instead handled by the Hazard Unit's
-- load-use stall.
entity Forwarding_Unit is
    port (
        -- EX-stage source register 1 address.
        ex_rs1_addr   : in  std_logic_vector(4 downto 0);
        -- EX-stage source register 2 address.
        ex_rs2_addr   : in  std_logic_vector(4 downto 0);
        -- MEM-stage destination register address.
        mem_rd_addr   : in  std_logic_vector(4 downto 0);
        -- MEM-stage register-write enable.
        mem_reg_write : in  std_logic;
        -- MEM-stage load indicator; inhibits MEM-stage forwarding since
        -- a load's data isn't available until WB.
        mem_mem_read  : in  std_logic;
        -- WB-stage destination register address.
        wb_rd_addr    : in  std_logic_vector(4 downto 0);
        -- WB-stage register-write enable.
        wb_reg_write  : in  std_logic;
        
        -- Forwarding select for ALU operand A: "00" = no forward (use
        -- the register file), "01" = forward from WB stage,
        -- "10" = forward from MEM stage.
        forward_a     : out std_logic_vector(1 downto 0);
        -- Forwarding select for ALU operand B, same encoding as forward_a.
        forward_b     : out std_logic_vector(1 downto 0)
    );
end entity Forwarding_Unit;

architecture Behavioral of Forwarding_Unit is
begin

process(all)
begin
    -- Forward A: Inhibit MEM-stage forwarding if the instruction is a Load
    if mem_reg_write = '1' and mem_mem_read = '0' and mem_rd_addr /= "00000" and mem_rd_addr = ex_rs1_addr then
        forward_a <= "10";
    elsif wb_reg_write = '1' and wb_rd_addr /= "00000" and wb_rd_addr = ex_rs1_addr then
        forward_a <= "01";
    else
        forward_a <= "00";
    end if;
    
    -- Forward B: Inhibit MEM-stage forwarding if the instruction is a Load
    if mem_reg_write = '1' and mem_mem_read = '0' and mem_rd_addr /= "00000" and mem_rd_addr = ex_rs2_addr then
        forward_b <= "10";
    elsif wb_reg_write = '1' and wb_rd_addr /= "00000" and wb_rd_addr = ex_rs2_addr then
        forward_b <= "01";
    else
        forward_b <= "00";
    end if;

end process;

end architecture Behavioral;