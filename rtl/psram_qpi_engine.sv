`timescale 1ns/1ps

// Runtime QPI PSRAM engine for the Saturn RAMH backend.
//
// This module is intentionally separate from psram_diag_bus.sv: the Stage 58
// diagnostic remains a frozen hardware reference, while this engine adds the
// longer transfers needed by the full Saturn core.
//
// Write requests are 1..4 bytes and right-aligned in write_data[31:0]. Read
// requests are 1..16 bytes and right-aligned in read_data[127:0]. The first
// byte on the QPI wire is the most significant byte of the valid field.
module psram_qpi_engine
#(
	parameter integer POWERUP_CYCLES = 20000,
	parameter [5:0]   HALF_DIVIDER   = 6'd2,
	parameter [7:0]   GUARD_CYCLES   = 8'd8
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

localparam [3:0] C_POWER      = 4'd0;
localparam [3:0] C_F5_START   = 4'd1;
localparam [3:0] C_F5_WAIT    = 4'd2;
localparam [3:0] C_66_START   = 4'd3;
localparam [3:0] C_66_WAIT    = 4'd4;
localparam [3:0] C_99_START   = 4'd5;
localparam [3:0] C_99_WAIT    = 4'd6;
localparam [3:0] C_ID_START   = 4'd7;
localparam [3:0] C_ID_WAIT    = 4'd8;
localparam [3:0] C_QPI_START  = 4'd9;
localparam [3:0] C_QPI_WAIT   = 4'd10;
localparam [3:0] C_READY      = 4'd11;
localparam [3:0] C_REQUEST    = 4'd12;
localparam [3:0] C_FAILED     = 4'd13;

localparam integer POWER_COUNTER_WIDTH =
	(POWERUP_CYCLES < 2) ? 1 : $clog2(POWERUP_CYCLES);

reg [3:0] control_state;
reg [POWER_COUNTER_WIDTH-1:0] power_count;

reg         phy_start;
reg         phy_qpi;
reg  [7:0]  phy_command;
reg         phy_address_enable;
reg  [23:0] phy_address;
reg         phy_write_enable;
reg         phy_read_enable;
reg  [4:0]  phy_bytes;
reg  [31:0] phy_write_data;
wire        phy_busy;
wire        phy_done;
wire [127:0] phy_read_data;

assign request_ready = (control_state == C_READY) && !phy_busy;
assign busy = (control_state != C_READY) || phy_busy;

psram_qpi_phy #(.GUARD_CYCLES(GUARD_CYCLES)) phy
(
	.clk(clk),
	.reset(reset),
	.start(phy_start),
	.qpi(phy_qpi),
	.command(phy_command),
	.address_enable(phy_address_enable),
	.address(phy_address),
	.write_enable(phy_write_enable),
	.read_enable(phy_read_enable),
	.byte_count(phy_bytes),
	.write_data(phy_write_data),
	.half_divider(HALF_DIVIDER),
	.busy(phy_busy),
	.done(phy_done),
	.read_data(phy_read_data),
	.PSRAM_CLK(PSRAM_CLK),
	.PSRAM_CE_N(PSRAM_CE_N),
	.PSRAM_DQ(PSRAM_DQ)
);

task configure_command;
	input       use_qpi;
	input [7:0] command_value;
	begin
		phy_qpi            <= use_qpi;
		phy_command         <= command_value;
		phy_address_enable  <= 1'b0;
		phy_address         <= 24'd0;
		phy_write_enable    <= 1'b0;
		phy_read_enable     <= 1'b0;
		phy_bytes           <= 5'd0;
		phy_write_data      <= 32'd0;
		phy_start           <= 1'b1;
	end
endtask

always @(posedge clk) begin
	phy_start     <= 1'b0;
	request_done  <= 1'b0;
	request_error <= 1'b0;

	if (reset) begin
		control_state       <= C_POWER;
		power_count         <= {POWER_COUNTER_WIDTH{1'b0}};
		phy_start           <= 1'b0;
		phy_qpi             <= 1'b0;
		phy_command          <= 8'd0;
		phy_address_enable   <= 1'b0;
		phy_address          <= 24'd0;
		phy_write_enable     <= 1'b0;
		phy_read_enable      <= 1'b0;
		phy_bytes            <= 5'd0;
		phy_write_data       <= 32'd0;
		request_read_data   <= 128'd0;
		request_done        <= 1'b0;
		request_error       <= 1'b0;
		init_done           <= 1'b0;
		init_error          <= 1'b0;
		device_id           <= 16'd0;
	end
	else begin
		case (control_state)
			C_POWER: begin
				if ((POWERUP_CYCLES == 0) ||
				    (power_count >= POWERUP_CYCLES - 1)) begin
					power_count   <= {POWER_COUNTER_WIDTH{1'b0}};
					control_state <= C_F5_START;
				end
				else power_count <= power_count + 1'b1;
			end

			// A newly loaded FPGA may find the device in QPI from the old
			// core. F5 exits QPI and is harmless when the device is in SPI.
			C_F5_START: begin
				configure_command(1'b1, 8'hF5);
				control_state <= C_F5_WAIT;
			end
			C_F5_WAIT: if (phy_done) control_state <= C_66_START;

			C_66_START: begin
				configure_command(1'b0, 8'h66);
				control_state <= C_66_WAIT;
			end
			C_66_WAIT: if (phy_done) control_state <= C_99_START;

			C_99_START: begin
				configure_command(1'b0, 8'h99);
				control_state <= C_99_WAIT;
			end
			C_99_WAIT: if (phy_done) control_state <= C_ID_START;

			C_ID_START: begin
				phy_qpi            <= 1'b0;
				phy_command         <= 8'h9F;
				phy_address_enable  <= 1'b1;
				phy_address         <= 24'd0;
				phy_write_enable    <= 1'b0;
				phy_read_enable     <= 1'b1;
				phy_bytes           <= 5'd2;
				phy_write_data      <= 128'd0;
				phy_start           <= 1'b1;
				control_state       <= C_ID_WAIT;
			end
			C_ID_WAIT: if (phy_done) begin
				device_id <= phy_read_data[15:0];
				if ((phy_read_data[15:0] == 16'h0000) ||
				    (phy_read_data[15:0] == 16'hFFFF) ||
				    (phy_read_data[7:0] != 8'h5D)) begin
					init_error    <= 1'b1;
					control_state <= C_FAILED;
				end
				else control_state <= C_QPI_START;
			end

			C_QPI_START: begin
				configure_command(1'b0, 8'h35);
				control_state <= C_QPI_WAIT;
			end
			C_QPI_WAIT: if (phy_done) begin
				init_done     <= 1'b1;
				control_state <= C_READY;
			end

			C_READY: begin
				if (request_valid && !phy_busy) begin
					if ((request_bytes == 0) ||
					    (request_write ? (request_bytes > 4) :
					                     (request_bytes > 16))) begin
						request_error <= 1'b1;
						request_done  <= 1'b1;
					end
					else begin
						phy_qpi            <= 1'b1;
						phy_command         <= request_write ? 8'h02 : 8'hEB;
						phy_address_enable  <= 1'b1;
						phy_address         <= request_address;
						phy_write_enable    <= request_write;
						phy_read_enable     <= !request_write;
						phy_bytes           <= request_bytes;
						phy_write_data      <= request_write_data;
						phy_start           <= 1'b1;
						control_state       <= C_REQUEST;
					end
				end
			end

			C_REQUEST: if (phy_done) begin
				request_read_data <= phy_read_data;
				request_done      <= 1'b1;
				control_state     <= C_READY;
			end

			C_FAILED: begin
				// Hold the engine unavailable until the full core resets it.
				init_done  <= 1'b0;
				init_error <= 1'b1;
			end

			default: control_state <= C_POWER;
		endcase
	end
end

endmodule


// Low-level transaction engine. Data changes at external SCLK falling edges;
// returned data is captured immediately before the next registered falling
// edge, preserving the Stage 58 timing strategy.
module psram_qpi_phy
#(
	parameter [7:0] GUARD_CYCLES = 8'd8
)
(
	input              clk,
	input              reset,
	input              start,
	input              qpi,
	input       [7:0]  command,
	input              address_enable,
	input      [23:0]  address,
	input              write_enable,
	input              read_enable,
	input       [4:0]  byte_count,
	input       [31:0] write_data,
	input       [5:0]  half_divider,
	output reg         busy,
	output reg         done,
	output reg [127:0] read_data,
	output reg         PSRAM_CLK,
	output reg         PSRAM_CE_N,
	inout       [3:0]  PSRAM_DQ
);

localparam [2:0] P_IDLE  = 3'd0;
localparam [2:0] P_CMD   = 3'd1;
localparam [2:0] P_ADDR  = 3'd2;
localparam [2:0] P_DUMMY = 3'd3;
localparam [2:0] P_WRITE = 3'd4;
localparam [2:0] P_READ  = 3'd5;
localparam [2:0] P_HOLD  = 3'd6;
localparam [2:0] P_GAP   = 3'd7;

reg [2:0] state;
reg [3:0] dq_out;
reg       dq_oe;
wire [3:0] dq_in = PSRAM_DQ;
reg [3:0] dq_sample;

reg [7:0]  command_shift;
reg [23:0] address_shift;
reg [31:0] write_shift;
reg [7:0] units_left;
reg [5:0] divider_count;
reg [7:0] hold_count;
reg [7:0] gap_count;

reg         transaction_qpi;
reg         transaction_address;
reg         transaction_write;
reg         transaction_read;
reg  [4:0]  transaction_bytes;

assign PSRAM_DQ = dq_oe ? dq_out : 4'bzzzz;

function [5:0] nonzero_divider;
	input [5:0] value;
	begin
		nonzero_divider = value ? value : 6'd1;
	end
endfunction

function [31:0] align_write_data;
	input [31:0] value;
	input [4:0] count;
	begin
		// The public interface is right-aligned; the wire shifter consumes
		// its most-significant nibble first.
		align_write_data = value << ((5'd4 - count) * 8);
	end
endfunction

always @(posedge clk) begin
	dq_sample <= dq_in;
end

task begin_hold;
	begin
		PSRAM_CLK <= 1'b0;
		dq_oe      <= 1'b0;
		hold_count <= GUARD_CYCLES;
		state      <= P_HOLD;
	end
endtask

always @(posedge clk) begin
	if (reset) begin
		state               <= P_IDLE;
		busy                <= 1'b0;
		done                <= 1'b0;
		read_data           <= 128'd0;
		PSRAM_CLK           <= 1'b0;
		PSRAM_CE_N          <= 1'b1;
		dq_out              <= 4'd0;
		dq_oe               <= 1'b0;
		command_shift       <= 8'd0;
		address_shift       <= 24'd0;
		write_shift         <= 32'd0;
		units_left          <= 8'd0;
		divider_count       <= 6'd0;
		hold_count          <= 8'd0;
		gap_count           <= 8'd0;
		transaction_qpi     <= 1'b0;
		transaction_address <= 1'b0;
		transaction_write   <= 1'b0;
		transaction_read    <= 1'b0;
		transaction_bytes   <= 5'd0;
	end
	else begin
		done <= 1'b0;

		case (state)
			P_IDLE: begin
				busy          <= 1'b0;
				PSRAM_CLK     <= 1'b0;
				PSRAM_CE_N    <= 1'b1;
				dq_out        <= 4'd0;
				dq_oe         <= 1'b0;
				divider_count <= 6'd0;

				if (start) begin
					busy                <= 1'b1;
					PSRAM_CE_N          <= 1'b0;
					read_data           <= 128'd0;
					transaction_qpi     <= qpi;
					transaction_address <= address_enable;
					transaction_write   <= write_enable;
					transaction_read    <= read_enable;
					transaction_bytes   <= byte_count;
					command_shift       <= command;
					address_shift       <= address;
					write_shift         <= write_enable ?
					                       align_write_data(write_data, byte_count) :
					                       32'd0;
					units_left          <= qpi ? 8'd2 : 8'd8;
					divider_count       <= nonzero_divider(half_divider) - 1'b1;
					dq_oe               <= 1'b1;
					dq_out              <= qpi ? command[7:4] : {3'b000, command[7]};
					state               <= P_CMD;
				end
			end

			P_HOLD: begin
				PSRAM_CLK <= 1'b0;
				dq_oe      <= 1'b0;
				if (hold_count <= 1) begin
					PSRAM_CE_N <= 1'b1;
					gap_count   <= GUARD_CYCLES;
					state       <= P_GAP;
				end
				else hold_count <= hold_count - 1'b1;
			end

			P_GAP: begin
				PSRAM_CE_N <= 1'b1;
				if (gap_count <= 1) begin
					busy  <= 1'b0;
					done  <= 1'b1;
					state <= P_IDLE;
				end
				else gap_count <= gap_count - 1'b1;
			end

			default: begin
				if (divider_count != 0)
					divider_count <= divider_count - 1'b1;
				else begin
					divider_count <= nonzero_divider(half_divider) - 1'b1;
					if (!PSRAM_CLK) begin
						PSRAM_CLK <= 1'b1;
					end
					else begin
						PSRAM_CLK <= 1'b0;
						case (state)
							P_CMD: begin
								if (units_left == 1) begin
									if (transaction_address) begin
										state         <= P_ADDR;
										units_left    <= transaction_qpi ? 8'd6 : 8'd24;
										dq_out        <= transaction_qpi ? address_shift[23:20] :
										                                  {3'b000, address_shift[23]};
									end
									else if (transaction_write) begin
										state      <= P_WRITE;
										units_left <= transaction_qpi ?
										              {transaction_bytes, 1'b0} :
										              {transaction_bytes, 3'b000};
										dq_out     <= transaction_qpi ? write_shift[31:28] :
										                               {3'b000, write_shift[31]};
									end
									else if (transaction_read) begin
										dq_oe <= 1'b0;
										if (transaction_qpi) begin
											state      <= P_DUMMY;
											units_left <= 8'd6;
										end
										else begin
											state      <= P_READ;
											units_left <= {transaction_bytes, 3'b000};
										end
									end
									else begin_hold();
								end
								else begin
									units_left <= units_left - 1'b1;
									if (transaction_qpi) begin
										command_shift <= {command_shift[3:0], 4'd0};
										dq_out        <= command_shift[3:0];
									end
									else begin
										command_shift <= {command_shift[6:0], 1'b0};
										dq_out        <= {3'b000, command_shift[6]};
									end
								end
							end

							P_ADDR: begin
								if (units_left == 1) begin
									if (transaction_write) begin
										state      <= P_WRITE;
										units_left <= transaction_qpi ?
										              {transaction_bytes, 1'b0} :
										              {transaction_bytes, 3'b000};
										dq_out     <= transaction_qpi ? write_shift[31:28] :
										                               {3'b000, write_shift[31]};
									end
									else if (transaction_read) begin
										dq_oe <= 1'b0;
										if (transaction_qpi) begin
											state      <= P_DUMMY;
											units_left <= 8'd6;
										end
										else begin
											state      <= P_READ;
											units_left <= {transaction_bytes, 3'b000};
										end
									end
									else begin_hold();
								end
								else begin
									units_left    <= units_left - 1'b1;
									if (transaction_qpi) begin
										address_shift <= {address_shift[19:0], 4'd0};
										dq_out       <= address_shift[19:16];
									end
									else begin
										address_shift <= {address_shift[22:0], 1'b0};
										dq_out       <= {3'b000, address_shift[22]};
									end
								end
							end

							P_DUMMY: begin
								if (units_left == 1) begin
									state      <= P_READ;
									units_left <= {transaction_bytes, 1'b0};
								end
								else units_left <= units_left - 1'b1;
							end

							P_WRITE: begin
								if (units_left == 1) begin_hold();
								else begin
									units_left <= units_left - 1'b1;
									if (transaction_qpi) begin
										write_shift <= {write_shift[27:0], 4'd0};
										dq_out     <= write_shift[27:24];
									end
									else begin
										write_shift <= {write_shift[30:0], 1'b0};
										dq_out     <= {3'b000, write_shift[30]};
									end
								end
							end

							P_READ: begin
								if (transaction_qpi)
									read_data <= {read_data[123:0],
									              (half_divider == 6'd1) ? dq_in : dq_sample};
								else
									read_data <= {read_data[126:0], dq_sample[1]};

								if (units_left == 1) begin_hold();
								else units_left <= units_left - 1'b1;
							end

							default: begin_hold();
						endcase
					end
				end
			end
		endcase
	end
end

endmodule
