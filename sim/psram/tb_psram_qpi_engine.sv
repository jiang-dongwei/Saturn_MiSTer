`timescale 1ns/1ps

module tb_psram_qpi_engine;

reg clk = 1'b0;
always #4.365 clk = ~clk; // 114.547 MHz, representative Saturn clk_ram

reg reset = 1'b1;
reg request_valid = 1'b0;
wire request_ready;
reg request_write = 1'b0;
reg [23:0] request_address = 24'd0;
reg [4:0] request_bytes = 5'd0;
reg [127:0] request_write_data = 128'd0;
wire [127:0] request_read_data;
wire request_done;
wire request_error;
wire init_done;
wire init_error;
wire [15:0] device_id;
wire busy;
wire psram_clk;
wire psram_ce_n;
wire [3:0] psram_dq;

psram_qpi_engine
#(
	.POWERUP_CYCLES(8),
	.HALF_DIVIDER(6'd2),
	.GUARD_CYCLES(8)
)
dut
(
	.clk(clk),
	.reset(reset),
	.request_valid(request_valid),
	.request_ready(request_ready),
	.request_write(request_write),
	.request_address(request_address),
	.request_bytes(request_bytes),
	.request_write_data(request_write_data),
	.request_read_data(request_read_data),
	.request_done(request_done),
	.request_error(request_error),
	.init_done(init_done),
	.init_error(init_error),
	.device_id(device_id),
	.busy(busy),
	.PSRAM_CLK(psram_clk),
	.PSRAM_CE_N(psram_ce_n),
	.PSRAM_DQ(psram_dq)
);

psram_diag_model
#(
	// Deliberately longer than the device's nominal output delay. At the
	// selected clk_ram/divider-2 rate this exercises the complete input window.
	.READ_OUTPUT_DELAY_NS(16)
)
memory
(
	.ce_n(psram_ce_n),
	.sclk(psram_clk),
	.dq(psram_dq)
);

wire bad_id_init_done;
wire bad_id_init_error;
wire [15:0] bad_id_device_id;
wire bad_id_clk;
wire bad_id_ce_n;
wire [3:0] bad_id_dq;

psram_qpi_engine
#(
	.POWERUP_CYCLES(8),
	.HALF_DIVIDER(6'd2),
	.GUARD_CYCLES(8)
)
dut_bad_id
(
	.clk(clk),
	.reset(reset),
	.request_valid(1'b0),
	.request_ready(),
	.request_write(1'b0),
	.request_address(24'd0),
	.request_bytes(5'd0),
	.request_write_data(128'd0),
	.request_read_data(),
	.request_done(),
	.request_error(),
	.init_done(bad_id_init_done),
	.init_error(bad_id_init_error),
	.device_id(bad_id_device_id),
	.busy(),
	.PSRAM_CLK(bad_id_clk),
	.PSRAM_CE_N(bad_id_ce_n),
	.PSRAM_DQ(bad_id_dq)
);

psram_diag_model #(.ID_VALUE(48'd0)) memory_bad_id
(
	.ce_n(bad_id_ce_n),
	.sclk(bad_id_clk),
	.dq(bad_id_dq)
);

realtime last_clock_edge;
realtime last_ce_rise;
realtime last_ce_fall;
reg have_clock_edge = 1'b0;
reg have_ce_rise = 1'b0;
integer transaction_count = 0;

always @(negedge psram_ce_n) begin
	last_ce_fall = $realtime;
	have_clock_edge = 1'b0;
	transaction_count = transaction_count + 1;
	if (have_ce_rise && (($realtime - last_ce_rise) < 60.0)) begin
		$display("FAIL: CE# high gap was only %0.3f ns", $realtime - last_ce_rise);
		$fatal;
	end
end

always @(posedge psram_ce_n) begin
	last_ce_rise = $realtime;
	have_ce_rise = 1'b1;
	if (($realtime - last_ce_fall) > 8000.0) begin
		$display("FAIL: CE# remained low for %0.3f ns", $realtime - last_ce_fall);
		$fatal;
	end
	if (have_clock_edge && (($realtime - last_clock_edge) < 60.0)) begin
		$display("FAIL: CE# hold after final clock was only %0.3f ns",
		         $realtime - last_clock_edge);
		$fatal;
	end
end

always @(posedge psram_clk or negedge psram_clk) begin
	if (!psram_ce_n) begin
		if (have_clock_edge) begin
			if ((($realtime - last_clock_edge) < 17.35) ||
			    (($realtime - last_clock_edge) > 17.60)) begin
				$display("FAIL: QPI half-period was %0.3f ns", $realtime - last_clock_edge);
				$fatal;
			end
		end
		last_clock_edge = $realtime;
		have_clock_edge = 1'b1;
	end
end

task issue_write;
	input [23:0] address_value;
	input [4:0] byte_count;
	input [127:0] data_value;
	integer timeout;
	begin
		timeout = 0;
		while (!request_ready && timeout < 100000) begin
			@(posedge clk);
			timeout = timeout + 1;
		end
		if (!request_ready) begin
			$display("FAIL: write request never became ready");
			$fatal;
		end

		@(negedge clk);
		request_write      = 1'b1;
		request_address    = address_value;
		request_bytes      = byte_count;
		request_write_data = data_value;
		request_valid      = 1'b1;
		@(negedge clk);
		request_valid      = 1'b0;

		timeout = 0;
		while (!request_done && timeout < 100000) begin
			@(posedge clk);
			timeout = timeout + 1;
		end
		if (!request_done || request_error) begin
			$display("FAIL: write transaction failed at %06h", address_value);
			$fatal;
		end
	end
endtask

task issue_read;
	input [23:0] address_value;
	input [4:0] byte_count;
	output [127:0] data_value;
	integer timeout;
	begin
		timeout = 0;
		while (!request_ready && timeout < 100000) begin
			@(posedge clk);
			timeout = timeout + 1;
		end
		if (!request_ready) begin
			$display("FAIL: read request never became ready");
			$fatal;
		end

		@(negedge clk);
		request_write      = 1'b0;
		request_address    = address_value;
		request_bytes      = byte_count;
		request_write_data = 128'd0;
		request_valid      = 1'b1;
		@(negedge clk);
		request_valid      = 1'b0;

		timeout = 0;
		while (!request_done && timeout < 100000) begin
			@(posedge clk);
			timeout = timeout + 1;
		end
		if (!request_done || request_error) begin
			$display("FAIL: read transaction failed at %06h", address_value);
			$fatal;
		end
		data_value = request_read_data;
	end
endtask

task issue_invalid_zero_length;
	integer timeout;
	integer transactions_before;
	begin
		timeout = 0;
		while (!request_ready && timeout < 100000) begin
			@(posedge clk);
			timeout = timeout + 1;
		end
		if (!request_ready) begin
			$display("FAIL: invalid request never became ready");
			$fatal;
		end

		transactions_before = transaction_count;
		@(negedge clk);
		request_write      = 1'b0;
		request_address    = 24'h000200;
		request_bytes      = 5'd0;
		request_write_data = 128'd0;
		request_valid      = 1'b1;
		@(negedge clk);
		request_valid      = 1'b0;

		timeout = 0;
		while (!request_done && timeout < 1000) begin
			@(posedge clk);
			timeout = timeout + 1;
		end
		if (!request_done || !request_error) begin
			$display("FAIL: zero-length request was not rejected");
			$fatal;
		end
		if (transaction_count != transactions_before) begin
			$display("FAIL: rejected request still generated CE# activity");
			$fatal;
		end
	end
endtask

reg [127:0] readback;
integer init_timeout;

initial begin
	repeat (6) @(posedge clk);
	reset = 1'b0;

	init_timeout = 0;
	while (!init_done && !init_error && init_timeout < 100000) begin
		@(posedge clk);
		init_timeout = init_timeout + 1;
	end
	if (!init_done || init_error) begin
		$display("FAIL: initialization did not complete, id=%04h", device_id);
		$fatal;
	end
	if (device_id !== 16'h0D5D || !memory.qpi_mode) begin
		$display("FAIL: initialization mismatch id=%04h qpi=%0d",
		         device_id, memory.qpi_mode);
		$fatal;
	end
	if (!bad_id_init_error || bad_id_init_done ||
	    bad_id_device_id !== 16'h0000) begin
		$display("FAIL: bad-ID engine was not rejected, done=%0d error=%0d id=%04h",
		         bad_id_init_done, bad_id_init_error, bad_id_device_id);
		$fatal;
	end

	issue_invalid_zero_length();

	issue_write(24'h000100, 5'd4, 128'h000000000000000000000000D15EA5C3);
	issue_read (24'h000100, 5'd4, readback);
	if (readback[31:0] !== 32'hD15EA5C3) begin
		$display("FAIL: 4-byte readback %08h", readback[31:0]);
		$fatal;
	end

	issue_write(24'h000110, 5'd16,
	            128'h00112233445566778899AABBCCDDEEFF);
	issue_read (24'h000110, 5'd16, readback);
	if (readback !== 128'h00112233445566778899AABBCCDDEEFF) begin
		$display("FAIL: 16-byte readback %032h", readback);
		$fatal;
	end

	issue_write(24'h000115, 5'd1,
	            128'h000000000000000000000000000000A7);
	issue_read (24'h000110, 5'd16, readback);
	if (readback !== 128'h0011223344A766778899AABBCCDDEEFF) begin
		$display("FAIL: 1-byte update readback %032h", readback);
		$fatal;
	end

	issue_write(24'h00011E, 5'd2,
	            128'h00000000000000000000000000005AC3);
	issue_read (24'h00011E, 5'd2, readback);
	if (readback[15:0] !== 16'h5AC3) begin
		$display("FAIL: 2-byte readback %04h", readback[15:0]);
		$fatal;
	end

	if (transaction_count < 13) begin
		$display("FAIL: only %0d CE# transactions observed", transaction_count);
		$fatal;
	end

	$display("PASS: S2-A runtime QPI engine initialized ID=%04h and passed 1/2/4/16-byte transfers",
	         device_id);
	$finish;
end

initial begin
	#5000000;
	$display("FAIL: global simulation timeout");
	$fatal;
end

endmodule
