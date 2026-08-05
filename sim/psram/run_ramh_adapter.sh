#!/bin/sh
set -eu

out="${TMPDIR:-/tmp}/ramh_psram_adapter_tb.vvp"

iverilog -g2012 -Wall -s tb_ramh_psram_adapter -o "$out" \
	rtl/psram_qpi_engine.sv \
	rtl/ramh_psram_adapter.sv \
	sim/psram/psram_diag_model.sv \
	sim/psram/tb_ramh_psram_adapter.sv
vvp "$out"
