#============================================================
# 3SQR QPI PSRAM adapter
#
# These six FPGA pins are exposed on the user-accessible J1 header. The
# dedicated PSRAM build deliberately supersedes their legacy SDRAM-DQM and
# secondary-SD assignments from sys.tcl.
#============================================================

# Consumed by sys.tcl when this file is sourced before the common pin map.
set MISTER_PSRAM_ADAPTER 1

set_location_assignment PIN_AG8  -to PSRAM_CLK
set_location_assignment PIN_AE15 -to PSRAM_CE_N
set_location_assignment PIN_U13  -to PSRAM_DQ[0]
set_location_assignment PIN_AH8  -to PSRAM_DQ[1]
set_location_assignment PIN_AG13 -to PSRAM_DQ[2]
set_location_assignment PIN_AF13 -to PSRAM_DQ[3]

set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to PSRAM_*
set_instance_assignment -name CURRENT_STRENGTH_NEW 8MA -to PSRAM_*
set_instance_assignment -name FAST_INPUT_REGISTER ON -to PSRAM_DQ[*]
