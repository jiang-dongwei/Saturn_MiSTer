project_open Saturn_PSRAM_Diag -revision Saturn_PSRAM_Diag
create_timing_netlist
read_sdc
update_timing_netlist

set dq_inputs [get_ports {PSRAM_DQ[*]}]
# Physical synthesis may retime or duplicate individual read_data bits, so use
# the stable base-name wildcard instead of assuming the pre-fit hierarchy.
set read_regs [get_registers {*read_data*}]

puts "=== STAGE58 PSRAM_DQ TO READ_DATA SETUP ==="
report_timing -setup -from $dq_inputs -to $read_regs -npaths 24 \
	-detail full_path

puts "=== STAGE58 PSRAM_DQ TO READ_DATA HOLD ==="
report_timing -hold -from $dq_inputs -to $read_regs -npaths 24 \
	-detail full_path

delete_timing_netlist
project_close
