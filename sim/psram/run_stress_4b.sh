#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/../.."
out="${TMPDIR:-/tmp}/saturn_psram_stress_4b_tb.vvp"
qpi_out="${TMPDIR:-/tmp}/saturn_psram_stress_4b_qpi_tb.vvp"

iverilog -g2012 -Wall -DPSRAM_STRESS_TB_4B -s tb_psram_stress -o "$out" \
	sim/psram/psram_qpi_engine_mock.sv \
	rtl/ramh_psram_adapter.sv \
	rtl/psram_stress_core.sv \
	sim/psram/tb_psram_stress.sv

vvp "$out"
vvp "$out" +FAULT_DATA
vvp "$out" +FAULT_ADDRESS

iverilog -g2012 -Wall -DPSRAM_STRESS_TB_4B -s tb_psram_stress_qpi -o "$qpi_out" \
	rtl/psram_qpi_engine.sv \
	rtl/ramh_psram_adapter.sv \
	rtl/psram_stress_core.sv \
	sim/psram/psram_diag_model.sv \
	sim/psram/tb_psram_stress_qpi.sv

vvp "$qpi_out"
