set aps_engine_pin [get_pins -no_duplicates {*|ramh_psram|engine|PSRAM_CLK|clk}]
set aps_clock_pin [get_pins -no_duplicates {*|ramh_psram|engine|PSRAM_CLK|q}]
set aps_master33 ""
set aps_master50 ""
foreach_in_collection aps_clock [get_clocks {*psram_speed_pll*}] {
    set aps_period [get_clock_info -period $aps_clock]
    if {$aps_period > 14.7 && $aps_period < 14.8} { set aps_master33 [get_clock_info -name $aps_clock] }
    if {$aps_period > 9.8 && $aps_period < 9.9} { set aps_master50 [get_clock_info -name $aps_clock] }
}
if {$aps_master33 == "" || $aps_master50 == ""} { error "Missing runtime control PLL clocks" }
create_generated_clock -name APS6408_CLK_EXT_33 -master_clock $aps_master33 \
    -source $aps_engine_pin -divide_by 2 $aps_clock_pin
create_generated_clock -name APS6408_CLK_EXT_50 -master_clock $aps_master50 \
    -source $aps_engine_pin -divide_by 2 -add $aps_clock_pin
set_clock_groups -logically_exclusive \
    -group [list $aps_master33 APS6408_CLK_EXT_33] \
    -group [list $aps_master50 APS6408_CLK_EXT_50]

foreach aps_external_clock {APS6408_CLK_EXT_33 APS6408_CLK_EXT_50} {
set_output_delay -clock $aps_external_clock -max 10.000 -add_delay \
    [get_ports {PSRAM_CE_N PSRAM_DQ[*] PSRAM_DQS}]
set_output_delay -clock $aps_external_clock -min -10.000 -add_delay \
    [get_ports {PSRAM_CE_N PSRAM_DQ[*] PSRAM_DQS}]
set_input_delay -clock $aps_external_clock -max 35.000 -add_delay \
    [get_ports {PSRAM_DQ[*] PSRAM_DQS}]
set_input_delay -clock $aps_external_clock -min 0.000 -add_delay \
    [get_ports {PSRAM_DQ[*] PSRAM_DQS}]
}

set_false_path -to [get_registers {*|ramh_psram|req_meta *|ramh_psram|ack_meta *|ramh_psram|init_meta *|ramh_psram|error_meta}]
# Bundled payloads remain held until the synchronized acknowledgement.
set aps_request_sources [get_registers {*|ramh_psram|source_*}]
set aps_request_targets [get_registers {*|ramh_psram|engine|runtime_* *|ramh_psram|engine|read_phase}]
set aps_response_sources [get_registers {*|ramh_psram|response_*}]
set aps_response_targets [get_registers {*|ramh_psram|cache_* *|ramh_psram|adapter_error}]
set_max_delay 9.841 -from $aps_request_sources -to $aps_request_targets
set_max_delay 14.762 -from $aps_response_sources -to $aps_response_targets
set_false_path -hold -from $aps_request_sources -to $aps_request_targets
set_false_path -hold -from $aps_response_sources -to $aps_response_targets
