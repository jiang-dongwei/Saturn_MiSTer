#!/bin/sh
set -eu

cd "$(dirname "$0")/../.."

iverilog -g2012 \
	-s tb_psram_diag \
	-o /tmp/saturn_psram_diag_tb \
	rtl/psram_diag_bus.sv \
	rtl/psram_diag_core.sv \
	sim/psram/psram_diag_model.sv \
	sim/psram/tb_psram_diag.sv

vvp /tmp/saturn_psram_diag_tb
