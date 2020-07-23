create_clock -period 20 [get_ports FPGA_CLK1_50]
create_clock -period 20 [get_ports FPGA_CLK2_50]
create_clock -period 20 [get_ports FPGA_CLK3_50]

derive_pll_clocks

derive_clock_uncertainty

set_false_path -from [get_registers {*display_en_core*}] -to [get_registers {*display_en_sync*}]
