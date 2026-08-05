# Stage 58 toggles PSRAM_CLK from a register clocked at 67.7376 MHz. At the
# fastest divider=1 setting this register produces a 33.8688 MHz square wave.
# Model it as a /2 source-synchronous generated clock at the register Q. Using
# an unrelated virtual output clock would discard the common controller-clock
# path and report a false setup violation. The output-buffer delay is omitted,
# which is conservative for setup at the external PSRAM.
create_generated_clock -name PSRAM_CLK_EXT \
	-source [get_pins {*|diagnostic|bus|PSRAM_CLK|clk}] -divide_by 2 \
	[get_pins {*|diagnostic|bus|PSRAM_CLK|q}]

set_output_delay -clock PSRAM_CLK_EXT -max 2.000 \
	[get_ports {PSRAM_CE_N PSRAM_DQ[*]}]
set_output_delay -clock PSRAM_CLK_EXT -min -2.000 \
	[get_ports {PSRAM_CE_N PSRAM_DQ[*]}]

set_input_delay -clock PSRAM_CLK_EXT -clock_fall -max 7.000 \
	[get_ports {PSRAM_DQ[*]}]
set_input_delay -clock PSRAM_CLK_EXT -clock_fall -min 1.000 \
	[get_ports {PSRAM_DQ[*]}]
