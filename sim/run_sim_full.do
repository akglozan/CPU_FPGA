# 2. Add Wave Window Signals
# Clocks & Reset
add wave -noupdate -divider "Clocks & Reset"
add wave -noupdate /tb_rv32im_soc/clk
add wave -noupdate /tb_rv32im_soc/rst_n

# CPU Core Execution & Pipeline Signals
add wave -noupdate -divider "CPU Execution"
add wave -noupdate -radix hex /tb_rv32im_soc/DUT/U_CPU/pc_debug
add wave -noupdate -radix hex /tb_rv32im_soc/DUT/instr
add wave -noupdate            /tb_rv32im_soc/DUT/U_CPU/bus_stall_wire

# Wishbone Master Bus (CPU MEM Stage)
add wave -noupdate -divider "Wishbone Master Bus"
add wave -noupdate -radix hex /tb_rv32im_soc/DUT/wb_cpu_adr
add wave -noupdate -radix hex /tb_rv32im_soc/DUT/wb_cpu_wdat
add wave -noupdate -radix hex /tb_rv32im_soc/DUT/wb_cpu_rdat
add wave -noupdate -radix bin /tb_rv32im_soc/DUT/wb_cpu_sel
add wave -noupdate            /tb_rv32im_soc/DUT/wb_cpu_we
add wave -noupdate            /tb_rv32im_soc/DUT/wb_cpu_cyc
add wave -noupdate            /tb_rv32im_soc/DUT/wb_cpu_stb
add wave -noupdate            /tb_rv32im_soc/DUT/wb_cpu_ack

# Bus Interconnect Slave Strobes
add wave -noupdate -divider "Interconnect Slaves"
add wave -noupdate            /tb_rv32im_soc/DUT/s0_stb
add wave -noupdate            /tb_rv32im_soc/DUT/s0_ack
add wave -noupdate            /tb_rv32im_soc/DUT/s1_stb
add wave -noupdate            /tb_rv32im_soc/DUT/s1_ack
add wave -noupdate            /tb_rv32im_soc/DUT/s3_stb
add wave -noupdate            /tb_rv32im_soc/DUT/s3_ack

# SDRAM Controller Internal State
add wave -noupdate -divider "SDRAM Controller Internal"
add wave -noupdate            /tb_rv32im_soc/DUT/U_SDRAM/state
add wave -noupdate -radix dec /tb_rv32im_soc/DUT/U_SDRAM/wait_cnt
add wave -noupdate            /tb_rv32im_soc/DUT/U_SDRAM/refresh_req

# External SDRAM Interface Pins
add wave -noupdate -divider "Physical SDRAM Pins"
add wave -noupdate            /tb_rv32im_soc/sdram_cke
add wave -noupdate            /tb_rv32im_soc/sdram_cs_n
add wave -noupdate            /tb_rv32im_soc/sdram_ras_n
add wave -noupdate            /tb_rv32im_soc/sdram_cas_n
add wave -noupdate            /tb_rv32im_soc/sdram_we_n
add wave -noupdate -radix hex /tb_rv32im_soc/sdram_ba
add wave -noupdate -radix hex /tb_rv32im_soc/sdram_addr
add wave -noupdate -radix bin /tb_rv32im_soc/sdram_dqm
add wave -noupdate -radix hex /tb_rv32im_soc/sdram_dq

# Peripherals & I/O
add wave -noupdate -divider "Peripherals & I/O"
add wave -noupdate            /tb_rv32im_soc/uart_tx
add wave -noupdate -radix hex /tb_rv32im_soc/gpio_leds