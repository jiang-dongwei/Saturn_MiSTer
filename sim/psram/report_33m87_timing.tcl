project_open Saturn_PSRAM_33M87 -revision Saturn_PSRAM_33M87
create_timing_netlist
read_sdc
update_timing_netlist

set engine_regs [get_registers {*|ramh_psram|g_async_engine.engine_cdc|engine_core|*}]
set dq_inputs [get_ports {PSRAM_DQ[*]}]
set dq_outputs [get_ports {PSRAM_CE_N PSRAM_DQ[*]}]
if {[get_collection_size $engine_regs] == 0 || [get_collection_size $dq_inputs] != 4 || [get_collection_size $dq_outputs] != 5} {
    error "Missing fitted PSRAM engine registers or external ports"
}
puts "PSRAM ENGINE REGISTERS: [get_collection_size $engine_regs]"
puts "PSRAM INPUT SAMPLE REGISTERS: [get_collection_size [get_registers {*|ramh_psram|g_async_engine.engine_cdc|engine_core|phy|dq_sample*}]]"
foreach check {setup hold} {
    puts "=== PSRAM DQ INPUT $check ==="
    report_timing -$check -from $dq_inputs -to $engine_regs -npaths 16 -detail full_path
    puts "=== PSRAM CE/DQ OUTPUT $check ==="
    report_timing -$check -from $engine_regs -to $dq_outputs -npaths 16 -detail full_path
    puts "=== PSRAM ENGINE ENDPOINTS $check ==="
    report_timing -$check -to $engine_regs -npaths 16 -detail full_path
}
foreach check {setup hold} {
    puts "=== GLOBAL WORST $check ==="
    report_timing -$check -npaths 12 -detail full_path
}
delete_timing_netlist
project_close
