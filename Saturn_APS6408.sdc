set aps_engine_pin [get_pins -no_duplicates {*|ramh_psram|engine|PSRAM_CLK|clk}]
set aps_clock_pin [get_pins -no_duplicates {*|ramh_psram|engine|PSRAM_CLK|q}]
set aps_mux_net [get_nets -no_duplicates {*|psram_clock_control|auto_generated|outclk}]
if {[get_collection_size $aps_mux_net] != 1} { error "Missing unique APS6408 runtime clock mux" }
set aps_master33 ""
set aps_master50 ""
foreach_in_collection aps_clock [get_clocks {*psram_speed_pll*}] {
    set aps_period [get_clock_info -period $aps_clock]
    if {$aps_period > 14.7 && $aps_period < 14.8} { set aps_master33 [get_clock_info -name $aps_clock] }
    if {$aps_period > 9.8 && $aps_period < 9.9} { set aps_master50 [get_clock_info -name $aps_clock] }
}
if {$aps_master33 == "" || $aps_master50 == ""} { error "Missing runtime control PLL clocks" }
# The engine stays reset while the bootstrap input or clock selection is changing.
foreach aps_profile {33 50} {
    set aps_master [set aps_master$aps_profile]
    set aps_source ""
    foreach_in_collection aps_master_clock [get_clocks $aps_master] {
        set aps_source [get_clock_info -targets $aps_master_clock]
    }
    if {[get_collection_size $aps_source] != 1} { error "Missing unique runtime PLL source" }
    if {$aps_profile == 33} {
        create_generated_clock -name APS6408_ENGINE_33 -master_clock $aps_master \
            -source $aps_source -divide_by 1 $aps_mux_net
    } else {
        create_generated_clock -name APS6408_ENGINE_50 -master_clock $aps_master \
            -source $aps_source -divide_by 1 -add $aps_mux_net
    }
}
create_generated_clock -name APS6408_CLK_EXT_33 -master_clock APS6408_ENGINE_33 \
    -source $aps_engine_pin -divide_by 2 $aps_clock_pin
create_generated_clock -name APS6408_CLK_EXT_50 -master_clock APS6408_ENGINE_50 \
    -source $aps_engine_pin -divide_by 2 -add $aps_clock_pin
set_clock_groups -logically_exclusive \
    -group [list $aps_master33 APS6408_ENGINE_33 APS6408_CLK_EXT_33] \
    -group [list $aps_master50 APS6408_ENGINE_50 APS6408_CLK_EXT_50]

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
# Only the first stage of each held-level synchronizer accepts metastability.
foreach aps_sync_name {rx_done_meta rx_clock_done_meta rx|arm_meta} {
    set aps_sync_first [get_registers [format {*|ramh_psram|engine|%s} $aps_sync_name]]
    if {[get_collection_size $aps_sync_first] == 0} { error "Missing receive synchronizer: $aps_sync_name" }
    set_false_path -to $aps_sync_first
}
# Transaction speed is registered before CA and held throughout the armed read.
set aps_rx_speed_sources [get_registers {*|ramh_psram|engine|rx_speed_hold[*]}]
set aps_rx_speed_targets [get_registers {*|ramh_psram|engine|rx|active_speed[*]}]
if {[get_collection_size [get_registers -no_duplicates {*|ramh_psram|engine|rx_speed_hold[*]}]] != 2 ||
    [get_collection_size [get_registers -no_duplicates {*|ramh_psram|engine|rx|active_speed[*]}]] != 2} {
    error "Expected two held receive speed bits and two armed captures"
}
set_max_delay 7.381 -from $aps_rx_speed_sources -to $aps_rx_speed_targets
set_false_path -hold -from $aps_rx_speed_sources -to $aps_rx_speed_targets
set aps_mode_sources [get_registers {*|psram_clock_mode[*]}]
set aps_mode_targets [get_registers {*|ramh_psram|engine_speed[*]}]
set aps_mode_source_bits [get_registers -no_duplicates {*|psram_clock_mode[*]}]
set aps_mode_target_bits [get_registers -no_duplicates {*|ramh_psram|engine_speed[*]}]
if {[get_collection_size $aps_mode_source_bits] != 2 || [get_collection_size $aps_mode_target_bits] != 2} {
    error "Expected two held mode bits and two engine mode captures"
}
post_message -type info "APS6408 mode endpoints: logical [get_collection_size $aps_mode_source_bits]/[get_collection_size $aps_mode_target_bits], physical [get_collection_size $aps_mode_sources]/[get_collection_size $aps_mode_targets]"
set_max_delay 9.841 -from $aps_mode_sources -to $aps_mode_targets
set_false_path -hold -from $aps_mode_sources -to $aps_mode_targets
# Bundled payloads remain held until the synchronized acknowledgement.
set aps_request_sources [get_registers {*|ramh_psram|source_addr* *|ramh_psram|source_data* *|ramh_psram|source_mask* *|ramh_psram|source_write}]
set aps_control_targets [get_registers {*|ramh_psram|engine_request_*}]
if {[get_collection_size $aps_control_targets] != 5} { error "Expected all five request control capture registers" }
set aps_address_targets [get_registers {*|ramh_psram|engine|runtime_address*}]
set aps_data_targets [get_registers {*|ramh_psram|engine|runtime_data*}]
if {[get_collection_size $aps_address_targets] < 18 || [get_collection_size $aps_address_targets] > 19} {
    error "Missing runtime address capture registers"
}
if {[get_collection_size $aps_data_targets] != 16} { error "Expected 16 runtime data capture registers" }
set aps_request_targets [get_registers {*|ramh_psram|engine_request_* *|ramh_psram|engine|runtime_address* *|ramh_psram|engine|runtime_data*}]
set aps_response_sources [get_registers {*|ramh_psram|response_*}]
set aps_response_targets [get_registers {*|ramh_psram|cache_* *|ramh_psram|adapter_error}]
foreach aps_endpoint_set {aps_request_sources aps_request_targets aps_response_sources aps_response_targets} {
    if {[get_collection_size [set $aps_endpoint_set]] == 0} { error "Missing bundled CDC endpoints: $aps_endpoint_set" }
}
set_max_delay 9.841 -from $aps_request_sources -to $aps_request_targets
set_max_delay 14.762 -from $aps_response_sources -to $aps_response_targets
set_false_path -hold -from $aps_request_sources -to $aps_request_targets
set_false_path -hold -from $aps_response_sources -to $aps_response_targets

# Tighten only full-cycle DDIO outputs; retain native half-cycle and hold checks.
set aps_ddio_sources [get_registers {*|ramh_psram|engine|rx|input_capture|input_ddr|*|dataout_h[*] *|ramh_psram|engine|rx|input_capture|input_ddr|*|dataout_l[*]}]
set aps_ddio_targets [get_registers {*|ramh_psram|engine|rx|pair_low[*] *|ramh_psram|engine|rx|pair_high[*] *|ramh_psram|engine|rx|data_high[*]}]
set aps_ddio_source_bits [get_registers -no_duplicates {*|ramh_psram|engine|rx|input_capture|input_ddr|*|dataout_h[*] *|ramh_psram|engine|rx|input_capture|input_ddr|*|dataout_l[*]}]
set aps_ddio_target_bits [get_registers -no_duplicates {*|ramh_psram|engine|rx|pair_low[*] *|ramh_psram|engine|rx|pair_high[*] *|ramh_psram|engine|rx|data_high[*]}]
if {[get_collection_size $aps_ddio_source_bits] != 18 || [get_collection_size $aps_ddio_target_bits] != 50} {
    error "Missing DDIO route-budget endpoints: expected 18 outputs and 50 capture bits"
}
post_message -type info "APS6408 DDIO route endpoints: logical [get_collection_size $aps_ddio_source_bits]/[get_collection_size $aps_ddio_target_bits], physical [get_collection_size $aps_ddio_sources]/[get_collection_size $aps_ddio_targets]"
if {![info exists aps_report_natural_ddio] || !$aps_report_natural_ddio} {
    set_max_delay 5.000 -from $aps_ddio_sources -to $aps_ddio_targets
    post_message -type info "APS6408 DDIO route budget: 5.000 ns; native hold checks retained"
} else {
    post_message -type info "APS6408 DDIO analysis: native clock setup and hold requirements"
}

# Completed receive words stay held until the synchronized completion is consumed.
set aps_receive_sources [get_registers {*|ramh_psram|engine|rx|early_word[*] *|ramh_psram|engine|rx|mid_word[*] *|ramh_psram|engine|rx|center_word[*] *|ramh_psram|engine|rx|late_word[*] *|ramh_psram|engine|rx|clock_word[*]}]
set aps_receive_targets [get_registers {*|ramh_psram|engine|rx_early_hold[*] *|ramh_psram|engine|rx_mid_hold[*] *|ramh_psram|engine|rx_center_hold[*] *|ramh_psram|engine|rx_late_hold[*] *|ramh_psram|engine|rx_clock_hold[*]}]
foreach aps_receive_pair {{early_word rx_early_hold} {mid_word rx_mid_hold} {center_word rx_center_hold} {late_word rx_late_hold} {clock_word rx_clock_hold}} {
    lassign $aps_receive_pair aps_receive_source aps_receive_target
    set aps_receive_source_bits [get_registers -no_duplicates [format {*|ramh_psram|engine|rx|%s[*]} $aps_receive_source]]
    set aps_receive_target_bits [get_registers -no_duplicates [format {*|ramh_psram|engine|%s[*]} $aps_receive_target]]
    if {[get_collection_size $aps_receive_source_bits] != 16 || [get_collection_size $aps_receive_target_bits] != 16} {
        error "Expected 16 receive payload and capture bits: $aps_receive_source/$aps_receive_target"
    }
    post_message -type info "APS6408 receive endpoints $aps_receive_source/$aps_receive_target: 16 logical bits"
}
set_max_delay 9.841 -from $aps_receive_sources -to $aps_receive_targets
set_false_path -hold -from $aps_receive_sources -to $aps_receive_targets
