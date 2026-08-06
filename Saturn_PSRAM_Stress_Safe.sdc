# The safe diagnostic variant uses clk_67 and HALF_DIVIDER=4. PSRAM_CLK
# changes every four controller cycles, so the external clock is clk/8.
create_generated_clock -name PSRAM_STRESS_CLK_EXT \
	-source [get_pins {*|stress|adapter|engine|phy|PSRAM_CLK|clk}] -divide_by 8 \
	[get_pins {*|stress|adapter|engine|phy|PSRAM_CLK|q}]

set_output_delay -clock PSRAM_STRESS_CLK_EXT -max 2.000 \
	[get_ports {PSRAM_CE_N PSRAM_DQ[*]}]
set_output_delay -clock PSRAM_STRESS_CLK_EXT -min -2.000 \
	[get_ports {PSRAM_CE_N PSRAM_DQ[*]}]

set_input_delay -clock PSRAM_STRESS_CLK_EXT -clock_fall -max 7.000 \
	[get_ports {PSRAM_DQ[*]}]
set_input_delay -clock PSRAM_STRESS_CLK_EXT -clock_fall -min 1.000 \
	[get_ports {PSRAM_DQ[*]}]
