`timescale 1ns/1ps

module tb_ramh_psram_random;

localparam integer TEST_BASE   = 16'h4000;
localparam integer TEST_BYTES  = 16'h4000;
localparam integer TEST_WORDS  = TEST_BYTES / 4;
localparam integer RANDOM_OPS  = 10000;
localparam integer BURST_LINES = 256;

reg clk = 1'b0;
always #5 clk = ~clk;

reg reset = 1'b1;
reg [19:2] addr = '0;
reg [31:0] din = 32'd0;
reg [3:0] wr = 4'd0;
reg rd = 1'b0;
reg burst = 1'b0;
reg rfs = 1'b0;
wire [31:0] dout;
wire busy;
wire init_done;
wire init_error;
wire [15:0] device_id;
wire adapter_error;
wire psram_clk;
wire psram_ce_n;
wire [3:0] psram_dq;

ramh_psram_adapter
#(
	.POWERUP_CYCLES(6),
	.HALF_DIVIDER(6'd2),
	.GUARD_CYCLES(8'd8)
)
dut
(
	.clk(clk),
	.reset(reset),
	.addr(addr),
	.din(din),
	.wr(wr),
	.rd(rd),
	.burst(burst),
	.dout(dout),
	.rfs(rfs),
	.busy(busy),
	.qpi_init_done(init_done),
	.qpi_init_error(init_error),
	.qpi_device_id(device_id),
	.adapter_error(adapter_error),
	.PSRAM_CLK(psram_clk),
	.PSRAM_CE_N(psram_ce_n),
	.PSRAM_DQ(psram_dq)
);

reg [7:0] reference_memory [0:TEST_BYTES-1];
reg       reference_cache_valid;
reg [15:0] reference_cache_tag;
reg [15:0] mask_coverage;
reg [31:0] rng;

integer read_count;
integer write_count;
integer hit_count;
integer miss_count;
integer reset_count;
integer rfs_count;
integer operation_index;
integer line_index;
integer word_index;
integer byte_index;
integer mask_index;
integer before_requests;
integer expected_runs;
integer timeout;
reg [19:0] byte_address;
reg [31:0] random_data;
reg [3:0] random_mask;

function [31:0] next_random;
	input [31:0] value;
	reg [31:0] x;
	begin
		x = value;
		x = x ^ (x << 13);
		x = x ^ (x >> 17);
		x = x ^ (x << 5);
		next_random = x;
	end
endfunction

function [31:0] expected_word;
	input [19:0] absolute_address;
	integer index;
	begin
		index = absolute_address - TEST_BASE;
		expected_word = {reference_memory[index + 0],
		                 reference_memory[index + 1],
		                 reference_memory[index + 2],
		                 reference_memory[index + 3]};
	end
endfunction

function integer write_run_count;
	input [3:0] mask;
	begin
		write_run_count = mask[3] +
		                  (mask[2] && !mask[3]) +
		                  (mask[1] && !mask[2]) +
		                  (mask[0] && !mask[1]);
	end
endfunction

task wait_for_initialization;
	begin
		timeout = 0;
		while (!init_done && !init_error && timeout < 10000) begin
			@(posedge clk);
			#1;
			timeout = timeout + 1;
		end
		if (!init_done || init_error || adapter_error ||
		    device_id !== 16'h0D5D)
			$fatal(1, "FAIL: initialization done=%0d init_error=%0d adapter_error=%0d id=%04h",
			       init_done, init_error, adapter_error, device_id);
	end
endtask

task read_checked;
	input [19:0] absolute_address;
	reg [31:0] expected;
	reg expected_hit;
	begin
		expected = expected_word(absolute_address);
		expected_hit = reference_cache_valid &&
		               (reference_cache_tag == absolute_address[19:4]);
		before_requests = dut.engine.accepted_count;

		@(negedge clk);
		addr = absolute_address[19:2];
		rd = 1'b1;
		@(posedge clk);
		#1;
		timeout = 0;
		while (busy && timeout < 10000) begin
			@(posedge clk);
			#1;
			timeout = timeout + 1;
		end
		if (busy || adapter_error)
			$fatal(1, "FAIL: read timeout address=%05h", absolute_address);
		if (dout !== expected)
			$fatal(1, "FAIL: read address=%05h actual=%08h expected=%08h op=%0d",
			       absolute_address, dout, expected, operation_index);
		if (dut.engine.accepted_count != before_requests +
		    (expected_hit ? 0 : 1))
			$fatal(1, "FAIL: read request count address=%05h hit=%0d delta=%0d",
			       absolute_address, expected_hit,
			       dut.engine.accepted_count - before_requests);

		if (expected_hit) hit_count = hit_count + 1;
		else begin
			miss_count = miss_count + 1;
			reference_cache_valid = 1'b1;
			reference_cache_tag = absolute_address[19:4];
		end
		read_count = read_count + 1;

		@(negedge clk);
		rd = 1'b0;
		@(posedge clk);
	end
endtask

task write_checked;
	input [19:0] absolute_address;
	input [31:0] value;
	input [3:0] mask;
	integer index;
	begin
		expected_runs = write_run_count(mask);
		before_requests = dut.engine.accepted_count;

		@(negedge clk);
		addr = absolute_address[19:2];
		din = value;
		wr = mask;
		@(posedge clk);
		#1;
		timeout = 0;
		while (busy && timeout < 10000) begin
			@(posedge clk);
			#1;
			timeout = timeout + 1;
		end
		if (busy || adapter_error)
			$fatal(1, "FAIL: write timeout address=%05h mask=%b",
			       absolute_address, mask);
		if (dut.engine.accepted_count != before_requests + expected_runs)
			$fatal(1, "FAIL: write request count address=%05h mask=%b delta=%0d expected=%0d",
			       absolute_address, mask,
			       dut.engine.accepted_count - before_requests,
			       expected_runs);

		@(negedge clk);
		wr = 4'd0;
		@(posedge clk);

		index = absolute_address - TEST_BASE;
		if (mask[3]) reference_memory[index + 0] = value[31:24];
		if (mask[2]) reference_memory[index + 1] = value[23:16];
		if (mask[1]) reference_memory[index + 2] = value[15:8];
		if (mask[0]) reference_memory[index + 3] = value[7:0];
		if (reference_cache_valid &&
		    reference_cache_tag == absolute_address[19:4])
			reference_cache_valid = 1'b0;
		mask_coverage[mask] = 1'b1;
		write_count = write_count + 1;
	end
endtask

task pulse_rfs;
	begin
		before_requests = dut.engine.accepted_count;
		@(negedge clk);
		rfs = 1'b1;
		repeat (3) @(posedge clk);
		@(negedge clk);
		rfs = 1'b0;
		if (busy || dut.engine.accepted_count != before_requests)
			$fatal(1, "FAIL: RFS created busy or a memory request");
		rfs_count = rfs_count + 1;
	end
endtask

task reset_adapter;
	begin
		before_requests = dut.engine.accepted_count;
		@(negedge clk);
		reset = 1'b1;
		rd = 1'b0;
		wr = 4'd0;
		repeat (4) @(posedge clk);
		#1;
		if (!busy) $fatal(1, "FAIL: busy low during reset");
		@(negedge clk);
		reset = 1'b0;
		wait_for_initialization();
		if (dut.engine.accepted_count != before_requests)
			$fatal(1, "FAIL: reset generated a runtime request");
		reference_cache_valid = 1'b0;
		reset_count = reset_count + 1;
	end
endtask

initial begin
	rng = 32'h1A2B3C4D;
	if ($value$plusargs("SEED=%h", rng))
		$display("INFO: S2-C random seed=%08h", rng);
	reference_cache_valid = 1'b0;
	reference_cache_tag = 16'd0;
	mask_coverage = 16'd0;
	read_count = 0;
	write_count = 0;
	hit_count = 0;
	miss_count = 0;
	reset_count = 0;
	rfs_count = 0;
	operation_index = 0;

	for (byte_index = 0; byte_index < TEST_BYTES;
	     byte_index = byte_index + 1) begin
		reference_memory[byte_index] =
			((byte_index * 73) + (byte_index >> 3) + 8'h5A) & 8'hFF;
		dut.engine.memory[TEST_BASE + byte_index] =
			reference_memory[byte_index];
	end

	repeat (5) @(posedge clk);
	reset = 1'b0;
	wait_for_initialization();

	// Force coverage of every legal write mask before randomized traffic.
	for (mask_index = 1; mask_index < 16; mask_index = mask_index + 1) begin
		operation_index = operation_index + 1;
		byte_address = TEST_BASE + ((mask_index * 4) & (TEST_BYTES - 4));
		rng = next_random(rng);
		write_checked(byte_address, rng, mask_index[3:0]);
		read_checked(byte_address);
	end

	// Explicit four-word line walks guarantee both misses and cache hits.
	for (line_index = 0; line_index < BURST_LINES;
	     line_index = line_index + 1) begin
		rng = next_random(rng);
		byte_address = TEST_BASE + ((rng % (TEST_BYTES / 16)) << 4);
		for (word_index = 0; word_index < 4;
		     word_index = word_index + 1) begin
			operation_index = operation_index + 1;
			read_checked(byte_address + (word_index << 2));
		end
	end

	for (operation_index = operation_index;
	     operation_index < RANDOM_OPS;
	     operation_index = operation_index + 1) begin
		rng = next_random(rng);
		word_index = rng % TEST_WORDS;
		byte_address = TEST_BASE + (word_index << 2);

		rng = next_random(rng);
		if (rng[2:0] < 3) begin
			random_mask = (rng[7:4] % 15) + 1;
			rng = next_random(rng);
			random_data = rng;
			write_checked(byte_address, random_data, random_mask);
		end
		else read_checked(byte_address);

		if ((operation_index != 0) &&
		    ((operation_index % 997) == 0)) pulse_rfs();
		if ((operation_index == 3000) ||
		    (operation_index == 6000) ||
		    (operation_index == 9000)) begin
			reset_adapter();
			read_checked(byte_address);
		end
	end

	// Final full-range sweep proves persistent memory agrees after the entire
	// mixed sequence and three controller resets.
	for (word_index = 0; word_index < TEST_WORDS;
	     word_index = word_index + 1) begin
		operation_index = operation_index + 1;
		read_checked(TEST_BASE + (word_index << 2));
	end

	if (mask_coverage[15:1] !== 15'h7FFF)
		$fatal(1, "FAIL: write mask coverage=%04h", mask_coverage);
	if ((hit_count == 0) || (miss_count == 0) ||
	    (read_count < 10000) || (write_count < 1000) ||
	    (reset_count != 3) || (rfs_count == 0))
		$fatal(1, "FAIL: insufficient coverage reads=%0d writes=%0d hits=%0d misses=%0d resets=%0d rfs=%0d",
		       read_count, write_count, hit_count, miss_count,
		       reset_count, rfs_count);

	$display("PASS: S2-C randomized RAMH regression ops=%0d reads=%0d writes=%0d hits=%0d misses=%0d resets=%0d rfs=%0d requests=%0d",
	         operation_index, read_count, write_count, hit_count, miss_count,
	         reset_count, rfs_count, dut.engine.accepted_count);
	$finish;
end

initial begin
	#200000000;
	$display("FAIL: global timeout");
	$fatal;
end

endmodule
