`timescale 1ns/1ps

// One-outstanding-request clock-domain bridge for psram_qpi_engine.
//
// Request payload registers are held in the source domain until the
// destination acknowledges completion.  The toggle synchronizers therefore
// provide several destination cycles of bundled-data settling time without a
// large asynchronous FIFO.  The response data remains stable in the engine
// until the next request and is sampled only after the acknowledgement has
// crossed back to the source domain.
module psram_qpi_engine_cdc
#(
	parameter integer POWERUP_CYCLES = 20000,
	parameter [5:0]   HALF_DIVIDER = 6'd1,
	parameter [7:0]   GUARD_CYCLES = 8'd8,
	parameter integer DIRECT_READ_CAPTURE = 0
)
(
	input              src_clk,
	input              src_reset,
	input              engine_clk,
	input              engine_reset,

	input              request_valid,
	output             request_ready,
	input              request_write,
	input      [23:0]  request_address,
	input       [4:0]  request_bytes,
	input      [31:0]  request_write_data,
	output     [127:0] request_read_data,
	output reg         request_done,
	output             request_error,

	output             init_done,
	output             init_error,
	output      [15:0] device_id,

	output             PSRAM_CLK,
	output             PSRAM_CE_N,
	inout       [3:0]  PSRAM_DQ
);

	(* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *)
	reg req_sync1, req_sync2;
	(* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *)
	reg ack_sync1, ack_sync2;
	(* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *)
	reg init_done_sync1, init_done_sync2;
	(* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *)
	reg init_error_sync1, init_error_sync2;

	reg req_toggle;
	reg ack_seen;
	reg src_request_write;
	reg [23:0] src_request_address;
	reg  [4:0] src_request_bytes;
	reg [31:0] src_request_write_data;

	reg req_seen;
	reg ack_toggle;
	reg engine_request_valid;
	reg response_error;
	reg [1:0] dst_state;

	wire engine_request_ready;
	wire [127:0] engine_request_read_data;
	wire engine_request_done;
	wire engine_request_error;
	wire engine_init_done;
	wire engine_init_error;
	wire [15:0] engine_device_id;

	localparam [1:0] D_IDLE = 2'd0;
	localparam [1:0] D_WAIT_READY = 2'd1;
	localparam [1:0] D_WAIT_DONE = 2'd2;

	assign request_ready = init_done_sync2 && !init_error_sync2 &&
	                       (req_toggle == ack_sync2);
	assign request_read_data = engine_request_read_data;
	assign request_error = response_error;
	assign init_done = init_done_sync2;
	assign init_error = init_error_sync2;
	assign device_id = engine_device_id;

	always @(posedge src_clk) begin
		request_done <= 1'b0;
		if (src_reset) begin
			req_toggle             <= 1'b0;
			ack_sync1              <= 1'b0;
			ack_sync2              <= 1'b0;
			ack_seen               <= 1'b0;
			init_done_sync1        <= 1'b0;
			init_done_sync2        <= 1'b0;
			init_error_sync1       <= 1'b0;
			init_error_sync2       <= 1'b0;
			src_request_write      <= 1'b0;
			src_request_address    <= 24'd0;
			src_request_bytes      <= 5'd0;
			src_request_write_data <= 32'd0;
		end
		else begin
			ack_sync1        <= ack_toggle;
			ack_sync2        <= ack_sync1;
			init_done_sync1  <= engine_init_done;
			init_done_sync2  <= init_done_sync1;
			init_error_sync1 <= engine_init_error;
			init_error_sync2 <= init_error_sync1;

			if (request_valid && request_ready) begin
				src_request_write      <= request_write;
				src_request_address    <= request_address;
				src_request_bytes      <= request_bytes;
				src_request_write_data <= request_write_data;
				req_toggle             <= ~req_toggle;
			end

			if (ack_sync2 != ack_seen) begin
				ack_seen     <= ack_sync2;
				request_done <= 1'b1;
			end
		end
	end

	always @(posedge engine_clk) begin
		engine_request_valid <= 1'b0;
		if (engine_reset) begin
			req_sync1           <= 1'b0;
			req_sync2           <= 1'b0;
			req_seen            <= 1'b0;
			ack_toggle          <= 1'b0;
			engine_request_valid<= 1'b0;
			response_error      <= 1'b0;
			dst_state           <= D_IDLE;
		end
		else begin
			req_sync1 <= req_toggle;
			req_sync2 <= req_sync1;

			case (dst_state)
				D_IDLE: begin
					if (req_sync2 != req_seen) begin
						req_seen  <= req_sync2;
						dst_state <= D_WAIT_READY;
					end
				end

				D_WAIT_READY: begin
					if (engine_request_ready) begin
						engine_request_valid <= 1'b1;
						dst_state <= D_WAIT_DONE;
					end
				end

				D_WAIT_DONE: begin
					if (engine_request_done) begin
						response_error <= engine_request_error;
						ack_toggle     <= req_seen;
						dst_state      <= D_IDLE;
					end
				end

				default: dst_state <= D_IDLE;
			endcase
		end
	end

	psram_qpi_engine
	#(
		.POWERUP_CYCLES(POWERUP_CYCLES),
		.HALF_DIVIDER(HALF_DIVIDER),
		.GUARD_CYCLES(GUARD_CYCLES),
		.DIRECT_READ_CAPTURE(DIRECT_READ_CAPTURE)
	)
	engine_core
	(
		.clk(engine_clk),
		.reset(engine_reset),
		.request_valid(engine_request_valid),
		.request_ready(engine_request_ready),
		.request_write(src_request_write),
		.request_address(src_request_address),
		.request_bytes(src_request_bytes),
		.request_write_data(src_request_write_data),
		.request_read_data(engine_request_read_data),
		.request_done(engine_request_done),
		.request_error(engine_request_error),
		.init_done(engine_init_done),
		.init_error(engine_init_error),
		.device_id(engine_device_id),
		.busy(),
		.PSRAM_CLK(PSRAM_CLK),
		.PSRAM_CE_N(PSRAM_CE_N),
		.PSRAM_DQ(PSRAM_DQ)
	);

endmodule
