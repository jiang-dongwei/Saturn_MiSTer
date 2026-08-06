#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/../.."

run_transaction_test() {
	local macro="$1"
	local tag="$2"
	local out="${TMPDIR:-/tmp}/saturn_psram_stress_${tag}_tb.vvp"

	iverilog -g2012 -Wall -D"$macro" -s tb_psram_stress -o "$out" \
		sim/psram/psram_qpi_engine_mock.sv \
		rtl/ramh_psram_adapter.sv \
		rtl/psram_stress_core.sv \
		sim/psram/tb_psram_stress.sv
	vvp "$out"
	vvp "$out" +DWRITE_DROP
	vvp "$out" +CONFIRM_RECOVER
	vvp "$out" +CONFIRM_PERSIST
}

run_qpi_test() {
	local macro="$1"
	local tag="$2"
	local directed_arg="$3"
	local out="${TMPDIR:-/tmp}/saturn_psram_stress_${tag}_qpi_tb.vvp"

	iverilog -g2012 -Wall -D"$macro" -s tb_psram_stress_qpi -o "$out" \
		rtl/psram_qpi_engine.sv \
		rtl/ramh_psram_adapter.sv \
		rtl/psram_stress_core.sv \
		sim/psram/psram_diag_model.sv \
		sim/psram/tb_psram_stress_qpi.sv
	vvp "$out"
	vvp "$out" "$directed_arg"
}

run_transaction_test PSRAM_STRESS_TB_LATE_SAMPLE late_sample
run_qpi_test PSRAM_STRESS_TB_LATE_SAMPLE late_sample +CORRUPT_LEGACY_SAMPLE

run_transaction_test PSRAM_STRESS_TB_LONG_GAP long_gap
run_qpi_test PSRAM_STRESS_TB_LONG_GAP long_gap +LONG_GAP_CHECK
