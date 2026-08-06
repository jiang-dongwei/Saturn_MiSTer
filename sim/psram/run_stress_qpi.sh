#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/../.."
out="${TMPDIR:-/tmp}/saturn_psram_stress_qpi_tb.vvp"

iverilog -g2012 -Wall -s tb_psram_stress_qpi -o "$out" \
	rtl/psram_qpi_engine.sv \
	rtl/ramh_psram_adapter.sv \
	rtl/psram_stress_core.sv \
	sim/psram/psram_diag_model.sv \
	sim/psram/tb_psram_stress_qpi.sv

vvp "$out"
