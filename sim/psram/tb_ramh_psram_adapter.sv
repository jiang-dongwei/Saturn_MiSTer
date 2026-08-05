`timescale 1ns/1ps

module tb_ramh_psram_adapter;

reg clk = 1'b0;
always #4.365 clk = ~clk;

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
	.POWERUP_CYCLES(4),
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

psram_diag_model
#(
	.READ_OUTPUT_DELAY_NS(16)
)
memory
(
	.ce_n(psram_ce_n),
	.sclk(psram_clk),
	.dq(psram_dq)
);

integer transaction_count = 0;
always @(negedge psram_ce_n) transaction_count = transaction_count + 1;

task read_word;
	input [19:0] byte_address;
	output [31:0] value;
	integer timeout;
	begin
		@(negedge clk);
		addr = byte_address[19:2];
		rd = 1'b1;
		@(posedge clk);
		#1;
		timeout = 0;
		while (busy && timeout < 100000) begin
			@(posedge clk);
			#1;
			timeout = timeout + 1;
		end
		if (busy || adapter_error) begin
			$display("FAIL: RAMH read timed out at %05h", byte_address);
			$fatal;
		end
		value = dout;
		@(negedge clk);
		rd = 1'b0;
		@(posedge clk);
	end
endtask

task write_word;
	input [19:0] byte_address;
	input [31:0] value;
	input [3:0] byte_enable;
	integer timeout;
	begin
		@(negedge clk);
		addr = byte_address[19:2];
		din = value;
		wr = byte_enable;
		@(posedge clk);
		#1;
		timeout = 0;
		while (busy && timeout < 100000) begin
			@(posedge clk);
			#1;
			timeout = timeout + 1;
		end
		if (busy || adapter_error) begin
			$display("FAIL: RAMH write timed out at %05h mask=%b",
			         byte_address, byte_enable);
			$fatal;
		end
		@(negedge clk);
		wr = 4'd0;
		@(posedge clk);
	end
endtask

reg [31:0] value;
reg [31:0] expected_value;
integer before_count;
integer init_timeout;
integer mask_index;
integer expected_runs;

initial begin
	// Two adjacent 16-byte lines, stored in CPU-visible big-endian order.
	memory.memory[20'h00100] = 8'hD1;
	memory.memory[20'h00101] = 8'h5E;
	memory.memory[20'h00102] = 8'hA5;
	memory.memory[20'h00103] = 8'hC3;
	memory.memory[20'h00104] = 8'h11;
	memory.memory[20'h00105] = 8'h22;
	memory.memory[20'h00106] = 8'h33;
	memory.memory[20'h00107] = 8'h44;
	memory.memory[20'h00108] = 8'h55;
	memory.memory[20'h00109] = 8'h66;
	memory.memory[20'h0010A] = 8'h77;
	memory.memory[20'h0010B] = 8'h88;
	memory.memory[20'h0010C] = 8'h99;
	memory.memory[20'h0010D] = 8'hAA;
	memory.memory[20'h0010E] = 8'hBB;
	memory.memory[20'h0010F] = 8'hCC;
	memory.memory[20'h00110] = 8'h01;
	memory.memory[20'h00111] = 8'h23;
	memory.memory[20'h00112] = 8'h45;
	memory.memory[20'h00113] = 8'h67;

	// Hold a RAMH read active before PSRAM initialization completes. busy must
	// remain asserted and the request must be serviced after init_done.
	addr = 20'h00100 >> 2;
	rd = 1'b1;
	repeat (6) @(posedge clk);
	reset = 1'b0;
	#1;
	if (!busy) $fatal(1, "FAIL: busy dropped before PSRAM initialization");

	init_timeout = 0;
	while (!init_done && !init_error && init_timeout < 100000) begin
		@(posedge clk);
		#1;
		if (!init_done && !busy)
			$fatal(1, "FAIL: busy dropped during PSRAM initialization");
		init_timeout = init_timeout + 1;
	end
	if (!init_done || init_error || adapter_error || device_id !== 16'h0D5D) begin
		$display("FAIL: adapter initialization id=%04h done=%0d init_error=%0d adapter_error=%0d",
		         device_id, init_done, init_error, adapter_error);
		$fatal;
	end

	init_timeout = 0;
	while (busy && init_timeout < 100000) begin
		@(posedge clk);
		#1;
		init_timeout = init_timeout + 1;
	end
	if (busy || dout !== 32'hD15EA5C3)
		$fatal(1, "FAIL: held initialization read value=%08h busy=%0d", dout, busy);
	@(negedge clk);
	rd = 1'b0;
	@(posedge clk);

	// Three other words in the same line must not create more traffic.
	before_count = transaction_count;
	read_word(20'h00104, value);
	if (value !== 32'h11223344) $fatal(1, "FAIL: cached word1 %08h", value);
	read_word(20'h00108, value);
	if (value !== 32'h55667788) $fatal(1, "FAIL: cached word2 %08h", value);
	read_word(20'h0010C, value);
	if (value !== 32'h99AABBCC) $fatal(1, "FAIL: cached word3 %08h", value);
	if (transaction_count != before_count) begin
		$display("FAIL: cache hits created %0d transactions",
		         transaction_count - before_count);
		$fatal;
	end

	// A full-word write is one QPI transaction and invalidates the line.
	before_count = transaction_count;
	write_word(20'h00108, 32'hA1B2C3D4, 4'b1111);
	if (transaction_count != before_count + 1)
		$fatal(1, "FAIL: full write transaction count");
	read_word(20'h00108, value);
	if (value !== 32'hA1B2C3D4)
		$fatal(1, "FAIL: full write/readback %08h", value);

	// A non-contiguous mask becomes two direct write runs.
	before_count = transaction_count;
	write_word(20'h00104, 32'hDEADBEEF, 4'b1010);
	if (transaction_count != before_count + 2)
		$fatal(1, "FAIL: split write transaction count");
	read_word(20'h00104, value);
	if (value !== 32'hDE22BE44)
		$fatal(1, "FAIL: split masked write/readback %08h", value);

	// Two adjacent byte enables are coalesced into one QPI transaction.
	before_count = transaction_count;
	write_word(20'h00104, 32'hABCDEF01, 4'b0110);
	if (transaction_count != before_count + 1)
		$fatal(1, "FAIL: contiguous write transaction count");
	read_word(20'h00104, value);
	if (value !== 32'hDECDEF44)
		$fatal(1, "FAIL: contiguous masked write/readback %08h", value);

	// A different line must replace the single cache line.
	before_count = transaction_count;
	read_word(20'h00110, value);
	if (value !== 32'h01234567 || transaction_count != before_count + 1)
		$fatal(1, "FAIL: second line fill %08h", value);

	// Exhaustively cover all 15 nonzero byte-enable masks. The adapter must
	// preserve disabled bytes and coalesce each contiguous run.
	for (mask_index = 1; mask_index < 16; mask_index = mask_index + 1) begin
		memory.memory[20'h00120] = 8'h10;
		memory.memory[20'h00121] = 8'h20;
		memory.memory[20'h00122] = 8'h30;
		memory.memory[20'h00123] = 8'h40;

		expected_runs = mask_index[3] +
		                (mask_index[2] && !mask_index[3]) +
		                (mask_index[1] && !mask_index[2]) +
		                (mask_index[0] && !mask_index[1]);
		before_count = transaction_count;
		write_word(20'h00120, 32'hA1B2C3D4, mask_index[3:0]);
		if (transaction_count != before_count + expected_runs) begin
			$display("FAIL: mask %b used %0d transactions, expected %0d",
			         mask_index[3:0], transaction_count - before_count,
			         expected_runs);
			$fatal;
		end

		read_word(20'h00120, value);
		expected_value = {mask_index[3] ? 8'hA1 : 8'h10,
		                  mask_index[2] ? 8'hB2 : 8'h20,
		                  mask_index[1] ? 8'hC3 : 8'h30,
		                  mask_index[0] ? 8'hD4 : 8'h40};
		if (value !== expected_value) begin
			$display("FAIL: mask %b readback=%08h expected=%08h",
			         mask_index[3:0], value, expected_value);
			$fatal;
		end
	end

	// SDRAM refresh requests are deliberately no-ops for PSRAM.
	before_count = transaction_count;
	@(negedge clk);
	rfs = 1'b1;
	repeat (3) @(posedge clk);
	@(negedge clk);
	rfs = 1'b0;
	if (transaction_count != before_count || busy)
		$fatal(1, "FAIL: rfs generated PSRAM traffic or busy");

	$display("PASS: S2-B RAMH adapter line fill/hit, endian mapping, direct writes, invalidation, and RFS no-op");
	$finish;
end

initial begin
	#10000000;
	$display("FAIL: global timeout");
	$fatal;
end

endmodule
