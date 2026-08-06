`timescale 1ns/1ps

// Transaction-level replacement for psram_qpi_engine used only by the
// long-running RAMH adapter regression. It deliberately adds variable
// completion latency. The testbench keeps a separate reference memory.
module psram_qpi_engine
#(
	parameter integer POWERUP_CYCLES = 8,
	parameter [5:0]   HALF_DIVIDER   = 6'd2,
	parameter [7:0]   GUARD_CYCLES   = 8'd8,
	parameter integer DIRECT_READ_CAPTURE = 0
)
(
	input              clk,
	input              reset,
	input              request_valid,
	output             request_ready,
	input              request_write,
	input      [23:0]  request_address,
	input       [4:0]  request_bytes,
	input       [31:0] request_write_data,
	output reg [127:0] request_read_data,
	output reg         request_done,
	output reg         request_error,
	output reg         init_done,
	output reg         init_error,
	output reg [15:0]  device_id,
	output             busy,
	output             PSRAM_CLK,
	output             PSRAM_CE_N,
	inout       [3:0]  PSRAM_DQ
);

reg [7:0] memory [0:65535];
integer accepted_count = 0;
integer write_accepted_count = 0;
integer dropped_write_count = 0;

reg [31:0] power_count;
reg        active;
reg  [3:0] latency_count;
reg [31:0] lfsr;
reg        saved_write;
reg [23:0] saved_address;
reg  [4:0] saved_bytes;
reg [31:0] saved_write_data;
reg [127:0] read_temp;
integer byte_index;

// Testbench-only fault hook. It defaults to zero and therefore leaves all
// existing S2 regressions unchanged. The stress-core testbench can set it
// hierarchically to emulate an address-line/read-decoder fault.
reg [23:0] read_address_xor = 24'd0;
reg        drop_next_write = 1'b0;

assign request_ready = init_done && !active;
assign busy = !init_done || active;
assign PSRAM_CLK = 1'b0;
assign PSRAM_CE_N = 1'b1;
assign PSRAM_DQ = 4'bzzzz;

always @(posedge clk) begin
	request_done  <= 1'b0;
	request_error <= 1'b0;

	if (reset) begin
		power_count         <= 32'd0;
		active              <= 1'b0;
		latency_count       <= 4'd0;
		lfsr                <= 32'h6D2B79F5;
		saved_write         <= 1'b0;
		saved_address       <= 24'd0;
		saved_bytes         <= 5'd0;
		saved_write_data    <= 32'd0;
		request_read_data   <= 128'd0;
		request_done        <= 1'b0;
		request_error       <= 1'b0;
		init_done           <= 1'b0;
		init_error          <= 1'b0;
		device_id           <= 16'd0;
	end
	else if (!init_done) begin
		if ((POWERUP_CYCLES == 0) ||
		    (power_count >= POWERUP_CYCLES - 1)) begin
			init_done   <= 1'b1;
			device_id   <= 16'h0D5D;
			power_count <= 32'd0;
		end
		else power_count <= power_count + 1'b1;
	end
	else if (!active) begin
		if (request_valid) begin
			accepted_count <= accepted_count + 1;
			if (request_write)
				write_accepted_count <= write_accepted_count + 1;
			if ((request_bytes == 0) ||
			    (request_write ? (request_bytes > 4) :
			                     (request_bytes > 16))) begin
				request_done  <= 1'b1;
				request_error <= 1'b1;
			end
			else begin
				active           <= 1'b1;
				latency_count    <= {1'b0,lfsr[2:0]} + 1'b1;
				lfsr             <= {lfsr[30:0],
				                     lfsr[31] ^ lfsr[21] ^ lfsr[1] ^ lfsr[0]};
				saved_write      <= request_write;
				saved_address    <= request_address;
				saved_bytes      <= request_bytes;
				saved_write_data <= request_write_data;
			end
		end
	end
	else if (latency_count != 0)
		latency_count <= latency_count - 1'b1;
	else begin
		if (saved_write) begin
			if (drop_next_write) begin
				drop_next_write <= 1'b0;
				dropped_write_count <= dropped_write_count + 1;
			end
			else begin
				for (byte_index = 0; byte_index < saved_bytes;
				     byte_index = byte_index + 1) begin
					memory[(saved_address[15:0] + byte_index) & 16'hFFFF] <=
						saved_write_data >> ((saved_bytes - 1 - byte_index) * 8);
				end
			end
		end
		else begin
			read_temp = 128'd0;
			for (byte_index = 0; byte_index < saved_bytes;
			     byte_index = byte_index + 1) begin
				read_temp = (read_temp << 8) |
				            memory[((saved_address[15:0] ^
				                     read_address_xor[15:0]) + byte_index) &
				                   16'hFFFF];
			end
			request_read_data <= read_temp;
		end
		active       <= 1'b0;
		request_done <= 1'b1;
	end
end

endmodule
