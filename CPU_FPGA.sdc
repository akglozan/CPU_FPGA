# ==============================================================================
# Synopsys Design Constraints (SDC) for CPU_FPGA (Top Entity: rv32im_soc)
# Target Frequency: 50 MHz (Period = 20.000 ns)
# ==============================================================================

# ------------------------------------------------------------------------------
# 1. Primary Clock Definition & Clock Derivation
# ------------------------------------------------------------------------------
create_clock -name sys_clk -period 20.000 [get_ports {clk}]

# Automatically derive PLL generated clocks and device jitter uncertainties
derive_pll_clocks
derive_clock_uncertainty

# ------------------------------------------------------------------------------
# 2. Asynchronous Reset & Board-Level I/O (False Paths)
# ------------------------------------------------------------------------------
# Active-low global asynchronous reset
set_false_path -from [get_ports {rst_n}]

# Slow board-level inputs (tactile switches/buttons)
set_false_path -from [get_ports {gpio_keys[*]}]

# Slow board-level outputs (user LEDs)
set_false_path -to [get_ports {gpio_leds[*]}]

# ------------------------------------------------------------------------------
# 3. Asynchronous Peripheral Interfaces (UART)
# ------------------------------------------------------------------------------
# Asynchronous serial receiver input
set_false_path -from [get_ports {uart_rx}]

# Asynchronous serial transmitter output
set_false_path -to [get_ports {uart_tx}]

# ------------------------------------------------------------------------------
# 4. Synchronous External SDRAM Interface Constraints
# ------------------------------------------------------------------------------
# Output Control, Address, Bank Select, and DQM lines (FPGA -> SDRAM)
set_output_delay -clock sys_clk -max 3.000 [get_ports {sdram_cke sdram_cs_n sdram_ras_n sdram_cas_n sdram_we_n sdram_ba[*] sdram_addr[*] sdram_dqm[*]}]
set_output_delay -clock sys_clk -min -1.500 [get_ports {sdram_cke sdram_cs_n sdram_ras_n sdram_cas_n sdram_we_n sdram_ba[*] sdram_addr[*] sdram_dqm[*]}]

# SDRAM Bidirectional Data Bus (Write Path: FPGA -> SDRAM)
set_output_delay -clock sys_clk -max 3.000 [get_ports {sdram_dq[*]}]
set_output_delay -clock sys_clk -min -1.500 [get_ports {sdram_dq[*]}]

# SDRAM Bidirectional Data Bus (Read Path: SDRAM -> FPGA)
set_input_delay -clock sys_clk -max 5.500 [get_ports {sdram_dq[*]}]
set_input_delay -clock sys_clk -min 2.000 [get_ports {sdram_dq[*]}]