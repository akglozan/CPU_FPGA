# ============================================================================
# ModelSim/Questa Compilation and Simulation Script for Phase 2
# Target: rv32im_soc and SDRAM Controller Verification
# ============================================================================

# 1. Resolve Project Root Directory
set SCRIPT_DIR [file dirname [file normalize [info script]]]
set PROJ_ROOT [file normalize "$SCRIPT_DIR/.."]

echo "Project Root set to: $PROJ_ROOT"

# 2. Create and map working library in current simulation folder
vlib work
vmap work work

# 3. Compile Core CPU Pipeline (Dependency Order)
echo "Compiling Core CPU..."
vcom -2008 "$PROJ_ROOT/rtl/core/Program_Counter.vhd"
vcom -2008 "$PROJ_ROOT/rtl/core/IF_ID_Register.vhd"
vcom -2008 "$PROJ_ROOT/rtl/core/IF_Stage.vhd"
vcom -2008 "$PROJ_ROOT/rtl/core/RegFile.vhd"
vcom -2008 "$PROJ_ROOT/rtl/core/Control_Unit.vhd"
vcom -2008 "$PROJ_ROOT/rtl/core/ImmGen.vhd"
vcom -2008 "$PROJ_ROOT/rtl/core/ID_EX_Register.vhd"
vcom -2008 "$PROJ_ROOT/rtl/core/ID_Stage.vhd"
vcom -2008 "$PROJ_ROOT/rtl/core/ALU.vhd"
vcom -2008 "$PROJ_ROOT/rtl/core/M_Extension_Unit.vhd"
vcom -2008 "$PROJ_ROOT/rtl/core/Forwarding_Unit.vhd"
vcom -2008 "$PROJ_ROOT/rtl/core/EX_MEM_Register.vhd"
vcom -2008 "$PROJ_ROOT/rtl/core/EX_Stage.vhd"
vcom -2008 "$PROJ_ROOT/rtl/core/MEM_WB_Register.vhd"
vcom -2008 "$PROJ_ROOT/rtl/core/MEM_Stage.vhd"
vcom -2008 "$PROJ_ROOT/rtl/core/Hazard_Unit.vhd"
vcom -2008 "$PROJ_ROOT/rtl/core/CPU_FPGA.vhd"

# 4. Compile Memory Subsystem & Interconnect
echo "Compiling Memory Hierarchy..."
vcom -2008 "$PROJ_ROOT/rtl/memory/bram_4kb.vhd"
vcom -2008 "$PROJ_ROOT/rtl/memory/bus_interconnect.vhd"
vcom -2008 "$PROJ_ROOT/rtl/memory/sdram_controller.vhd"

# 5. Compile Peripherals
echo "Compiling Peripherals..."
vcom -2008 "$PROJ_ROOT/rtl/peripherals/uart_tx.vhd"
vcom -2008 "$PROJ_ROOT/rtl/peripherals/gpio_led.vhd"
vcom -2008 "$PROJ_ROOT/rtl/peripherals/gpio_key.vhd"
vcom -2008 "$PROJ_ROOT/rtl/peripherals/timer.vhd"
vcom -2008 "$PROJ_ROOT/rtl/peripherals/periph_bridge.vhd"

# 6. Compile Top-Level SoC & Simulation Models
echo "Compiling SoC Top-Level and Testbench..."
vcom -2008 "$PROJ_ROOT/rtl/rv32im_soc.vhd"
vcom -2008 "$PROJ_ROOT/sim/sdram_model.vhd"
vcom -2008 "$PROJ_ROOT/sim/tb_rv32im_soc.vhd"

# 7. Initialize Simulation (Optimize for full visibility)
echo "Loading Simulation..."
vsim -voptargs="+acc" work.tb_rv32im_soc

# ============================================================================
# Waveform Configuration
# ============================================================================
onerror {resume}
quietly WaveActivateNextPane {} 0

# --- System Clocks & Reset ---
add wave -noupdate -divider "Clocks & Reset"
add wave -noupdate /tb_rv32im_soc/clk
add wave -noupdate /tb_rv32im_soc/rst_n

# --- CPU Context ---
add wave -noupdate -divider "CPU Execution Context"
add wave -noupdate -radix hexadecimal /tb_rv32im_soc/DUT/pc
add wave -noupdate -radix hexadecimal /tb_rv32im_soc/DUT/instr
add wave -noupdate /tb_rv32im_soc/DUT/U_CPU/bus_stall_wire

# --- Wishbone Interconnect (CPU -> SDRAM) ---
add wave -noupdate -divider "Wishbone B4 Bus (SDRAM Slave 1)"
add wave -noupdate /tb_rv32im_soc/DUT/U_INTERCONNECT/s1_cyc_o
add wave -noupdate /tb_rv32im_soc/DUT/U_INTERCONNECT/s1_stb_o
add wave -noupdate /tb_rv32im_soc/DUT/U_INTERCONNECT/s1_we_o
add wave -noupdate -radix hexadecimal /tb_rv32im_soc/DUT/U_INTERCONNECT/s1_adr_o
add wave -noupdate -radix hexadecimal /tb_rv32im_soc/DUT/U_INTERCONNECT/s1_dat_o
add wave -noupdate -radix binary      /tb_rv32im_soc/DUT/U_INTERCONNECT/s1_sel_o
add wave -noupdate /tb_rv32im_soc/DUT/U_INTERCONNECT/s1_ack_i
add wave -noupdate -radix hexadecimal /tb_rv32im_soc/DUT/U_INTERCONNECT/s1_dat_i

# --- SDRAM Controller FSM ---
add wave -noupdate -divider "SDRAM Controller FSM"
add wave -noupdate /tb_rv32im_soc/DUT/U_SDRAM/state
add wave -noupdate -radix unsigned /tb_rv32im_soc/DUT/U_SDRAM/wait_cnt
add wave -noupdate /tb_rv32im_soc/DUT/U_SDRAM/refresh_req
add wave -noupdate -radix unsigned /tb_rv32im_soc/DUT/U_SDRAM/refresh_cnt

# --- Physical SDRAM Interface ---
add wave -noupdate -divider "Physical SDRAM Pins"
add wave -noupdate /tb_rv32im_soc/sdram_cke
add wave -noupdate /tb_rv32im_soc/sdram_cs_n
add wave -noupdate /tb_rv32im_soc/sdram_ras_n
add wave -noupdate /tb_rv32im_soc/sdram_cas_n
add wave -noupdate /tb_rv32im_soc/sdram_we_n
add wave -noupdate -radix binary /tb_rv32im_soc/sdram_ba
add wave -noupdate -radix hexadecimal /tb_rv32im_soc/sdram_addr
add wave -noupdate -radix binary /tb_rv32im_soc/sdram_dqm
add wave -noupdate -radix hexadecimal /tb_rv32im_soc/sdram_dq
add wave -noupdate /tb_rv32im_soc/DUT/U_SDRAM/dq_oe

# --- SDRAM Model Internals (Verification) ---
add wave -noupdate -divider "SDRAM Sim Model Pipeline"
add wave -noupdate -radix binary /tb_rv32im_soc/U_SDRAM_CHIP/read_pipeline_valid
add wave -noupdate -radix binary /tb_rv32im_soc/U_SDRAM_CHIP/bank_active
add wave -noupdate -radix hexadecimal /tb_rv32im_soc/U_SDRAM_CHIP/active_row

# Formatting layout
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {0 ns} 0}
configure wave -namecolwidth 350
configure wave -valuecolwidth 150
configure wave -justifyvalue left
configure wave -signalnamewidth 1
configure wave -snapdistance 10
configure wave -datasetprefix 0
configure wave -rowmargin 4
configure wave -childrowmargin 2
configure wave -gridoffset 0
configure wave -gridperiod 1
configure wave -griddelta 40
configure wave -timeline 0
configure wave -timelineunits ns
update

# ============================================================================
# Text Trace / Log Setup (write list)
# ============================================================================
# Clear any pre-existing list signals
delete list -all

# Add key signals to the list window logger
add list -radix hex /tb_rv32im_soc/DUT/pc
add list -radix hex /tb_rv32im_soc/DUT/instr
add list           /tb_rv32im_soc/DUT/U_CPU/bus_stall_wire
add list           /tb_rv32im_soc/DUT/U_INTERCONNECT/s1_cyc_o
add list           /tb_rv32im_soc/DUT/U_INTERCONNECT/s1_stb_o
add list           /tb_rv32im_soc/DUT/U_INTERCONNECT/s1_we_o
add list -radix hex /tb_rv32im_soc/DUT/U_INTERCONNECT/s1_adr_o
add list -radix hex /tb_rv32im_soc/DUT/U_INTERCONNECT/s1_dat_o
add list           /tb_rv32im_soc/DUT/U_INTERCONNECT/s1_ack_i
add list -radix hex /tb_rv32im_soc/DUT/U_INTERCONNECT/s1_dat_i
add list           /tb_rv32im_soc/DUT/U_SDRAM/state
add list           /tb_rv32im_soc/sdram_cs_n
add list           /tb_rv32im_soc/sdram_ras_n
add list           /tb_rv32im_soc/sdram_cas_n
add list           /tb_rv32im_soc/sdram_we_n
add list -radix hex /tb_rv32im_soc/sdram_addr
add list -radix hex /tb_rv32im_soc/sdram_dq

# ============================================================================
# Execution & Trace Export
# ============================================================================
echo "Running simulation for 200 us to clear SDRAM init sequence..."
run 200 us
wave zoom full

# Export list log to sim_trace.txt
set TRACE_FILE "$PROJ_ROOT/sim/sim_trace.txt"
echo "Exporting waveform trace to $TRACE_FILE..."
write list -tabular "$TRACE_FILE"
echo "Trace log written successfully."