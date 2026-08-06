`timescale 1ns/1ps

// Standalone RAMH-side stress test for the Saturn QPI PSRAM backend.
// All memory traffic enters through ramh_psram_adapter, matching the logical
// interface used by the full Saturn core.
module psram_stress_core
#(
	parameter integer WORD_COUNT     = 262144,
	parameter integer POWERUP_CYCLES = 20000,
	parameter [5:0]   HALF_DIVIDER   = 6'd2,
	parameter [7:0]   GUARD_CYCLES   = 8'd8,
	parameter integer READ_LINE_BYTES = 16
)
(
	input              clk,
	input              reset,
	output      [1:0]  result_code,
	output      [7:0]  phase_code,
	output      [3:0]  pattern_id,
	output      [31:0] loop_count,
	output      [31:0] operation_count,
	output      [23:0] current_address,
	output      [31:0] expected_data,
	output      [31:0] actual_data,
	output      [31:0] xor_data,
	output      [3:0]  byte_mask,
	output      [15:0] device_id,
	output             init_done,
	output             init_error,
	output             failed,
	output             activity,
	output             PSRAM_CLK,
	output             PSRAM_CE_N,
	inout       [3:0]  PSRAM_DQ
);

wire [19:2] ramh_addr;
wire [31:0] ramh_din;
wire  [3:0] ramh_wr;
wire        ramh_rd;
wire        ramh_burst;
wire        ramh_rfs;
wire [31:0] ramh_dout;
wire        ramh_busy;
wire        adapter_error;

ramh_psram_adapter
#(
	.POWERUP_CYCLES(POWERUP_CYCLES),
	.HALF_DIVIDER(HALF_DIVIDER),
	.GUARD_CYCLES(GUARD_CYCLES),
	.READ_LINE_BYTES(READ_LINE_BYTES)
)
adapter
(
	.clk(clk),
	.reset(reset),
	.addr(ramh_addr),
	.din(ramh_din),
	.wr(ramh_wr),
	.rd(ramh_rd),
	.burst(ramh_burst),
	.dout(ramh_dout),
	.rfs(ramh_rfs),
	.busy(ramh_busy),
	.qpi_init_done(init_done),
	.qpi_init_error(init_error),
	.qpi_device_id(device_id),
	.adapter_error(adapter_error),
	.PSRAM_CLK(PSRAM_CLK),
	.PSRAM_CE_N(PSRAM_CE_N),
	.PSRAM_DQ(PSRAM_DQ)
);

ramh_psram_stress
#(
	.WORD_COUNT(WORD_COUNT)
)
tester
(
	.clk(clk),
	.reset(reset),
	.ramh_addr(ramh_addr),
	.ramh_din(ramh_din),
	.ramh_wr(ramh_wr),
	.ramh_rd(ramh_rd),
	.ramh_burst(ramh_burst),
	.ramh_rfs(ramh_rfs),
	.ramh_dout(ramh_dout),
	.ramh_busy(ramh_busy),
	.init_done(init_done),
	.init_error(init_error),
	.adapter_error(adapter_error),
	.result_code(result_code),
	.phase_code(phase_code),
	.pattern_id(pattern_id),
	.loop_count(loop_count),
	.operation_count(operation_count),
	.current_address(current_address),
	.expected_data(expected_data),
	.actual_data(actual_data),
	.xor_data(xor_data),
	.byte_mask(byte_mask),
	.failed(failed),
	.activity(activity)
);

endmodule


module ramh_psram_stress
#(
	parameter integer WORD_COUNT = 262144
)
(
	input              clk,
	input              reset,
	output reg [19:2]  ramh_addr,
	output reg [31:0]  ramh_din,
	output reg  [3:0]  ramh_wr,
	output reg         ramh_rd,
	output             ramh_burst,
	output             ramh_rfs,
	input      [31:0]  ramh_dout,
	input              ramh_busy,
	input              init_done,
	input              init_error,
	input              adapter_error,
	output      [1:0]  result_code,
	output      [7:0]  phase_code,
	output reg  [3:0]  pattern_id,
	output reg [31:0]  loop_count,
	output reg [31:0]  operation_count,
	output reg [23:0]  current_address,
	output reg [31:0]  expected_data,
	output reg [31:0]  actual_data,
	output reg [31:0]  xor_data,
	output reg  [3:0]  byte_mask,
	output reg         failed,
	output             activity
);

localparam [17:0] LAST_WORD = WORD_COUNT - 1;
localparam integer BYTE_STRIDE = (WORD_COUNT < 32) ? 1 : (WORD_COUNT / 32);
localparam integer CACHE_BASE_INT = ((WORD_COUNT / 2) & 32'hFFFFFFFC);

localparam [4:0] H_WAIT_INIT       = 5'd0;
localparam [4:0] H_PATTERN_WRITE   = 5'd1;
localparam [4:0] H_PATTERN_WRITE_W = 5'd2;
localparam [4:0] H_PATTERN_FWD     = 5'd3;
localparam [4:0] H_PATTERN_FWD_W   = 5'd4;
localparam [4:0] H_PATTERN_REV     = 5'd5;
localparam [4:0] H_PATTERN_REV_W   = 5'd6;
localparam [4:0] H_BYTE_BASE       = 5'd7;
localparam [4:0] H_BYTE_BASE_W     = 5'd8;
localparam [4:0] H_BYTE_PATCH      = 5'd9;
localparam [4:0] H_BYTE_PATCH_W    = 5'd10;
localparam [4:0] H_BYTE_READ       = 5'd11;
localparam [4:0] H_BYTE_READ_W     = 5'd12;
localparam [4:0] H_CACHE           = 5'd13;
localparam [4:0] H_CACHE_W         = 5'd14;
localparam [4:0] H_FAILED          = 5'd15;

localparam [1:0] T_IDLE  = 2'd0;
localparam [1:0] T_PULSE = 2'd1;
localparam [1:0] T_WAIT  = 2'd2;

reg [4:0] hstate;
reg [1:0] txn_state;
reg       txn_start;
reg       txn_done;
reg       cmd_read;
reg [17:0] cmd_address;
reg [31:0] cmd_data;
reg  [3:0] cmd_mask;
reg [17:0] word_index;
reg  [3:0] byte_mask_index;
reg  [4:0] cache_step;
reg  [7:0] failure_phase;

wire txn_ready = (txn_state == T_IDLE);
assign ramh_burst = 1'b0;
assign ramh_rfs = 1'b0;
assign result_code = failed ? 2'd2 : ((loop_count != 0) ? 2'd1 : 2'd0);
assign activity = operation_count[17];

function [31:0] mixed_address;
	input [17:0] index;
	reg [31:0] value;
	begin
		value = {14'd0, index} ^ 32'h6D2B79F5;
		value = value ^ (value << 13);
		value = value ^ (value >> 17);
		value = value ^ (value << 5);
		mixed_address = value;
	end
endfunction

function [31:0] pattern_value;
	input [3:0] pattern;
	input [17:0] index;
	reg [31:0] byte_address;
	begin
		byte_address = 32'h06000000 + {12'd0, index, 2'b00};
		case (pattern)
			4'd0: pattern_value = 32'h00000000;
			4'd1: pattern_value = 32'hFFFFFFFF;
			4'd2: pattern_value = 32'hA5A5A5A5;
			4'd3: pattern_value = 32'h5A5A5A5A;
			4'd4: pattern_value = byte_address;
			4'd5: pattern_value = ~byte_address;
			4'd6: pattern_value = mixed_address(index);
			4'd7: pattern_value = 32'h00000001 << index[4:0];
			default: pattern_value = ~(32'h00000001 << index[4:0]);
		endcase
	end
endfunction

function [17:0] byte_test_word;
	input [3:0] mask;
	begin
		byte_test_word = mask * BYTE_STRIDE;
	end
endfunction

function [31:0] byte_base_value;
	input [3:0] mask;
	begin
		byte_base_value = 32'h10203040 ^ {28'd0, mask};
	end
endfunction

function [31:0] byte_patch_value;
	input [3:0] mask;
	begin
		byte_patch_value = 32'hA1B2C3D4 ^ {24'd0, mask, mask};
	end
endfunction

function [31:0] merge_bytes;
	input [31:0] base_value;
	input [31:0] patch_value;
	input  [3:0] mask;
	reg [31:0] value;
	begin
		value = base_value;
		if (mask[3]) value[31:24] = patch_value[31:24];
		if (mask[2]) value[23:16] = patch_value[23:16];
		if (mask[1]) value[15:8]  = patch_value[15:8];
		if (mask[0]) value[7:0]   = patch_value[7:0];
		merge_bytes = value;
	end
endfunction

function cache_is_read;
	input [4:0] step;
	begin
		cache_is_read = (step >= 5) && (step != 9);
	end
endfunction

function [2:0] cache_offset;
	input [4:0] step;
	begin
		case (step)
			0, 5, 11: cache_offset = 3'd0;
			1, 6:     cache_offset = 3'd1;
			2, 7, 9, 10: cache_offset = 3'd2;
			3, 8, 13: cache_offset = 3'd3;
			default:  cache_offset = 3'd4;
		endcase
	end
endfunction

function [17:0] cache_word;
	input [4:0] step;
	begin
		cache_word = CACHE_BASE_INT + cache_offset(step);
	end
endfunction

function [31:0] cache_original_value;
	input [2:0] offset;
	begin
		cache_original_value = 32'hCAFE0000 ^ {29'd0, offset};
	end
endfunction

function [31:0] cache_value;
	input [4:0] step;
	begin
		if ((step == 9) || (step == 10)) cache_value = 32'h5AA55AA5;
		else cache_value = cache_original_value(cache_offset(step));
	end
endfunction

function [7:0] live_phase;
	input [4:0] state_value;
	begin
		case (state_value)
			H_WAIT_INIT: live_phase = 8'h00;
			H_PATTERN_WRITE,
			H_PATTERN_WRITE_W: live_phase = {4'h1, pattern_id};
			H_PATTERN_FWD,
			H_PATTERN_FWD_W: live_phase = {4'h2, pattern_id};
			H_PATTERN_REV,
			H_PATTERN_REV_W: live_phase = {4'h3, pattern_id};
			H_BYTE_BASE,
			H_BYTE_BASE_W,
			H_BYTE_PATCH,
			H_BYTE_PATCH_W,
			H_BYTE_READ,
			H_BYTE_READ_W: live_phase = 8'h40;
			H_CACHE,
			H_CACHE_W: live_phase = 8'h50;
			default: live_phase = 8'hFF;
		endcase
	end
endfunction

assign phase_code = failed ? failure_phase : live_phase(hstate);

// One-cycle RAMH request generator followed by a wait for adapter completion.
always @(posedge clk) begin
	if (reset) begin
		txn_state <= T_IDLE;
		txn_done  <= 1'b0;
		ramh_addr <= 18'd0;
		ramh_din  <= 32'd0;
		ramh_wr   <= 4'd0;
		ramh_rd   <= 1'b0;
	end
	else begin
		txn_done <= 1'b0;
		case (txn_state)
			T_IDLE: begin
				ramh_wr <= 4'd0;
				ramh_rd <= 1'b0;
				if (txn_start && !ramh_busy) begin
					ramh_addr <= cmd_address;
					ramh_din  <= cmd_data;
					ramh_wr   <= cmd_read ? 4'd0 : cmd_mask;
					ramh_rd   <= cmd_read;
					txn_state <= T_PULSE;
				end
			end
			T_PULSE: begin
				ramh_wr   <= 4'd0;
				ramh_rd   <= 1'b0;
				txn_state <= T_WAIT;
			end
			default: begin
				if (!ramh_busy) begin
					txn_done  <= 1'b1;
					txn_state <= T_IDLE;
				end
			end
		endcase
	end
end

always @(posedge clk) begin
	txn_start <= 1'b0;

	if (reset) begin
		hstate          <= H_WAIT_INIT;
		txn_start       <= 1'b0;
		cmd_read        <= 1'b0;
		cmd_address     <= 18'd0;
		cmd_data        <= 32'd0;
		cmd_mask        <= 4'd0;
		word_index      <= 18'd0;
		pattern_id      <= 4'd0;
		byte_mask_index <= 4'd1;
		cache_step      <= 5'd0;
		failure_phase   <= 8'd0;
		loop_count      <= 32'd0;
		operation_count <= 32'd0;
		current_address <= 24'd0;
		expected_data   <= 32'd0;
		actual_data     <= 32'd0;
		xor_data        <= 32'd0;
		byte_mask       <= 4'd0;
		failed          <= 1'b0;
	end
	else if (!failed && (init_error || adapter_error)) begin
		failed          <= 1'b1;
		failure_phase   <= 8'hE0;
		expected_data   <= 32'h00000D5D;
		actual_data     <= 32'd0;
		xor_data        <= 32'h00000D5D;
		hstate          <= H_FAILED;
	end
	else begin
		case (hstate)
			H_WAIT_INIT: begin
				if (init_done) begin
					word_index <= 18'd0;
					hstate <= H_PATTERN_WRITE;
				end
			end

			H_PATTERN_WRITE: if (txn_ready) begin
				cmd_read        <= 1'b0;
				cmd_address     <= word_index;
				cmd_data        <= pattern_value(pattern_id, word_index);
				cmd_mask        <= 4'hF;
				expected_data   <= pattern_value(pattern_id, word_index);
				current_address <= {4'd0, word_index, 2'b00};
				byte_mask       <= 4'hF;
				txn_start       <= 1'b1;
				hstate          <= H_PATTERN_WRITE_W;
			end

			H_PATTERN_WRITE_W: if (txn_done) begin
				operation_count <= operation_count + 1'b1;
				if (word_index == LAST_WORD) begin
					word_index <= 18'd0;
					hstate <= H_PATTERN_FWD;
				end
				else begin
					word_index <= word_index + 1'b1;
					hstate <= H_PATTERN_WRITE;
				end
			end

			H_PATTERN_FWD: if (txn_ready) begin
				cmd_read        <= 1'b1;
				cmd_address     <= word_index;
				cmd_data        <= 32'd0;
				cmd_mask        <= 4'd0;
				expected_data   <= pattern_value(pattern_id, word_index);
				current_address <= {4'd0, word_index, 2'b00};
				byte_mask       <= 4'd0;
				txn_start       <= 1'b1;
				hstate          <= H_PATTERN_FWD_W;
			end

			H_PATTERN_FWD_W: if (txn_done) begin
				operation_count <= operation_count + 1'b1;
				actual_data <= ramh_dout;
				xor_data    <= expected_data ^ ramh_dout;
				if (ramh_dout != expected_data) begin
					failed        <= 1'b1;
					failure_phase <= live_phase(hstate);
					hstate        <= H_FAILED;
				end
				else if (word_index == LAST_WORD) begin
					word_index <= LAST_WORD;
					hstate <= H_PATTERN_REV;
				end
				else begin
					word_index <= word_index + 1'b1;
					hstate <= H_PATTERN_FWD;
				end
			end

			H_PATTERN_REV: if (txn_ready) begin
				cmd_read        <= 1'b1;
				cmd_address     <= word_index;
				cmd_data        <= 32'd0;
				cmd_mask        <= 4'd0;
				expected_data   <= pattern_value(pattern_id, word_index);
				current_address <= {4'd0, word_index, 2'b00};
				byte_mask       <= 4'd0;
				txn_start       <= 1'b1;
				hstate          <= H_PATTERN_REV_W;
			end

			H_PATTERN_REV_W: if (txn_done) begin
				operation_count <= operation_count + 1'b1;
				actual_data <= ramh_dout;
				xor_data    <= expected_data ^ ramh_dout;
				if (ramh_dout != expected_data) begin
					failed        <= 1'b1;
					failure_phase <= live_phase(hstate);
					hstate        <= H_FAILED;
				end
				else if (word_index == 0) begin
					if (pattern_id == 4'd8) begin
						byte_mask_index <= 4'd1;
						hstate <= H_BYTE_BASE;
					end
					else begin
						pattern_id <= pattern_id + 1'b1;
						word_index <= 18'd0;
						hstate <= H_PATTERN_WRITE;
					end
				end
				else begin
					word_index <= word_index - 1'b1;
					hstate <= H_PATTERN_REV;
				end
			end

			H_BYTE_BASE: if (txn_ready) begin
				cmd_read        <= 1'b0;
				cmd_address     <= byte_test_word(byte_mask_index);
				cmd_data        <= byte_base_value(byte_mask_index);
				cmd_mask        <= 4'hF;
				expected_data   <= byte_base_value(byte_mask_index);
				current_address <= {4'd0, byte_test_word(byte_mask_index), 2'b00};
				byte_mask       <= 4'hF;
				txn_start       <= 1'b1;
				hstate          <= H_BYTE_BASE_W;
			end

			H_BYTE_BASE_W: if (txn_done) begin
				operation_count <= operation_count + 1'b1;
				hstate <= H_BYTE_PATCH;
			end

			H_BYTE_PATCH: if (txn_ready) begin
				cmd_read        <= 1'b0;
				cmd_address     <= byte_test_word(byte_mask_index);
				cmd_data        <= byte_patch_value(byte_mask_index);
				cmd_mask        <= byte_mask_index;
				expected_data   <= merge_bytes(byte_base_value(byte_mask_index),
				                               byte_patch_value(byte_mask_index),
				                               byte_mask_index);
				current_address <= {4'd0, byte_test_word(byte_mask_index), 2'b00};
				byte_mask       <= byte_mask_index;
				txn_start       <= 1'b1;
				hstate          <= H_BYTE_PATCH_W;
			end

			H_BYTE_PATCH_W: if (txn_done) begin
				operation_count <= operation_count + 1'b1;
				hstate <= H_BYTE_READ;
			end

			H_BYTE_READ: if (txn_ready) begin
				cmd_read        <= 1'b1;
				cmd_address     <= byte_test_word(byte_mask_index);
				cmd_data        <= 32'd0;
				cmd_mask        <= 4'd0;
				expected_data   <= merge_bytes(byte_base_value(byte_mask_index),
				                               byte_patch_value(byte_mask_index),
				                               byte_mask_index);
				current_address <= {4'd0, byte_test_word(byte_mask_index), 2'b00};
				byte_mask       <= byte_mask_index;
				txn_start       <= 1'b1;
				hstate          <= H_BYTE_READ_W;
			end

			H_BYTE_READ_W: if (txn_done) begin
				operation_count <= operation_count + 1'b1;
				actual_data <= ramh_dout;
				xor_data    <= expected_data ^ ramh_dout;
				if (ramh_dout != expected_data) begin
					failed        <= 1'b1;
					failure_phase <= live_phase(hstate);
					hstate        <= H_FAILED;
				end
				else if (byte_mask_index == 4'hF) begin
					cache_step <= 5'd0;
					hstate <= H_CACHE;
				end
				else begin
					byte_mask_index <= byte_mask_index + 1'b1;
					hstate <= H_BYTE_BASE;
				end
			end

			H_CACHE: if (txn_ready) begin
				cmd_read        <= cache_is_read(cache_step);
				cmd_address     <= cache_word(cache_step);
				cmd_data        <= cache_value(cache_step);
				cmd_mask        <= cache_is_read(cache_step) ? 4'd0 : 4'hF;
				expected_data   <= cache_value(cache_step);
				current_address <= {4'd0, cache_word(cache_step), 2'b00};
				byte_mask       <= cache_is_read(cache_step) ? 4'd0 : 4'hF;
				txn_start       <= 1'b1;
				hstate          <= H_CACHE_W;
			end

			H_CACHE_W: if (txn_done) begin
				operation_count <= operation_count + 1'b1;
				if (cache_is_read(cache_step)) begin
					actual_data <= ramh_dout;
					xor_data    <= expected_data ^ ramh_dout;
				end
				if (cache_is_read(cache_step) && (ramh_dout != expected_data)) begin
					failed        <= 1'b1;
					failure_phase <= live_phase(hstate);
					hstate        <= H_FAILED;
				end
				else if (cache_step == 5'd13) begin
					loop_count <= loop_count + 1'b1;
					pattern_id <= 4'd0;
					word_index <= 18'd0;
					hstate <= H_PATTERN_WRITE;
				end
				else begin
					cache_step <= cache_step + 1'b1;
					hstate <= H_CACHE;
				end
			end

			default: hstate <= H_FAILED;
		endcase
	end
end

endmodule
