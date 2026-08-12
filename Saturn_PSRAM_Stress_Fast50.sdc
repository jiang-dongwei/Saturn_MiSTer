# 101.6064 MHz controller toggles the registered external clock every cycle.
create_generated_clock -name PSRAM_FAST50_CLK_EXT \
	-source [get_pins {*|stress|adapter|engine|PSRAM_CLK|clk}] -divide_by 2 \
	[get_pins {*|stress|adapter|engine|PSRAM_CLK|q}]

set_output_delay -clock PSRAM_FAST50_CLK_EXT -max 2.000 \
	[get_ports {PSRAM_CE_N PSRAM_DQ[*]}]
set_output_delay -clock PSRAM_FAST50_CLK_EXT -min -2.000 \
	[get_ports {PSRAM_CE_N PSRAM_DQ[*]}]
set_input_delay -clock PSRAM_FAST50_CLK_EXT -clock_fall -max 7.000 \
	[get_ports {PSRAM_DQ[*]}]
set_input_delay -clock PSRAM_FAST50_CLK_EXT -clock_fall -min 1.000 \
	[get_ports {PSRAM_DQ[*]}]
