# The runtime engine uses clk_67 and HALF_DIVIDER=2. PSRAM_CLK changes every
# two controller cycles, so the external source-synchronous clock is clk/4.
create_generated_clock -name PSRAM_STRESS_CLK_EXT \
	-source [get_pins {*|stress|adapter|engine|phy|PSRAM_CLK|clk}] -divide_by 4 \
	[get_pins {*|stress|adapter|engine|phy|PSRAM_CLK|q}]

# Conservative board/device values inherited from the hardware-proven Stage
# 58 diagnostic: up to 7 ns memory clock-to-output and 2 ns output path.
set_output_delay -clock PSRAM_STRESS_CLK_EXT -max 2.000 \
	[get_ports {PSRAM_CE_N PSRAM_DQ[*]}]
set_output_delay -clock PSRAM_STRESS_CLK_EXT -min -2.000 \
	[get_ports {PSRAM_CE_N PSRAM_DQ[*]}]

set_input_delay -clock PSRAM_STRESS_CLK_EXT -clock_fall -max 7.000 \
	[get_ports {PSRAM_DQ[*]}]
set_input_delay -clock PSRAM_STRESS_CLK_EXT -clock_fall -min 1.000 \
	[get_ports {PSRAM_DQ[*]}]
