project_open Saturn_APS6408_1M -revision Saturn_APS6408_1M
create_timing_netlist
read_sdc
update_timing_netlist
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
