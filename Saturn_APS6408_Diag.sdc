# Constrain the fastest selectable PSRAM clock (33.8688 MHz).
create_generated_clock -name APS6408_CLK_EXT \
    -source [get_pins -no_duplicates {*|diagnostic|PSRAM_CLK|clk}] -divide_by 8 \
    [get_pins -no_duplicates {*|diagnostic|PSRAM_CLK|q}]

set_output_delay -clock APS6408_CLK_EXT -max 10.000 \
    [get_ports {PSRAM_CE_N PSRAM_DQ[*] PSRAM_DQS}]
set_output_delay -clock APS6408_CLK_EXT -min -10.000 \
    [get_ports {PSRAM_CE_N PSRAM_DQ[*] PSRAM_DQS}]
set_input_delay -clock APS6408_CLK_EXT -max 35.000 \
    [get_ports {PSRAM_DQ[*] PSRAM_DQS}]
set_input_delay -clock APS6408_CLK_EXT -min 0.000 \
    [get_ports {PSRAM_DQ[*] PSRAM_DQS}]
