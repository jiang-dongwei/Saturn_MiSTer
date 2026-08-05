#!/bin/sh
set -eu

cd "$(dirname "$0")/../.."

iverilog -g2012 -Wall \
	-s tb_psram_qpi_engine \
	-o /tmp/saturn_psram_qpi_engine_tb \
	rtl/psram_qpi_engine.sv \
	sim/psram/psram_diag_model.sv \
	sim/psram/tb_psram_qpi_engine.sv

vvp /tmp/saturn_psram_qpi_engine_tb
