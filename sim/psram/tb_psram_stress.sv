`timescale 1ns/1ps

module tb_psram_stress;

reg clk = 1'b0;
reg reset = 1'b1;
always #5 clk = ~clk;

wire [1:0] result_code;
wire [7:0] phase_code;
wire [3:0] pattern_id;
wire [31:0] loop_count;
wire [31:0] operation_count;
wire [23:0] current_address;
wire [31:0] expected_data;
wire [31:0] actual_data;
wire [31:0] xor_data;
wire [31:0] confirm_data1;
wire [31:0] confirm_data2;
wire [3:0] byte_mask;
wire [15:0] device_id;
wire init_done;
wire init_error;
wire failed;
wire activity;
wire psram_clk;
wire psram_ce_n;
tri [3:0] psram_dq;

`ifdef PSRAM_STRESS_TB_CONFIRM
localparam integer TB_READ_LINE_BYTES = 4;
`elsif PSRAM_STRESS_TB_SAFE
localparam integer TB_READ_LINE_BYTES = 4;
`elsif PSRAM_STRESS_TB_4B
localparam integer TB_READ_LINE_BYTES = 4;
`else
localparam integer TB_READ_LINE_BYTES = 16;
`endif
`ifdef PSRAM_STRESS_TB_CONFIRM
localparam [5:0] TB_HALF_DIVIDER = 6'd4;
localparam integer TB_CONFIRM_ON_MISMATCH = 1;
`elsif PSRAM_STRESS_TB_SAFE
localparam [5:0] TB_HALF_DIVIDER = 6'd4;
localparam integer TB_CONFIRM_ON_MISMATCH = 0;
`elsif PSRAM_STRESS_TB_SLOW
localparam [5:0] TB_HALF_DIVIDER = 6'd4;
localparam integer TB_CONFIRM_ON_MISMATCH = 0;
`else
localparam [5:0] TB_HALF_DIVIDER = 6'd2;
localparam integer TB_CONFIRM_ON_MISMATCH = 0;
`endif

psram_stress_core
#(
	.WORD_COUNT(64),
	.POWERUP_CYCLES(2),
	.HALF_DIVIDER(TB_HALF_DIVIDER),
	.GUARD_CYCLES(1),
	.READ_LINE_BYTES(TB_READ_LINE_BYTES),
	.CONFIRM_ON_MISMATCH(TB_CONFIRM_ON_MISMATCH)
)
dut
(
	.clk(clk),
	.reset(reset),
	.result_code(result_code),
	.phase_code(phase_code),
	.pattern_id(pattern_id),
	.loop_count(loop_count),
	.operation_count(operation_count),
	.current_address(current_address),
	.expected_data(expected_data),
	.actual_data(actual_data),
	.xor_data(xor_data),
	.confirm_data1(confirm_data1),
	.confirm_data2(confirm_data2),
	.byte_mask(byte_mask),
	.device_id(device_id),
	.init_done(init_done),
	.init_error(init_error),
	.failed(failed),
	.activity(activity),
	.PSRAM_CLK(psram_clk),
	.PSRAM_CE_N(psram_ce_n),
	.PSRAM_DQ(psram_dq)
);

task wait_for_failure;
	input [7:0] expected_phase;
	begin
		wait (failed);
		if (phase_code !== expected_phase) begin
			$display("FAIL: expected failure phase %02x, got %02x", expected_phase,
			         phase_code);
			$fatal(1);
		end
		if (xor_data == 0) begin
			$display("FAIL: checker entered failure with zero XOR");
			$fatal(1);
		end
		$display("PASS: injected fault caught phase=%02x addr=%06x exp=%08x act=%08x xor=%08x",
		         phase_code, current_address, expected_data, actual_data, xor_data);
		$finish;
	end
endtask

initial begin
	integer confirm_start_count;
	repeat (6) @(posedge clk);
	reset <= 1'b0;

	if ($test$plusargs("CONFIRM_RECOVER")) begin
		wait ((phase_code == 8'h20) && (pattern_id == 0));
		dut.adapter.engine.memory[32] =
			dut.adapter.engine.memory[32] ^ 8'h01;
		wait (dut.tester.hstate == 5'd16);
		confirm_start_count = dut.adapter.engine.accepted_count;
		dut.adapter.engine.memory[32] =
			dut.adapter.engine.memory[32] ^ 8'h01;
		wait (failed);
		if ((actual_data == 0) || (confirm_data1 != 0) ||
		    (confirm_data2 != 0) ||
		    ((dut.adapter.engine.accepted_count - confirm_start_count) != 4)) begin
			$display("FAIL: recover confirm R0=%08x R1=%08x R2=%08x requests=%0d",
			         actual_data, confirm_data1, confirm_data2,
			         dut.adapter.engine.accepted_count - confirm_start_count);
			$fatal(1);
		end
		$display("PASS: physical rereads recovered R0=%08x R1=%08x R2=%08x",
		         actual_data, confirm_data1, confirm_data2);
		$finish;
	end
	else if ($test$plusargs("CONFIRM_PERSIST")) begin
		wait ((phase_code == 8'h20) && (pattern_id == 0));
		dut.adapter.engine.memory[32] =
			dut.adapter.engine.memory[32] ^ 8'h01;
		wait (dut.tester.hstate == 5'd16);
		confirm_start_count = dut.adapter.engine.accepted_count;
		wait (failed);
		if ((actual_data == 0) || (confirm_data1 != actual_data) ||
		    (confirm_data2 != actual_data) ||
		    ((dut.adapter.engine.accepted_count - confirm_start_count) != 4)) begin
			$display("FAIL: persistent confirm R0=%08x R1=%08x R2=%08x requests=%0d",
			         actual_data, confirm_data1, confirm_data2,
			         dut.adapter.engine.accepted_count - confirm_start_count);
			$fatal(1);
		end
		$display("PASS: physical rereads persistent R0=%08x R1=%08x R2=%08x",
		         actual_data, confirm_data1, confirm_data2);
		$finish;
	end
	else if ($test$plusargs("FAULT_DATA")) begin
		wait ((phase_code == 8'h20) && (pattern_id == 0));
		dut.adapter.engine.memory[32] =
			dut.adapter.engine.memory[32] ^ 8'h01;
		wait_for_failure(8'h20);
	end
	else if ($test$plusargs("FAULT_ADDRESS")) begin
		wait ((phase_code == 8'h24) && (pattern_id == 4));
		dut.adapter.engine.read_address_xor = 24'h000004;
		wait_for_failure(8'h24);
	end
	else if ($test$plusargs("FAULT_CACHE")) begin
		wait ((dut.tester.hstate == 5'd13) &&
		      (dut.tester.cache_step == 5'd9));
		force dut.adapter.line_valid = 1'b1;
		wait ((dut.tester.hstate == 5'd13) &&
		      (dut.tester.cache_step == 5'd10));
		release dut.adapter.line_valid;
		wait_for_failure(8'h50);
	end
	else begin
		wait (loop_count >= 2);
		if (failed || init_error || (device_id != 16'h0D5D)) begin
			$display("FAIL: normal run failed loops=%0d phase=%02x id=%04x",
			         loop_count, phase_code, device_id);
			$fatal(1);
		end
		$display("PASS: two complete stress loops, operations=%0d", operation_count);
		$finish;
	end
end

initial begin
	#20000000;
	$display("FAIL: stress testbench timeout phase=%02x pattern=%x loops=%0d ops=%0d",
	         phase_code, pattern_id, loop_count, operation_count);
	$fatal(1);
end

endmodule
