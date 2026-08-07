# Runtime Saturn RAMH PSRAM interface.
#
# The QPI PHY is clocked by clk_ram (about 114.56 MHz in the fitted Saturn
# revision). With HALF_DIVIDER=2, PSRAM_CLK toggles every two controller cycles
# and its full external period is therefore four controller cycles (about
# 28.64 MHz).
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

# The PSRAM changes each QPI nibble after an external falling edge. The PHY
# intentionally samples DQ on every clk_ram edge, but P_READ consumes the last
# dq_sample value immediately before the following QPI falling edge. With
# HALF_DIVIDER=2 that functional sample is the third clk_ram edge after the
# external launch edge. Earlier samples are overwritten and never reach
# read_data. Express that protocol relationship explicitly instead of timing
# the first, intentionally disposable sample as a one-cycle transfer.
set psram_dq_sample_regs \
	[get_registers {*|ramh_psram|engine|phy|dq_sample*}]
set_multicycle_path -setup -end 3 \
	-from [get_ports {PSRAM_DQ[*]}] -to $psram_dq_sample_regs
set_multicycle_path -hold -end 2 \
	-from [get_ports {PSRAM_DQ[*]}] -to $psram_dq_sample_regs
