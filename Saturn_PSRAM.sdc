# Runtime Saturn RAMH PSRAM interface.
#
# The QPI PHY is clocked by clk_ram (67.7376 MHz in the normal Saturn mode).
# With HALF_DIVIDER=2, PSRAM_CLK toggles every two controller cycles and its
# full external period is therefore four controller cycles (about 16.93 MHz).
# Model the forwarded clock at the registered PSRAM_CLK Q pin, matching the
# hardware-proven standalone stress/diagnostic constraints.
create_generated_clock -name PSRAM_RUNTIME_CLK_EXT \
	-source [get_pins {*|ramh_psram|engine|phy|PSRAM_CLK|clk}] -divide_by 4 \
	[get_pins {*|ramh_psram|engine|phy|PSRAM_CLK|q}]

# Conservative board/device timing envelope inherited from the standalone
# PSRAM cores that passed on the known-good card.
set_output_delay -clock PSRAM_RUNTIME_CLK_EXT -max 2.000 \
	[get_ports {PSRAM_CE_N PSRAM_DQ[*]}]
set_output_delay -clock PSRAM_RUNTIME_CLK_EXT -min -2.000 \
	[get_ports {PSRAM_CE_N PSRAM_DQ[*]}]

set_input_delay -clock PSRAM_RUNTIME_CLK_EXT -clock_fall -max 7.000 \
	[get_ports {PSRAM_DQ[*]}]
set_input_delay -clock PSRAM_RUNTIME_CLK_EXT -clock_fall -min 1.000 \
	[get_ports {PSRAM_DQ[*]}]
