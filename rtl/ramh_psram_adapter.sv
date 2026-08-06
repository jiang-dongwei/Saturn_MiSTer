`timescale 1ns/1ps

// Saturn RAMH to QPI PSRAM adapter.
//
// The CPU-side interface intentionally mirrors the logical side of sdram2.
// RAMH addresses are 32-bit word addresses. By default reads fill one aligned
// 16-byte line; READ_LINE_BYTES=4 is a diagnostic mode which fetches only the
// requested 32-bit word. Writes go directly to PSRAM and invalidate a matching
// cached entry.
module ramh_psram_adapter
#(
	parameter integer POWERUP_CYCLES = 20000,
	parameter [5:0]   HALF_DIVIDER   = 6'd2,
	parameter [7:0]   GUARD_CYCLES   = 8'd8,
	parameter integer READ_LINE_BYTES = 16,
	parameter integer DIRECT_READ_CAPTURE = 0
)
(
	input              clk,
	input              reset,

	input      [19:2]  addr,
	input      [31:0]  din,
	input       [3:0]  wr,
	input              rd,
	input              burst,
	output reg [31:0]  dout,
	input              rfs,
	output             busy,

	output             qpi_init_done,
	output             qpi_init_error,
	output     [15:0]  qpi_device_id,
	output reg         adapter_error,

	output             PSRAM_CLK,
	output             PSRAM_CE_N,
	inout       [3:0]  PSRAM_DQ
);

localparam [2:0] A_IDLE      = 3'd0;
localparam [2:0] A_READ_REQ  = 3'd1;
localparam [2:0] A_READ_WAIT = 3'd2;
localparam [2:0] A_WRITE_REQ = 3'd3;
localparam [2:0] A_WRITE_WAIT= 3'd4;
localparam [2:0] A_FAILED    = 3'd5;

reg [2:0] state;

reg         engine_request_valid;
wire        engine_request_ready;
reg         engine_request_write;
reg  [23:0] engine_request_address;
reg   [4:0] engine_request_bytes;
reg  [31:0] engine_request_write_data;
wire [127:0] engine_request_read_data;
wire         engine_request_done;
wire         engine_request_error;

reg [19:2] pending_addr;
reg [31:0] pending_write_data;
reg  [3:0] pending_write_mask;

reg         line_valid;
reg [17:0] line_tag;
reg [127:0] line_data;

reg read_armed;
reg write_armed;

wire diagnostic_word_read = (READ_LINE_BYTES == 4);
wire [17:0] current_line_tag = diagnostic_word_read ?
	                            addr : {addr[19:4], 2'b00};
wire cache_match = line_valid && (line_tag == current_line_tag);
wire pending_cpu_read  = rd && read_armed && !cache_match;
wire pending_cpu_write = (|wr) && write_armed;

assign busy = reset || !qpi_init_done || qpi_init_error || adapter_error ||
	            (state != A_IDLE) || pending_cpu_read || pending_cpu_write;

// burst is satisfied by the 16-byte line fill. PSRAM needs no refresh, so rfs
// is intentionally accepted without creating a physical transaction.
always @* begin
	dout = 32'd0;
	if (cache_match) begin
		if (diagnostic_word_read) dout = line_data[31:0];
		else begin
			case (addr[3:2])
				2'd0: dout = line_data[127:96];
				2'd1: dout = line_data[ 95:64];
				2'd2: dout = line_data[ 63:32];
				default: dout = line_data[31:0];
			endcase
		end
	end
end

// Byte enables follow the original sdram2 convention:
// wr[3] is din[31:24] at address +0, wr[0] is din[7:0] at address +3.
function [1:0] first_write_offset;
	input [3:0] mask;
	begin
		casex (mask)
			4'b1xxx: first_write_offset = 2'd0;
			4'b01xx: first_write_offset = 2'd1;
			4'b001x: first_write_offset = 2'd2;
			default: first_write_offset = 2'd3;
		endcase
	end
endfunction

function [2:0] first_write_count;
	input [3:0] mask;
	begin
		case (mask)
			4'b1111: first_write_count = 3'd4;
			4'b1110: first_write_count = 3'd3;
			4'b1100,
			4'b1101: first_write_count = 3'd2;
			4'b1000,
			4'b1001,
			4'b1010,
			4'b1011: first_write_count = 3'd1;

			4'b0111: first_write_count = 3'd3;
			4'b0110: first_write_count = 3'd2;
			4'b0100,
			4'b0101: first_write_count = 3'd1;

			4'b0011: first_write_count = 3'd2;
			default: first_write_count = 3'd1;
		endcase
	end
endfunction

function [3:0] write_run_mask;
	input [1:0] offset;
	input [2:0] count;
	begin
		case ({offset, count})
			{2'd0,3'd4}: write_run_mask = 4'b1111;
			{2'd0,3'd3}: write_run_mask = 4'b1110;
			{2'd0,3'd2}: write_run_mask = 4'b1100;
			{2'd0,3'd1}: write_run_mask = 4'b1000;
			{2'd1,3'd3}: write_run_mask = 4'b0111;
			{2'd1,3'd2}: write_run_mask = 4'b0110;
			{2'd1,3'd1}: write_run_mask = 4'b0100;
			{2'd2,3'd2}: write_run_mask = 4'b0011;
			{2'd2,3'd1}: write_run_mask = 4'b0010;
			default:      write_run_mask = 4'b0001;
		endcase
	end
endfunction

function [31:0] write_run_data;
	input [31:0] value;
	input  [1:0] offset;
	input  [2:0] count;
	begin
		write_run_data = 32'd0;
		case (offset)
			2'd0: begin
				case (count)
					3'd4: write_run_data[31:0] = value;
					3'd3: write_run_data[23:0] = value[31:8];
					3'd2: write_run_data[15:0] = value[31:16];
					default: write_run_data[7:0] = value[31:24];
				endcase
			end
			2'd1: begin
				case (count)
					3'd3: write_run_data[23:0] = value[23:0];
					3'd2: write_run_data[15:0] = value[23:8];
					default: write_run_data[7:0] = value[23:16];
				endcase
			end
			2'd2: begin
				if (count == 3'd2) write_run_data[15:0] = value[15:0];
				else write_run_data[7:0] = value[15:8];
			end
			default: write_run_data[7:0] = value[7:0];
		endcase
	end
endfunction

wire [1:0] next_write_offset = first_write_offset(pending_write_mask);
wire [2:0] next_write_count  = first_write_count(pending_write_mask);
wire [3:0] next_write_mask   = write_run_mask(next_write_offset,
	                                           next_write_count);

psram_qpi_engine
#(
	.POWERUP_CYCLES(POWERUP_CYCLES),
	.HALF_DIVIDER(HALF_DIVIDER),
	.GUARD_CYCLES(GUARD_CYCLES),
	.DIRECT_READ_CAPTURE(DIRECT_READ_CAPTURE)
)
engine
(
	.clk(clk),
	.reset(reset),
	.request_valid(engine_request_valid),
	.request_ready(engine_request_ready),
	.request_write(engine_request_write),
	.request_address(engine_request_address),
	.request_bytes(engine_request_bytes),
	.request_write_data(engine_request_write_data),
	.request_read_data(engine_request_read_data),
	.request_done(engine_request_done),
	.request_error(engine_request_error),
	.init_done(qpi_init_done),
	.init_error(qpi_init_error),
	.device_id(qpi_device_id),
	.busy(),
	.PSRAM_CLK(PSRAM_CLK),
	.PSRAM_CE_N(PSRAM_CE_N),
	.PSRAM_DQ(PSRAM_DQ)
);

always @(posedge clk) begin
	engine_request_valid <= 1'b0;

	if (reset) begin
		state                     <= A_IDLE;
		engine_request_valid      <= 1'b0;
		engine_request_write      <= 1'b0;
		engine_request_address    <= 24'd0;
		engine_request_bytes      <= 5'd0;
		engine_request_write_data <= 32'd0;
		pending_addr              <= '0;
		pending_write_data        <= 32'd0;
		pending_write_mask        <= 4'd0;
		line_valid                <= 1'b0;
		line_tag                  <= 18'd0;
		line_data                 <= 128'd0;
		read_armed                <= 1'b1;
		write_armed               <= 1'b1;
		adapter_error             <= 1'b0;
	end
	else begin
		if (!rd)  read_armed  <= 1'b1;
		if (!(|wr)) write_armed <= 1'b1;

		if (qpi_init_error) begin
			adapter_error <= 1'b1;
			state         <= A_FAILED;
		end
		else begin
			case (state)
				A_IDLE: begin
					if (qpi_init_done && !adapter_error) begin
						if ((|wr) && write_armed) begin
							write_armed        <= 1'b0;
							pending_addr       <= addr;
							pending_write_data <= din;
							pending_write_mask <= wr;
							if (line_valid && (line_tag == current_line_tag))
								line_valid <= 1'b0;
							state <= A_WRITE_REQ;
						end
						else if (rd && read_armed) begin
							read_armed <= 1'b0;
							if (!cache_match) begin
								pending_addr <= addr;
								state        <= A_READ_REQ;
							end
						end
					end
				end

				A_READ_REQ: begin
					if (engine_request_ready) begin
						engine_request_write      <= 1'b0;
						engine_request_address    <= diagnostic_word_read ?
						                              {4'd0, pending_addr, 2'd0} :
						                              {4'd0, pending_addr[19:4], 4'd0};
						engine_request_bytes      <= READ_LINE_BYTES;
						engine_request_write_data <= 32'd0;
						engine_request_valid      <= 1'b1;
						state                     <= A_READ_WAIT;
					end
				end

				A_READ_WAIT: begin
					if (engine_request_done) begin
						if (engine_request_error) begin
							adapter_error <= 1'b1;
							state         <= A_FAILED;
						end
						else begin
							line_data  <= engine_request_read_data;
							line_tag   <= diagnostic_word_read ?
							              pending_addr :
							              {pending_addr[19:4], 2'b00};
							line_valid <= 1'b1;
							state      <= A_IDLE;
						end
					end
				end

				A_WRITE_REQ: begin
					if (engine_request_ready) begin
						engine_request_write   <= 1'b1;
						engine_request_address <= {4'd0,
						                           pending_addr,
						                           2'd0} + next_write_offset;
						engine_request_bytes   <= {2'd0, next_write_count};
						engine_request_write_data <=
							write_run_data(pending_write_data,
							               next_write_offset,
							               next_write_count);
						engine_request_valid <= 1'b1;
						pending_write_mask   <= pending_write_mask &
						                        ~next_write_mask;
						state                <= A_WRITE_WAIT;
					end
				end

				A_WRITE_WAIT: begin
					if (engine_request_done) begin
						if (engine_request_error) begin
							adapter_error <= 1'b1;
							state         <= A_FAILED;
						end
						else if (pending_write_mask != 0)
							state <= A_WRITE_REQ;
						else state <= A_IDLE;
					end
				end

				A_FAILED: begin
					adapter_error <= 1'b1;
					state         <= A_FAILED;
				end

				default: state <= A_FAILED;
			endcase
		end
	end
end

endmodule
