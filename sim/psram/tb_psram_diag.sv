`timescale 1ns/1ps

module tb_psram_diag;

reg clk = 1'b0;
always #7.381 clk = ~clk; // 67.7376 MHz

reg reset = 1'b1;

wire [1:0] good_result;
wire [7:0] good_stage;
wire [47:0] good_id;
wire good_kgd;
wire [23:0] good_address;
wire [15:0] good_expected;
wire [15:0] good_actual;
wire [2:0] good_speed;
wire [7:0] good_leds;
wire good_activity;
wire good_clk;
wire good_ce_n;
wire [3:0] good_dq;

wire [1:0] bad_result;
wire [7:0] bad_stage;
wire bad_clk;
wire bad_ce_n;
wire [3:0] bad_dq;

wire [1:0] alias_result;
wire [7:0] alias_stage;
wire alias_clk;
wire alias_ce_n;
wire [3:0] alias_dq;

wire [1:0] noid_result;
wire [7:0] noid_stage;
wire noid_clk;
wire noid_ce_n;
wire [3:0] noid_dq;

wire [1:0] tail_result;
wire [7:0] tail_stage;
wire [15:0] tail_actual;
wire tail_clk;
wire tail_ce_n;
wire [3:0] tail_dq;

wire [1:0] write_result;
wire [7:0] write_stage;
wire [15:0] write_actual;
wire write_clk;
wire write_ce_n;
wire [3:0] write_dq;
wire [23:0] write_matrix_a;
wire [23:0] write_matrix_b;
wire [23:0] write_matrix_c;

wire [1:0] trace_result;
wire [7:0] trace_stage;
wire [47:0] trace_id;
wire trace_kgd;
wire [23:0] trace_matrix_a;
wire [23:0] trace_matrix_b;
wire [23:0] trace_matrix_c;
wire trace_clk;
wire trace_ce_n;
wire [3:0] trace_dq;

wire [1:0] write_tail_result;
wire [7:0] write_tail_stage;
wire [15:0] write_tail_actual;
wire write_tail_clk;
wire write_tail_ce_n;
wire [3:0] write_tail_dq;


psram_diag_core #(.POWERUP_CYCLES(8)) dut_good
(
	.clk(clk), .reset(reset), .mode(2'd0), .max_speed_select(3'd0),
	.result_code(good_result), .stage_code(good_stage),
	.id_value(good_id), .id_kgd_ok(good_kgd),
	.failure_address(good_address), .expected_data(good_expected),
	.actual_data(good_actual), .speed_index(good_speed),
	.diagnostic_leds(good_leds), .activity(good_activity),
	.PSRAM_CLK(good_clk), .PSRAM_CE_N(good_ce_n), .PSRAM_DQ(good_dq)
);

psram_diag_model memory_good
(
	.ce_n(good_ce_n), .sclk(good_clk), .dq(good_dq)
);

psram_diag_core #(.POWERUP_CYCLES(8)) dut_bad
(
	.clk(clk), .reset(reset), .mode(2'd0), .max_speed_select(3'd0),
	.result_code(bad_result), .stage_code(bad_stage),
	.id_value(), .id_kgd_ok(), .failure_address(), .expected_data(),
	.actual_data(), .speed_index(), .diagnostic_leds(), .activity(),
	.PSRAM_CLK(bad_clk), .PSRAM_CE_N(bad_ce_n), .PSRAM_DQ(bad_dq)
);

psram_diag_model #(.FORCE_BAD_READ(1)) memory_bad
(
	.ce_n(bad_ce_n), .sclk(bad_clk), .dq(bad_dq)
);

psram_diag_core #(.POWERUP_CYCLES(8)) dut_alias
(
	.clk(clk), .reset(reset), .mode(2'd0), .max_speed_select(3'd0),
	.result_code(alias_result), .stage_code(alias_stage),
	.id_value(), .id_kgd_ok(), .failure_address(), .expected_data(),
	.actual_data(), .speed_index(), .diagnostic_leds(), .activity(),
	.PSRAM_CLK(alias_clk), .PSRAM_CE_N(alias_ce_n), .PSRAM_DQ(alias_dq)
);

psram_diag_model #(.ADDRESS_MASK(23'h3FFFFF)) memory_alias
(
	.ce_n(alias_ce_n), .sclk(alias_clk), .dq(alias_dq)
);

psram_diag_core #(.POWERUP_CYCLES(8)) dut_noid
(
	.clk(clk), .reset(reset), .mode(2'd0), .max_speed_select(3'd0),
	.result_code(noid_result), .stage_code(noid_stage),
	.id_value(), .id_kgd_ok(), .failure_address(), .expected_data(),
	.actual_data(), .speed_index(), .diagnostic_leds(), .activity(),
	.PSRAM_CLK(noid_clk), .PSRAM_CE_N(noid_ce_n), .PSRAM_DQ(noid_dq)
);

psram_diag_model #(.ID_VALUE(48'd0)) memory_noid
(
	.ce_n(noid_ce_n), .sclk(noid_clk), .dq(noid_dq)
);

psram_diag_core #(.POWERUP_CYCLES(8)) dut_tail
(
	.clk(clk), .reset(reset), .mode(2'd0), .max_speed_select(3'd0),
	.result_code(tail_result), .stage_code(tail_stage),
	.id_value(), .id_kgd_ok(), .failure_address(), .expected_data(),
	.actual_data(tail_actual), .speed_index(), .diagnostic_leds(), .activity(),
	.PSRAM_CLK(tail_clk), .PSRAM_CE_N(tail_ce_n), .PSRAM_DQ(tail_dq)
);

psram_diag_model #(.FORCE_SHORT_TAIL(1)) memory_tail
(
	.ce_n(tail_ce_n), .sclk(tail_clk), .dq(tail_dq)
);

psram_diag_core #(.POWERUP_CYCLES(8)) dut_write
(
	.clk(clk), .reset(reset), .mode(2'd0), .max_speed_select(3'd0),
	.result_code(write_result), .stage_code(write_stage),
	.id_value(), .id_kgd_ok(), .failure_address(), .expected_data(),
	.actual_data(write_actual), .speed_index(), .diagnostic_leds(), .activity(),
	.matrix_a(write_matrix_a), .matrix_b(write_matrix_b), .matrix_c(write_matrix_c),
	.PSRAM_CLK(write_clk), .PSRAM_CE_N(write_ce_n), .PSRAM_DQ(write_dq)
);

psram_diag_model #(.FORCE_BAD_WRITE(1)) memory_write
(
	.ce_n(write_ce_n), .sclk(write_clk), .dq(write_dq)
);

psram_diag_core #(.POWERUP_CYCLES(8), .DDIO_TRACE_MODE(1'b1)) dut_trace
(
	.clk(clk), .reset(reset), .mode(2'd0), .max_speed_select(3'd0),
	.result_code(trace_result), .stage_code(trace_stage),
	.id_value(trace_id), .id_kgd_ok(trace_kgd),
	.failure_address(), .expected_data(), .actual_data(), .speed_index(),
	.diagnostic_leds(), .activity(),
	.matrix_a(trace_matrix_a), .matrix_b(trace_matrix_b),
	.matrix_c(trace_matrix_c),
	.PSRAM_CLK(trace_clk), .PSRAM_CE_N(trace_ce_n), .PSRAM_DQ(trace_dq)
);

// Stress the trace instance with 16 ns of end-to-end DQ delay.  This is long
// enough to expose the divider=1 stale-sample bug while divider=2 and 4 retain
// ample margin.  The corrected fast path captures at the following falling
// boundary, nearly one full 33.87 MHz clock period after launch.
psram_diag_model #(.READ_OUTPUT_DELAY_NS(16)) memory_trace
(
	.ce_n(trace_ce_n), .sclk(trace_clk), .dq(trace_dq)
);

psram_diag_core #(.POWERUP_CYCLES(8)) dut_write_tail
(
	.clk(clk), .reset(reset), .mode(2'd0), .max_speed_select(3'd0),
	.result_code(write_tail_result), .stage_code(write_tail_stage),
	.id_value(), .id_kgd_ok(), .failure_address(), .expected_data(),
	.actual_data(write_tail_actual), .speed_index(), .diagnostic_leds(), .activity(),
	.PSRAM_CLK(write_tail_clk), .PSRAM_CE_N(write_tail_ce_n), .PSRAM_DQ(write_tail_dq)
);

psram_diag_model #(.FORCE_SHORT_WRITE_TAIL(1)) memory_write_tail
(
	.ce_n(write_tail_ce_n), .sclk(write_tail_clk), .dq(write_tail_dq)
);

realtime last_good_rise;
realtime last_good_ce_rise;
realtime last_good_ce_fall;
reg good_clock_seen = 1'b0;
reg good_ce_seen = 1'b0;

realtime trace_last_rise;
realtime trace_last_fall;
reg trace_have_rise = 1'b0;
reg trace_have_fall = 1'b0;
integer trace_div4_rises = 0;
integer trace_div4_falls = 0;
integer trace_div2_rises = 0;
integer trace_div2_falls = 0;
integer trace_div1_rises = 0;
integer trace_div1_falls = 0;
realtime trace_expected_half;
realtime trace_observed_half;

always @(posedge good_clk) begin
	if (!good_ce_n) begin
		last_good_rise = $realtime;
		good_clock_seen = 1'b1;
	end
end

always @(posedge good_ce_n) begin
	if (($realtime - last_good_ce_fall) > 8000.0) begin
		$display("FAIL: CE# stayed low for %0.3f ns, exceeding tCEM=8 us",
		         $realtime - last_good_ce_fall);
		$fatal;
	end
	if (good_clock_seen && (($realtime - last_good_rise) < 50.0)) begin
		$display("FAIL: CE# rose only %0.3f ns after the final clock rise",
		         $realtime - last_good_rise);
		$fatal;
	end
	last_good_ce_rise = $realtime;
	good_ce_seen = 1'b1;
end

always @(negedge good_ce_n) begin
	last_good_ce_fall = $realtime;
	if (good_ce_seen && (($realtime - last_good_ce_rise) < 50.0)) begin
		$display("FAIL: CE# high recovery was only %0.3f ns",
		         $realtime - last_good_ce_rise);
		$fatal;
	end
end

// Stage 58 performs one 20-clock QPI read at each divider 4, 2 and 1. At the
// simulated 67.7376 MHz controller clock their HIGH/LOW phases are 59.048,
// 29.524 and 14.762 ns. Reset phase history at each CE# transaction boundary
// so the inter-transaction recovery gap is not measured as a clock low phase.
always @(negedge trace_ce_n) begin
	trace_have_rise = 1'b0;
	trace_have_fall = 1'b0;
end

always @(posedge trace_clk) begin
	if (!trace_ce_n && dut_trace.bus_qpi && dut_trace.bus_read_enable) begin
		case (dut_trace.bus_half_divider)
			6'd4: trace_div4_rises = trace_div4_rises + 1;
			6'd2: trace_div2_rises = trace_div2_rises + 1;
			6'd1: trace_div1_rises = trace_div1_rises + 1;
			default: begin end
		endcase
		if (trace_have_fall) begin
			trace_expected_half = 14.762 * dut_trace.bus_half_divider;
			trace_observed_half = $realtime - trace_last_fall;
			if (trace_observed_half < (trace_expected_half - 0.6) ||
			    trace_observed_half > (trace_expected_half + 0.6)) begin
				$display("FAIL: Stage 58 divider=%0d LOW width=%0.3f ns expected=%0.3f ns",
				         dut_trace.bus_half_divider, trace_observed_half,
				         trace_expected_half);
				$fatal;
			end
		end
		trace_last_rise = $realtime;
		trace_have_rise = 1'b1;
	end
end

always @(negedge trace_clk) begin
	if (!trace_ce_n && dut_trace.bus_qpi && dut_trace.bus_read_enable) begin
		case (dut_trace.bus_half_divider)
			6'd4: trace_div4_falls = trace_div4_falls + 1;
			6'd2: trace_div2_falls = trace_div2_falls + 1;
			6'd1: trace_div1_falls = trace_div1_falls + 1;
			default: begin end
		endcase
		if (trace_have_rise) begin
			trace_expected_half = 14.762 * dut_trace.bus_half_divider;
			trace_observed_half = $realtime - trace_last_rise;
			if (trace_observed_half < (trace_expected_half - 0.6) ||
			    trace_observed_half > (trace_expected_half + 0.6)) begin
				$display("FAIL: Stage 58 divider=%0d HIGH width=%0.3f ns expected=%0.3f ns",
				         dut_trace.bus_half_divider, trace_observed_half,
				         trace_expected_half);
				$fatal;
			end
		end
		trace_last_fall = $realtime;
		trace_have_fall = 1'b1;
	end
end

always @* begin
	if (dut_good.bus.dq_oe && memory_good.dq_oe) begin
		$display("FAIL: controller and good memory drove DQ simultaneously");
		$fatal;
	end
end

initial begin
	integer timeout;
	repeat (5) @(posedge clk);
	reset <= 1'b0;

	timeout = 0;
	while (((good_result == 0) || (bad_result == 0) ||
	        (alias_result == 0) || (noid_result == 0) ||
	        (tail_result == 0) || (write_result == 0) ||
	        (write_tail_result == 0) || (trace_result == 0)) &&
	       timeout < 1000000) begin
		@(posedge clk);
		timeout = timeout + 1;
	end

	if (good_result != 1 || good_stage != 8'h0A ||
	    good_id != 48'h0D5D_0000_0000 || !good_kgd ||
	    good_leds[6] != 1'b1) begin
		$display("FAIL: good device result=%0d stage=%02x id=%012x leds=%02x addr=%06x expected=%04x actual=%04x",
		         good_result, good_stage, good_id, good_leds, good_address,
		         good_expected, good_actual);
		$fatal;
	end

	if (bad_result != 2 || bad_stage != 8'h03) begin
		$display("FAIL: corrupted read was not isolated to QPI basic stage: result=%0d stage=%02x",
		         bad_result, bad_stage);
		$fatal;
	end

	if (alias_result != 2 || alias_stage != 8'h05) begin
		$display("FAIL: 4 MiB alias was not isolated to address stage: result=%0d stage=%02x",
		         alias_result, alias_stage);
		$fatal;
	end

	if (noid_result != 2 || noid_stage != 8'h01) begin
		$display("FAIL: missing/zero ID was not isolated to SPI ID stage: result=%0d stage=%02x",
		         noid_result, noid_stage);
		$fatal;
	end

	if (tail_result != 2 || tail_stage != 8'h41 || tail_actual != 16'hFFF5) begin
		$display("FAIL: short-read tail fault was not isolated: result=%0d stage=%02x actual=%04x",
		         tail_result, tail_stage, tail_actual);
		$fatal;
	end

	if (write_tail_result != 2 || write_tail_stage != 8'h43 ||
	    write_tail_actual != 16'hFFF5) begin
		$display("FAIL: short-write tail fault was not isolated: result=%0d stage=%02x actual=%04x",
		         write_tail_result, write_tail_stage, write_tail_actual);
		$fatal;
	end

	if (write_result != 3 || write_stage != 8'h52 ||
	    write_matrix_a != 24'hFF00FF || write_matrix_b != 24'hFF00FF ||
	    write_matrix_c != 24'hFF00FF) begin
		$display("FAIL: QPI read command-matrix mismatch: result=%0d stage=%02x A=%06x B=%06x C=%06x actual=%04x",
		         write_result, write_stage, write_matrix_a, write_matrix_b,
		         write_matrix_c, write_actual);
		$fatal;
	end

	if (trace_result != 3 || trace_stage != 8'h58 ||
	    trace_id != 48'h0D5D_0000_0000 || !trace_kgd ||
	    trace_matrix_a != 24'h1234A5 ||
	    trace_matrix_b != 24'h1234A5 ||
	    trace_matrix_c != 24'h1234A5) begin
		$display("FAIL: Stage 58 speed-ladder mismatch: result=%0d stage=%02x id=%012x kgd=%0d A=%06x B=%06x C=%06x",
		         trace_result, trace_stage, trace_id, trace_kgd,
		         trace_matrix_a, trace_matrix_b, trace_matrix_c);
		$fatal;
	end

	if (trace_div4_rises != 20 || trace_div4_falls != 20 ||
	    trace_div2_rises != 20 || trace_div2_falls != 20 ||
	    trace_div1_rises != 20 || trace_div1_falls != 20) begin
		$display("FAIL: Stage 58 clock counts d4=%0d/%0d d2=%0d/%0d d1=%0d/%0d",
		         trace_div4_rises, trace_div4_falls,
		         trace_div2_rises, trace_div2_falls,
		         trace_div1_rises, trace_div1_falls);
		$fatal;
	end

	$display("Stage 58 waveform counts: d4=%0d/%0d d2=%0d/%0d d1=%0d/%0d",
	         trace_div4_rises, trace_div4_falls,
	         trace_div2_rises, trace_div2_falls,
	         trace_div1_rises, trace_div1_falls);

	$display("PASS: diagnostic fault isolation, Stage 52 matrix, and Stage 58 fast-capture ladder");
	$finish;
end

endmodule
