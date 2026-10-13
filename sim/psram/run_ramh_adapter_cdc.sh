#!/bin/sh
set -eu
cd "$(dirname "$0")/../.."
out="${TMPDIR:-/tmp}/ramh_psram_adapter_cdc_tb.vvp"
for pipeline in 0 1; do
  for delay in 7 12; do
    iverilog -g2012 -Wall -s tb_ramh_psram_adapter \
        -Ptb_ramh_psram_adapter.ASYNC_ENGINE=1 \
        -Ptb_ramh_psram_adapter.FAST_READ_PIPELINE="$pipeline" \
        -Ptb_ramh_psram_adapter.READ_OUTPUT_DELAY_NS="$delay" -o "$out" \
        rtl/psram_qpi_engine.sv rtl/psram_qpi_engine_cdc.sv \
        rtl/ramh_psram_adapter.sv sim/psram/psram_diag_model.sv \
        sim/psram/tb_ramh_psram_adapter.sv
    for phase in 0 3 7; do
        echo "CDC regression: pipeline=${pipeline} DQ delay=${delay}ns engine phase=${phase}ns"
        vvp "$out" +ENGINE_PHASE_NS="$phase"
    done
  done
done
