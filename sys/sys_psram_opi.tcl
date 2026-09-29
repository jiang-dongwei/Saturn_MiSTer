# APS6408L-3OBM-BA diagnostic board, CN5 HDMI-shaped connector to DE10-Nano J1.
# AH17/AH16 are driven by the DE10-Nano's U29 button buffer.  Do not build a
# bitstream that drives them until CLK/CE# are rerouted or U29 is isolated.
error "Unsafe APS6408 wiring: PSRAM_CLK/CE_N target KEY0/KEY1 (AH17/AH16), which U29 actively drives. Reroute CLK/CE_N and update this file before building."
set MISTER_PSRAM_ADAPTER 1
set MISTER_OPI_DIAG 1

set_location_assignment PIN_AH17 -to PSRAM_CLK
set_location_assignment PIN_AH16 -to PSRAM_CE_N
set_location_assignment PIN_U13  -to PSRAM_DQ[0]
set_location_assignment PIN_AH8  -to PSRAM_DQ[1]
set_location_assignment PIN_AG13 -to PSRAM_DQ[2]
set_location_assignment PIN_AF13 -to PSRAM_DQ[3]
set_location_assignment PIN_AG10 -to PSRAM_DQ[4]
set_location_assignment PIN_AG8  -to PSRAM_DQ[5]
set_location_assignment PIN_AE15 -to PSRAM_DQ[6]
set_location_assignment PIN_AG9  -to PSRAM_DQ[7]
set_location_assignment PIN_U14  -to PSRAM_DQS

set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to PSRAM_*
set_instance_assignment -name CURRENT_STRENGTH_NEW 8MA -to PSRAM_*
set_instance_assignment -name FAST_INPUT_REGISTER ON -to PSRAM_DQ[*]
set_instance_assignment -name FAST_INPUT_REGISTER ON -to PSRAM_DQS
