# The async QPI engine is clocked by the diagnostic PLL's 67.7376 MHz output.
# HALF_DIVIDER=1 toggles the registered forwarded clock every engine cycle,
# producing a 33.8688 MHz square wave on PSRAM_CLK.
create_generated_clock -name PSRAM_33M87_CLK_EXT \
	-source [get_pins {*|ramh_psram_adapter:ramh_psram|psram_qpi_engine_cdc:g_async_engine.engine_cdc|psram_qpi_engine:engine_core|psram_qpi_phy:phy|PSRAM_CLK|clk}] -divide_by 2 \
	[get_pins {*|ramh_psram_adapter:ramh_psram|psram_qpi_engine_cdc:g_async_engine.engine_cdc|psram_qpi_engine:engine_core|psram_qpi_phy:phy|PSRAM_CLK|q}]

set_output_delay -clock PSRAM_33M87_CLK_EXT -max 2.000 \
	[get_ports {PSRAM_CE_N PSRAM_DQ[*]}]
set_output_delay -clock PSRAM_33M87_CLK_EXT -min -2.000 \
	[get_ports {PSRAM_CE_N PSRAM_DQ[*]}]

set_input_delay -clock PSRAM_33M87_CLK_EXT -clock_fall -max 7.000 \
	[get_ports {PSRAM_DQ[*]}]
set_input_delay -clock PSRAM_33M87_CLK_EXT -clock_fall -min 1.000 \
	[get_ports {PSRAM_DQ[*]}]

# Toggle synchronizers are the timing boundary. Request payload and response
# data are held stable by the one-outstanding-request handshake until the
# corresponding toggle has crossed both synchronizer stages.
set_false_path -to [get_registers {*|ramh_psram_adapter:ramh_psram|psram_qpi_engine_cdc:g_async_engine.engine_cdc|req_sync1*}]
set_false_path -to [get_registers {*|ramh_psram_adapter:ramh_psram|psram_qpi_engine_cdc:g_async_engine.engine_cdc|ack_sync1*}]
set_false_path -to [get_registers {*|ramh_psram_adapter:ramh_psram|psram_qpi_engine_cdc:g_async_engine.engine_cdc|init_done_sync1*}]
set_false_path -to [get_registers {*|ramh_psram_adapter:ramh_psram|psram_qpi_engine_cdc:g_async_engine.engine_cdc|init_error_sync1*}]
set_false_path -from [get_registers {*|ramh_psram_adapter:ramh_psram|psram_qpi_engine_cdc:g_async_engine.engine_cdc|src_request_*}]
set_false_path -from [get_registers {*|ramh_psram_adapter:ramh_psram|psram_qpi_engine_cdc:g_async_engine.engine_cdc|response_error*}]
set_false_path -to [get_registers {*|ramh_psram_adapter:ramh_psram|line_data*}]

# psram_engine_reset_pipe is the conventional asynchronous-assert,
# synchronous-release reset synchronizer for the new PLL domain.  Quartus
# implements the packed pipe as a register with a synchronous-clear control
# mux, so constrain the synchronizer register endpoint rather than a physical
# aclr pin that does not exist in the fitted netlist.
set_false_path -to [get_registers {*|psram_engine_reset_pipe*}]
