project_open Saturn_PSRAM -revision Saturn_PSRAM
create_timing_netlist
read_sdc
update_timing_netlist

set dq_ports [get_ports {PSRAM_DQ[*]}]
set output_ports [get_ports {PSRAM_CE_N PSRAM_DQ[*]}]

puts "=== SATURN PSRAM GENERATED CLOCKS ==="
report_clocks

puts "=== SATURN PSRAM INPUT SETUP ==="
report_timing -setup -from $dq_ports -npaths 24 -detail full_path

puts "=== SATURN PSRAM INPUT HOLD ==="
report_timing -hold -from $dq_ports -npaths 24 -detail full_path

puts "=== SATURN PSRAM OUTPUT SETUP ==="
report_timing -setup -to $output_ports -npaths 24 -detail full_path

puts "=== SATURN PSRAM OUTPUT HOLD ==="
report_timing -hold -to $output_ports -npaths 24 -detail full_path

delete_timing_netlist
project_close
