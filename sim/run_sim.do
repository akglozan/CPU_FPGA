# ================================================================
# RV32IM SoC UART-focused ModelSim/Questa simulation
# Output:
#   sim_trace.vcd  - fast, standard waveform trace
#
# This script intentionally does NOT create sim_trace.txt.
# This Questa/ModelSim installation has no unambiguous waveform
# 'dump' command, and Tcl sampling loops make simulation very slow.
# Convert sim_trace.vcd to text outside the simulator if needed.
# ================================================================

# Create a fresh work library
if {[file exists work]} {
    vdel -lib work -all
}
vlib work
vmap work work

# ================================================================
# Compile core RTL source files (VHDL-2008)
# ================================================================
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

# ================================================================
# Compile memory and bus interconnect RTL
# ================================================================
vcom -2008 ../rtl/memory/bram_4kb.vhd
vcom -2008 ../rtl/memory/bus_interconnect.vhd

# ================================================================
# Compile peripherals and SoC top level
# ================================================================
vcom -2008 ../rtl/peripherals/uart_tx.vhd
vcom -2008 ../rtl/peripherals/gpio_led.vhd
vcom -2008 ../rtl/peripherals/gpio_key.vhd
vcom -2008 ../rtl/peripherals/timer.vhd
vcom -2008 ../rtl/rv32im_soc.vhd

# ================================================================
# Compile SoC testbench
# ================================================================
vcom -2008 tb_rv32im_soc.vhd

# Elaborate with access to internal signals
vsim -t 1ns -voptargs="+acc" work.tb_rv32im_soc

# ================================================================
# Fast VCD logging: UART and CPU bus transaction path only
# ================================================================
vcd file sim_trace.vcd

# System signals
vcd add /tb_rv32im_soc/clk
vcd add /tb_rv32im_soc/rst_n

# CPU <-> SoC bus signals
vcd add /tb_rv32im_soc/UUT/mem_addr
vcd add /tb_rv32im_soc/UUT/mem_wdata
vcd add /tb_rv32im_soc/UUT/mem_rdata
vcd add /tb_rv32im_soc/UUT/mem_write

# UART SoC integration signals
vcd add /tb_rv32im_soc/uart_tx
vcd add /tb_rv32im_soc/UUT/uart_tx_start
vcd add /tb_rv32im_soc/UUT/uart_tx_busy
vcd add /tb_rv32im_soc/UUT/uart_rdata

# UART transmitter internals
vcd add /tb_rv32im_soc/UUT/U_UART/tx_data
vcd add /tb_rv32im_soc/UUT/U_UART/tx_start
vcd add /tb_rv32im_soc/UUT/U_UART/tx_busy
vcd add /tb_rv32im_soc/UUT/U_UART/tx_out
vcd add /tb_rv32im_soc/UUT/U_UART/tx_shift
vcd add /tb_rv32im_soc/UUT/U_UART/clk_count
vcd add /tb_rv32im_soc/UUT/U_UART/state

# ================================================================
# Wave window configuration
# ================================================================
view wave

add wave -divider "System"
add wave -hex /tb_rv32im_soc/clk
add wave -hex /tb_rv32im_soc/rst_n

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

# ================================================================
# UART-focused run
# 2 ms captures about 23 complete 8-N-1 frames at 115200 baud.
# ================================================================
run 2ms

# Finalize VCD output
vcd flush
vcd off
wave zoomfull