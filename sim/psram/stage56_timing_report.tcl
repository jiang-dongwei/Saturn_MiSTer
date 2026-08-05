project_open Saturn_PSRAM_Diag -revision Saturn_PSRAM_Diag
create_timing_netlist
read_sdc
update_timing_netlist

puts "=== STAGE56 WORST HOLD PATHS ==="
report_timing -hold -npaths 12 -detail full_path

puts "=== STAGE56 WORST SETUP PATHS ==="
report_timing -setup -npaths 12 -detail full_path

delete_timing_netlist
project_close
