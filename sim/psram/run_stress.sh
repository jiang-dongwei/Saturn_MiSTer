#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/../.."
out="${TMPDIR:-/tmp}/saturn_psram_stress_tb.vvp"

iverilog -g2012 -Wall -s tb_psram_stress -o "$out" \
	sim/psram/psram_qpi_engine_mock.sv \
	rtl/ramh_psram_adapter.sv \
	rtl/psram_stress_core.sv \
	sim/psram/tb_psram_stress.sv

vvp "$out"
vvp "$out" +FAULT_DATA
vvp "$out" +FAULT_ADDRESS
vvp "$out" +FAULT_CACHE
