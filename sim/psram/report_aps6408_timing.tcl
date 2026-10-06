project_open Saturn_APS6408_Diag -revision Saturn_APS6408_Diag
create_timing_netlist
read_sdc
update_timing_netlist

set diagnostic_regs [get_registers {*|diagnostic|*}]
set dq_regs [get_registers {*|diagnostic|dq_input_sample*}]
set external_inputs [get_ports {PSRAM_DQ[*] PSRAM_DQS}]
if {[get_collection_size $diagnostic_regs] == 0 || [get_collection_size $dq_regs] != 8} {
    error "Missing fitted APS6408 diagnostic or input registers"
}
puts "APS6408 REGISTERS: [get_collection_size $diagnostic_regs]"
foreach check {setup hold} {
    puts "=== APS6408 REGISTER TO REGISTER $check ==="
    report_timing -$check -from $diagnostic_regs -to $diagnostic_regs -npaths 20 -detail full_path
    puts "=== APS6408 DQ INPUT REGISTER TO LOGIC $check ==="
    report_timing -$check -from $dq_regs -to $diagnostic_regs -npaths 12 -detail full_path
    puts "=== APS6408 EXTERNAL INPUT $check ==="
    report_timing -$check -from $external_inputs -to $diagnostic_regs -npaths 12 -detail full_path
    puts "=== GLOBAL WORST $check ==="
    report_timing -$check -npaths 8 -detail full_path
}
delete_timing_netlist
project_close
