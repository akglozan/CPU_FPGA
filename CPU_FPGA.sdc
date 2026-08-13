# Create 50 MHz clock constraint on pin 'clk' (20 ns period)
create_clock -name clk -period 20.000 [get_ports {clk}]

# Automatically derive clock uncertainty (jitter/skew)
derive_clock_uncertainty

# Cut false paths for asynchronous reset and inputs/outputs
set_false_path -from [get_ports {rst_n}]
set_false_path -from [get_ports {gpio_keys[*]}]
set_false_path -from [get_ports {uart_rx}]
set_false_path -to [get_ports {gpio_leds[*]}]
set_false_path -to [get_ports {uart_tx}]