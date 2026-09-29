# The 67.7376 MHz fabric clock toggles the diagnostic PSRAM clock every
# eight cycles. This revision only targets 4.2336 MHz board bring-up.
create_generated_clock -name APS6408_CLK_EXT \
    -source [get_pins -no_duplicates {*|diagnostic|PSRAM_CLK|clk}] -divide_by 16 \
    [get_pins -no_duplicates {*|diagnostic|PSRAM_CLK|q}]

set_output_delay -clock APS6408_CLK_EXT -max 10.000 \
    [get_ports {PSRAM_CE_N PSRAM_DQ[*] PSRAM_DQS}]
set_output_delay -clock APS6408_CLK_EXT -min -10.000 \
    [get_ports {PSRAM_CE_N PSRAM_DQ[*] PSRAM_DQS}]
set_input_delay -clock APS6408_CLK_EXT -max 35.000 \
    [get_ports {PSRAM_DQ[*] PSRAM_DQS}]
set_input_delay -clock APS6408_CLK_EXT -min 0.000 \
    [get_ports {PSRAM_DQ[*] PSRAM_DQS}]
