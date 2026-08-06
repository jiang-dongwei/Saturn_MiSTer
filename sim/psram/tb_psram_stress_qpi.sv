`timescale 1ns/1ps

module tb_psram_stress_qpi;

reg clk = 1'b0;
reg reset = 1'b1;
always #7.381 clk = ~clk;

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

`ifdef PSRAM_STRESS_TB_DWRITE
localparam integer TB_READ_LINE_BYTES = 4;
`elsif PSRAM_STRESS_TB_CONFIRM
localparam integer TB_READ_LINE_BYTES = 4;
`elsif PSRAM_STRESS_TB_SAFE
localparam integer TB_READ_LINE_BYTES = 4;
`elsif PSRAM_STRESS_TB_4B
localparam integer TB_READ_LINE_BYTES = 4;
`else
localparam integer TB_READ_LINE_BYTES = 16;
`endif
`ifdef PSRAM_STRESS_TB_DWRITE
localparam [5:0] TB_HALF_DIVIDER = 6'd4;
localparam integer TB_CONFIRM_ON_MISMATCH = 1;
localparam integer TB_DUPLICATE_WRITES = 1;
`elsif PSRAM_STRESS_TB_CONFIRM
localparam [5:0] TB_HALF_DIVIDER = 6'd4;
localparam integer TB_CONFIRM_ON_MISMATCH = 1;
localparam integer TB_DUPLICATE_WRITES = 0;
`elsif PSRAM_STRESS_TB_SAFE
localparam [5:0] TB_HALF_DIVIDER = 6'd4;
localparam integer TB_CONFIRM_ON_MISMATCH = 0;
localparam integer TB_DUPLICATE_WRITES = 0;
`elsif PSRAM_STRESS_TB_SLOW
localparam [5:0] TB_HALF_DIVIDER = 6'd4;
localparam integer TB_CONFIRM_ON_MISMATCH = 0;
localparam integer TB_DUPLICATE_WRITES = 0;
`else
localparam [5:0] TB_HALF_DIVIDER = 6'd2;
localparam integer TB_CONFIRM_ON_MISMATCH = 0;
localparam integer TB_DUPLICATE_WRITES = 0;
`endif

psram_stress_core
#(
	.WORD_COUNT(16),
	.POWERUP_CYCLES(2),
	.HALF_DIVIDER(TB_HALF_DIVIDER),
	.GUARD_CYCLES(2),
	.READ_LINE_BYTES(TB_READ_LINE_BYTES),
	.CONFIRM_ON_MISMATCH(TB_CONFIRM_ON_MISMATCH),
	.DUPLICATE_WRITES(TB_DUPLICATE_WRITES)
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

psram_diag_model
#(
	.READ_OUTPUT_DELAY_NS(0),
	.ADDRESS_MASK(23'h000FFF)
)
memory
(
	.ce_n(psram_ce_n),
	.sclk(psram_clk),
	.dq(psram_dq)
);

initial begin
	repeat (6) @(posedge clk);
	reset <= 1'b0;
	wait (loop_count >= 1);
	if (failed || init_error || (device_id != 16'h0D5D)) begin
		$display("FAIL: bit-level QPI stress phase=%02x id=%04x exp=%08x act=%08x",
		         phase_code, device_id, expected_data, actual_data);
		$fatal(1);
	end
	$display("PASS: bit-level QPI stress loop operations=%0d id=%04x",
	         operation_count, device_id);
	$finish;
end

initial begin
	#50000000;
	$display("FAIL: bit-level QPI stress timeout phase=%02x pattern=%x ops=%0d",
	         phase_code, pattern_id, operation_count);
	$fatal(1);
end

endmodule
