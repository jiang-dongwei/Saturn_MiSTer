project_open Saturn_APS6408 -revision Saturn_APS6408
create_timing_netlist
read_sdc
update_timing_netlist
set corner 0
foreach_in_collection operating_condition [get_available_operating_conditions] {
    set_operating_conditions $operating_condition
    update_timing_netlist
    puts "APS6408 ROUTE BUDGET CORNER $corner: [get_operating_conditions_info $operating_condition -model]"
    foreach check {setup hold} {
        report_timing -$check -from $aps_ddio_sources -to $aps_ddio_targets -npaths 12 -detail full_path -file .ci/aps6408-route-budget-corner$corner-$check.rpt
    }
    incr corner
}
if {$corner != 4} { error "Expected four route-budget operating conditions" }
delete_timing_netlist
# Re-read all constraints on the same fitted design, omitting only the tighter budget.
set aps_report_natural_ddio 1
create_timing_netlist
read_sdc
update_timing_netlist
puts "APS6408 NATURAL CLOCK REQUIREMENT ANALYSIS"
puts "APS6408 REQUEST CONTROL CAPTURES [get_collection_size [get_registers {*|ramh_psram|engine_request_*}]]"
puts "APS6408 REQUEST ADDRESS CAPTURES [get_collection_size [get_registers {*|ramh_psram|engine|runtime_address*}]]"
puts "APS6408 REQUEST DATA CAPTURES [get_collection_size [get_registers {*|ramh_psram|engine|runtime_data*}]]"
puts "APS6408 MODE CAPTURES [get_collection_size [get_registers {*|ramh_psram|engine_speed[*]}]]"
foreach clock_name {APS6408_ENGINE_33 APS6408_ENGINE_50 APS6408_CLK_EXT_33 APS6408_CLK_EXT_50} {
    set clocks [get_clocks $clock_name]
    if {[get_collection_size $clocks] != 1} { error "Missing fitted clock $clock_name" }
    foreach_in_collection clock $clocks {
        puts "APS6408 FITTED CLOCK $clock_name PERIOD [get_clock_info -period $clock] REGISTERS [get_clock_info -nreg_pos $clock]"
        if {[string match APS6408_ENGINE_* $clock_name] && [get_clock_info -nreg_pos $clock] == 0} {
            error "Runtime clock $clock_name does not reach fitted registers"
        }
    }
}

set diagnostic_regs [get_registers {*|ramh_psram|*}]
set dq_regs [get_registers {*|ramh_psram|engine|rx|input_capture|input_ddr|*}]
set external_inputs [get_ports {PSRAM_DQ[*] PSRAM_DQS}]
if {[get_collection_size $diagnostic_regs] == 0 || [get_collection_size $dq_regs] == 0} {
    error "Missing fitted APS6408 diagnostic or input registers"
}
puts "APS6408 REGISTERS: [get_collection_size $diagnostic_regs]"
puts "APS6408 DDIO INPUT REGISTERS: [get_collection_size $dq_regs]"
set corner 0
foreach_in_collection operating_condition [get_available_operating_conditions] {
    set_operating_conditions $operating_condition
    update_timing_netlist
    puts "APS6408 CORNER $corner: [get_operating_conditions_info $operating_condition -model]"
foreach check {setup hold} {
    puts "=== APS6408 REGISTER TO REGISTER $check ==="
    report_timing -$check -from $diagnostic_regs -to $diagnostic_regs -npaths 20 -detail full_path -file .ci/aps6408-corner$corner-internal-$check.rpt
    foreach aps_engine_profile {33 50} {
        set aps_profile_clock [get_clocks APS6408_ENGINE_$aps_engine_profile]
        report_timing -$check -from $diagnostic_regs -to $diagnostic_regs \
            -from_clock $aps_profile_clock -to_clock $aps_profile_clock -npaths 20 \
            -detail full_path -file .ci/aps6408-corner$corner-engine$aps_engine_profile-$check.rpt
    }
    puts "=== APS6408 DQ INPUT REGISTER TO LOGIC $check ==="
    report_timing -$check -from $dq_regs -to $diagnostic_regs -npaths 12 -detail full_path -file .ci/aps6408-corner$corner-dq-register-$check.rpt
    puts "=== APS6408 EXTERNAL INPUT $check ==="
    report_timing -$check -from $external_inputs -to $diagnostic_regs -npaths 12 -detail full_path -file .ci/aps6408-corner$corner-external-$check.rpt
    puts "=== GLOBAL WORST $check ==="
    report_timing -$check -npaths 8 -detail full_path -file .ci/aps6408-corner$corner-global-$check.rpt
}
    incr corner
}
puts "APS6408 OPERATING CONDITIONS REPORTED: $corner"
delete_timing_netlist
project_close
