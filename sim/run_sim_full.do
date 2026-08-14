# Recreate the ModelSim/Questa work library
if {[file exists work]} {
    vdel -lib work -all
}
vlib work
vmap work work

# Compile core RTL (VHDL-2008)
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

# Compile memory and bus interconnect
vcom -2008 ../rtl/memory/bram_4kb.vhd
vcom -2008 ../rtl/memory/bus_interconnect.vhd

# Compile peripherals and SoC top level
vcom -2008 ../rtl/peripherals/uart_tx.vhd
vcom -2008 ../rtl/peripherals/gpio_led.vhd
vcom -2008 ../rtl/peripherals/gpio_key.vhd
vcom -2008 ../rtl/peripherals/timer.vhd
vcom -2008 ../rtl/rv32im_soc.vhd

# Compile testbench
vcom -2008 tb_rv32im_soc.vhd

# Elaborate with internal signal visibility
vsim -t 1ns -voptargs="+acc" work.tb_rv32im_soc

# Log all signals for text dump
log -r /tb_rv32im_soc

# VCD logging (binary waveform file)
vcd file sim_trace.vcd
vcd add -r /tb_rv32im_soc/*
vcd add -r /tb_rv32im_soc/UUT/*
vcd add -r /tb_rv32im_soc/UUT/U_UART/*

# Waveform setup
view wave

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

add wave -divider "UART Interface"
add wave -hex /tb_rv32im_soc/uart_tx
add wave -hex /tb_rv32im_soc/UUT/uart_tx_start
add wave -hex /tb_rv32im_soc/UUT/uart_tx_busy
add wave -hex /tb_rv32im_soc/UUT/uart_rdata
add wave -hex /tb_rv32im_soc/UUT/U_UART/tx_data
add wave -hex /tb_rv32im_soc/UUT/U_UART/tx_start
add wave -hex /tb_rv32im_soc/UUT/U_UART/tx_busy
add wave -hex /tb_rv32im_soc/UUT/U_UART/tx_out
add wave -hex /tb_rv32im_soc/UUT/U_UART/tx_shift
add wave -unsigned /tb_rv32im_soc/UUT/U_UART/clk_count
add wave -hex /tb_rv32im_soc/UUT/U_UART/state

add wave -divider "GPIO"
add wave -hex /tb_rv32im_soc/gpio_leds
add wave -hex /tb_rv32im_soc/gpio_keys

# Run long enough for the complete firmware banner and diagnostics
run 15ms

# Flush and close VCD
vcd flush
vcd off

# Export full time-history waveform log to text file
dump -o sim_trace.txt

# Auto-fit waveform window
wave zoomfull