# External 50.8032 MHz QPI clock. Use a virtual board-interface clock here:
# Quartus may absorb/rename the internal PSRAM_CLK register during fitting,
# while the top-level I/O timing requirement must remain stable.
create_clock -name PSRAM_FAST50_CLK_EXT -period 19.683 [get_ports {PSRAM_CLK}]

set_output_delay -clock PSRAM_FAST50_CLK_EXT -max 2.000 \
	[get_ports {PSRAM_CE_N PSRAM_DQ[*]}]
set_output_delay -clock PSRAM_FAST50_CLK_EXT -min -2.000 \
	[get_ports {PSRAM_CE_N PSRAM_DQ[*]}]
set_input_delay -clock PSRAM_FAST50_CLK_EXT -clock_fall -max 7.000 \
	[get_ports {PSRAM_DQ[*]}]
set_input_delay -clock PSRAM_FAST50_CLK_EXT -clock_fall -min 1.000 \
	[get_ports {PSRAM_DQ[*]}]
