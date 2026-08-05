project_open Saturn_PSRAM_Diag -revision Saturn_PSRAM_Diag
create_timing_netlist
read_sdc
update_timing_netlist

report_timing -setup -npaths 12 -detail full_path \
	-to [get_ports {PSRAM_CE_N PSRAM_DQ[*]}]

delete_timing_netlist
project_close
