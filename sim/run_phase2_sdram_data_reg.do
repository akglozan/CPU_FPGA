# ==============================================================================
# ModelSim / QuestaSim Automated Simulation Script (.do)
# Target: tb_rv32im_soc
# Execution Directory: akglozan-cpu_fpga/sim/
# ==============================================================================

# 1. Close any active simulation and reset work library
quit -sim

if {[file exists work]} {
    vdel -lib work -all
}
vlib work
vmap work work

# 2. Compile Core Stage Components & Arithmetic Units
vcom -2008 -work work ../rtl/core/Program_Counter.vhd
vcom -2008 -work work ../rtl/core/RegFile.vhd
vcom -2008 -work work ../rtl/core/ImmGen.vhd
vcom -2008 -work work ../rtl/core/ALU.vhd
vcom -2008 -work work ../rtl/core/M_Extension_Unit.vhd
vcom -2008 -work work ../rtl/core/Control_Unit.vhd
vcom -2008 -work work ../rtl/core/Hazard_Unit.vhd
vcom -2008 -work work ../rtl/core/Forwarding_Unit.vhd
vcom -2008 -work work ../rtl/core/Instruction_Memory.vhd
vcom -2008 -work work ../rtl/core/Data_Memory.vhd

# 3. Compile Core Pipeline Registers (Prior to Stages)
vcom -2008 -work work ../rtl/core/IF_ID_Register.vhd
vcom -2008 -work work ../rtl/core/ID_EX_Register.vhd
vcom -2008 -work work ../rtl/core/EX_MEM_Register.vhd
vcom -2008 -work work ../rtl/core/MEM_WB_Register.vhd

# 4. Compile Core Pipeline Stages & Top Core
vcom -2008 -work work ../rtl/core/IF_Stage.vhd
vcom -2008 -work work ../rtl/core/ID_Stage.vhd
vcom -2008 -work work ../rtl/core/EX_Stage.vhd
vcom -2008 -work work ../rtl/core/MEM_Stage.vhd
vcom -2008 -work work ../rtl/core/CPU_FPGA.vhd

# 5. Compile Memory & Interconnect Subsystem
vcom -2008 -work work ../rtl/memory/bram_4kb.vhd
vcom -2008 -work work ../rtl/memory/bus_interconnect.vhd
vcom -2008 -work work ../rtl/memory/sdram_controller.vhd

# 6. Compile Peripherals
vcom -2008 -work work ../rtl/peripherals/uart_tx.vhd
vcom -2008 -work work ../rtl/peripherals/timer.vhd
vcom -2008 -work work ../rtl/peripherals/gpio_led.vhd
vcom -2008 -work work ../rtl/peripherals/gpio_key.vhd
vcom -2008 -work work ../rtl/peripherals/Bus_Decoder.vhd
vcom -2008 -work work ../rtl/peripherals/periph_bridge.vhd

# 7. Compile Top-Level SoC & Testbench Components
vcom -2008 -work work ../rtl/rv32im_soc.vhd
vcom -2008 -work work ./sdram_model.vhd
vcom -2008 -work work ./tb_rv32im_soc.vhd

# 8. Elaborate Simulation with Full Signal Visibility
vsim -t 1ps -voptargs="+acc" work.tb_rv32im_soc

# 9. Open GUI Wave Window and Add Signals
view wave

add wave -noupdate -divider "Clocks & Reset"
add wave -noupdate -radix binary /tb_rv32im_soc/clk
add wave -noupdate -radix binary /tb_rv32im_soc/rst_n

add wave -noupdate -divider "CPU Execution Context"
add wave -noupdate -radix hexadecimal /tb_rv32im_soc/DUT/pc
add wave -noupdate -radix hexadecimal /tb_rv32im_soc/DUT/instr
add wave -noupdate -radix binary      /tb_rv32im_soc/DUT/U_CPU/bus_stall_wire

add wave -noupdate -divider "Wishbone Master (CPU MEM Stage)"
add wave -noupdate -radix hexadecimal /tb_rv32im_soc/DUT/U_INTERCONNECT/m_adr_i
add wave -noupdate -radix hexadecimal /tb_rv32im_soc/DUT/U_INTERCONNECT/m_dat_i
add wave -noupdate -radix hexadecimal /tb_rv32im_soc/DUT/U_INTERCONNECT/m_dat_o
add wave -noupdate -radix binary      /tb_rv32im_soc/DUT/U_INTERCONNECT/m_we_i
add wave -noupdate -radix binary      /tb_rv32im_soc/DUT/U_INTERCONNECT/m_sel_i
add wave -noupdate -radix binary      /tb_rv32im_soc/DUT/U_INTERCONNECT/m_cyc_i
add wave -noupdate -radix binary      /tb_rv32im_soc/DUT/U_INTERCONNECT/m_stb_i
add wave -noupdate -radix binary      /tb_rv32im_soc/DUT/U_INTERCONNECT/m_ack_o

add wave -noupdate -divider "Wishbone Slave 1 (SDRAM)"
add wave -noupdate -radix hexadecimal /tb_rv32im_soc/DUT/U_INTERCONNECT/s1_adr_o
add wave -noupdate -radix hexadecimal /tb_rv32im_soc/DUT/U_INTERCONNECT/s1_dat_o
add wave -noupdate -radix hexadecimal /tb_rv32im_soc/DUT/U_INTERCONNECT/s1_dat_i
add wave -noupdate -radix binary      /tb_rv32im_soc/DUT/U_INTERCONNECT/s1_we_o
add wave -noupdate -radix binary      /tb_rv32im_soc/DUT/U_INTERCONNECT/s1_sel_o
add wave -noupdate -radix binary      /tb_rv32im_soc/DUT/U_INTERCONNECT/s1_cyc_o
add wave -noupdate -radix binary      /tb_rv32im_soc/DUT/U_INTERCONNECT/s1_stb_o
add wave -noupdate -radix binary      /tb_rv32im_soc/DUT/U_INTERCONNECT/s1_ack_i

add wave -noupdate -divider "SDRAM Controller Internal Registers"
add wave -noupdate                    /tb_rv32im_soc/DUT/U_SDRAM/state
add wave -noupdate -radix decimal     /tb_rv32im_soc/DUT/U_SDRAM/wait_cnt
add wave -noupdate -radix binary      /tb_rv32im_soc/DUT/U_SDRAM/refresh_req
add wave -noupdate -radix decimal     /tb_rv32im_soc/DUT/U_SDRAM/refresh_cnt
add wave -noupdate -radix hexadecimal /tb_rv32im_soc/DUT/U_SDRAM/latched_adr
add wave -noupdate -radix hexadecimal /tb_rv32im_soc/DUT/U_SDRAM/latched_wdata
add wave -noupdate -radix hexadecimal /tb_rv32im_soc/DUT/U_SDRAM/rdata_reg
add wave -noupdate -radix binary      /tb_rv32im_soc/DUT/U_SDRAM/dq_oe

add wave -noupdate -divider "Physical SDRAM Bus"
add wave -noupdate -radix binary      /tb_rv32im_soc/sdram_cke
add wave -noupdate -radix binary      /tb_rv32im_soc/sdram_cs_n
add wave -noupdate -radix binary      /tb_rv32im_soc/sdram_ras_n
add wave -noupdate -radix binary      /tb_rv32im_soc/sdram_cas_n
add wave -noupdate -radix binary      /tb_rv32im_soc/sdram_we_n
add wave -noupdate -radix hexadecimal /tb_rv32im_soc/sdram_ba
add wave -noupdate -radix hexadecimal /tb_rv32im_soc/sdram_addr
add wave -noupdate -radix binary      /tb_rv32im_soc/sdram_dqm
add wave -noupdate -radix hexadecimal /tb_rv32im_soc/sdram_dq

# 10. Open List Window & Register Signals for Text File Logging
view list

add list -radix hexadecimal /tb_rv32im_soc/DUT/pc
add list -radix hexadecimal /tb_rv32im_soc/DUT/instr
add list -radix binary      /tb_rv32im_soc/DUT/U_CPU/bus_stall_wire
add list -radix binary      /tb_rv32im_soc/DUT/U_INTERCONNECT/s1_cyc_o
add list -radix binary      /tb_rv32im_soc/DUT/U_INTERCONNECT/s1_stb_o
add list -radix binary      /tb_rv32im_soc/DUT/U_INTERCONNECT/s1_we_o
add list -radix hexadecimal /tb_rv32im_soc/DUT/U_INTERCONNECT/s1_adr_o
add list -radix hexadecimal /tb_rv32im_soc/DUT/U_INTERCONNECT/s1_dat_o
add list -radix binary      /tb_rv32im_soc/DUT/U_INTERCONNECT/s1_ack_i
add list -radix hexadecimal /tb_rv32im_soc/DUT/U_INTERCONNECT/s1_dat_i
add list                    /tb_rv32im_soc/DUT/U_SDRAM/state
add list -radix binary      /tb_rv32im_soc/sdram_cs_n
add list -radix binary      /tb_rv32im_soc/sdram_ras_n
add list -radix binary      /tb_rv32im_soc/sdram_cas_n
add list -radix binary      /tb_rv32im_soc/sdram_we_n
add list -radix hexadecimal /tb_rv32im_soc/sdram_addr
add list -radix hexadecimal /tb_rv32im_soc/sdram_dq

# 11. Run Simulation
run 50 us

# 12. Export List Buffer to File & Adjust Wave Window Zoom
write list sim_trace.txt
WaveRestoreZoom {0 ns} {50 us}