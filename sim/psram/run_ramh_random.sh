#!/bin/sh
set -eu

out="${TMPDIR:-/tmp}/ramh_psram_random_tb.vvp"

iverilog -g2012 -Wall -s tb_ramh_psram_random -o "$out" \
	sim/psram/psram_qpi_engine_mock.sv \
	rtl/ramh_psram_adapter.sv \
	sim/psram/tb_ramh_psram_random.sv

for seed in 1A2B3C4D C001D00D 5A17C0DE 89ABCDEF F00DBAAD; do
	vvp "$out" +SEED="$seed"
done
