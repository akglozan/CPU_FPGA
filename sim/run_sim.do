# Create and clear work library
vlib work
vmap work work

# Compile Core RTL Source Files (VHDL-2008)
vcom -2008 ../rtl/core/Program_Counter.vhd
vcom -2008 ../rtl/core/Instruction_Memory.vhd
vcom -2008 ../rtl/core/IF_ID_Register.vhd
vcom -2008 ../rtl/core/RegFile.vhd
vcom -2008 ../rtl/core/ImmGen.vhd
vcom -2008 ../rtl/core/ID_EX_Register.vhd
vcom -2008 ../rtl/core/Control_Unit.vhd
vcom -2008 ../rtl/core/ALU.vhd
vcom -2008 ../rtl/core/M_Extension_Unit.vhd
vcom -2008 ../rtl/core/Hazard_Unit.vhd
vcom -2008 ../rtl/core/Forwarding_Unit.vhd
vcom -2008 ../rtl/core/EX_MEM_Register.vhd
vcom -2008 ../rtl/core/Data_Memory.vhd
vcom -2008 ../rtl/core/MEM_WB_Register.vhd
vcom -2008 ../rtl/core/IF_Stage.vhd
vcom -2008 ../rtl/core/ID_Stage.vhd
vcom -2008 ../rtl/core/EX_Stage.vhd
vcom -2008 ../rtl/core/MEM_Stage.vhd
vcom -2008 ../rtl/core/CPU_FPGA.vhd

# Compile Memory & Interconnect
vcom -2008 ../rtl/memory/bram_4kb.vhd
vcom -2008 ../rtl/memory/bus_interconnect.vhd

# Compile Peripherals & Top Level
vcom -2008 ../rtl/peripherals/uart_tx.vhd
vcom -2008 ../rtl/peripherals/gpio_led.vhd
vcom -2008 ../rtl/peripherals/gpio_key.vhd
vcom -2008 ../rtl/peripherals/timer.vhd
vcom -2008 ../rtl/rv32im_soc.vhd

# Compile Testbench
vcom -2008 tb_rv32im_soc.vhd

# Elaborate & Load Simulation (Preserve internal signal visibility for wave viewer)
vsim -t 1ns -voptargs="+acc" work.tb_rv32im_soc

# Setup VCD Logging File
vcd file sim_trace.vcd
vcd add -r /tb_rv32im_soc/*

# Open Waveform Window Interface
view wave

# Waveform Window Setup
add wave -divider "System"
add wave -hex /tb_rv32im_soc/clk
add wave -hex /tb_rv32im_soc/rst_n

add wave -divider "CPU Core Pipeline"
add wave -hex /tb_rv32im_soc/UUT/U_CPU/pc_debug
add wave -hex /tb_rv32im_soc/UUT/U_CPU/instr_debug

add wave -divider "Bus Interconnect"
add wave -hex /tb_rv32im_soc/UUT/mem_addr
add wave -hex /tb_rv32im_soc/UUT/mem_wdata
add wave -hex /tb_rv32im_soc/UUT/mem_rdata
add wave -hex /tb_rv32im_soc/UUT/mem_write

add wave -divider "Peripherals"
add wave -hex /tb_rv32im_soc/gpio_leds
add wave -hex /tb_rv32im_soc/gpio_keys
add wave -hex /tb_rv32im_soc/uart_tx

# Execute Simulation, Flush VCD Dump, and Auto-Fit Waveforms
run 2ms
vcd flush
vcd off
wave zoomfull