create_generated_clock -name APS6408_CLK_EXT \
    -source [get_pins -no_duplicates {*|ramh_psram|engine|PSRAM_CLK|clk}] -divide_by 2 \
    [get_pins -no_duplicates {*|ramh_psram|engine|PSRAM_CLK|q}]

set_output_delay -clock APS6408_CLK_EXT -max 10.000 \
    [get_ports {PSRAM_CE_N PSRAM_DQ[*] PSRAM_DQS}]
set_output_delay -clock APS6408_CLK_EXT -min -10.000 \
    [get_ports {PSRAM_CE_N PSRAM_DQ[*] PSRAM_DQS}]
set_input_delay -clock APS6408_CLK_EXT -max 35.000 \
    [get_ports {PSRAM_DQ[*] PSRAM_DQS}]
set_input_delay -clock APS6408_CLK_EXT -min 0.000 \
    [get_ports {PSRAM_DQ[*] PSRAM_DQS}]

set_false_path -to [get_registers {*|ramh_psram|req_meta *|ramh_psram|ack_meta *|ramh_psram|init_meta *|ramh_psram|error_meta}]
# Bundled payloads remain held until the synchronized acknowledgement.
set_max_delay -datapath_only 14.762 -from [get_registers {*|ramh_psram|source_*}] -to [get_registers {*|ramh_psram|engine|runtime_*}]
set_max_delay -datapath_only 14.762 -from [get_registers {*|ramh_psram|response_*}] -to [get_registers {*|ramh_psram|cache_* *|ramh_psram|adapter_error}]
