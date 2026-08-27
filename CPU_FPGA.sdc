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

# ------------------------------------------------------------------------------
# 5. VGA Output & Clock-Domain Crossing (Phase 4.2)
# ------------------------------------------------------------------------------
# The five VGA pins are driven directly from pix_clk-domain registers in
# vga_pixel_pipeline.vhd and go to a passive connector, not to a chip
# with setup/hold requirements, so there is no meaningful output delay to
# constrain. Left unconstrained they show up in the Unconstrained Output
# Ports report; cut them explicitly instead, the same way the LEDs and
# uart_tx already are above.
set_false_path -to [get_ports {vga_hs_pin vga_vs_pin vga_r_pin vga_g_pin vga_b_pin}]

# sys_clk (50 MHz) and pix_clk (25 MHz, vga_pll c0) come from the same
# board oscillator, so derive_pll_clocks makes TimeQuest treat them as
# related and time every path between them as if it were synchronous.
# The design does not rely on that: every signal crossing between the two
# goes through an explicit synchronizer -- rst_sync for the pix_clk-domain
# reset, the toggle-bit + captured-line_num handshake in vga_line_fetch.vhd,
# the bank synchronizer in vga_pixel_pipeline.vhd, and vga_line_buffer's /
# vga_palette's dual-clock RAM ports, which are dual-clock precisely so
# that no data path crosses combinationally. Declaring the two groups
# asynchronous stops the Fitter spending effort closing paths that are
# handled structurally, and stops a future marginal case from appearing
# to pass by luck rather than by design.
set_clock_groups -asynchronous \
    -group [get_clocks {sys_clk}] \
    -group [get_clocks {u_vga_pll|altpll_component|auto_generated|pll1|clk[0]}]
