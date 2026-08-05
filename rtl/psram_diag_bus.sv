// Conservative SPI/QPI transaction engine with a true square PSRAM clock.
//
// The controller clock is 67.7376 MHz.  half_divider is the number of
// controller cycles in each HIGH and LOW phase, so every selected rate has a
// 50 percent duty cycle:
//   1 = 33.8688 MHz, 2 = 16.9344 MHz, 4 = 8.4672 MHz, 8 = 4.2336 MHz, ...
// DQ changes on PSRAM clock falling edges.  Dividers above one use the input
// I/O register sampled during the high phase.  At divider=1 there is no spare
// controller cycle between the external rising and falling edges, so the read
// shifter captures the live DQ pins on the controller edge that is about to
// lower PSRAM_CLK.  The external falling edge propagates after that internal
// capture, giving the fastest path nearly one full PSRAM clock period to settle.
module psram_diag_bus
(
	input             clk,
	input             reset,

	input             start,
	input             qpi,
	input       [7:0] command,
	input             address_enable,
	input      [23:0] address,
	input             write_enable,
	input      [23:0] write_data,
	input       [2:0] write_bytes,
	input             read_enable,
	input       [2:0] read_bytes,
	input       [5:0] half_divider,

	output reg        busy,
	output reg        done,
	output reg [47:0] read_data,
	output reg  [3:0] dq_sample,

	output reg        PSRAM_CLK,
	output reg        PSRAM_CE_N,
	inout       [3:0] PSRAM_DQ
);

localparam [3:0] ST_IDLE  = 4'd0;
localparam [3:0] ST_CMD   = 4'd1;
localparam [3:0] ST_ADDR  = 4'd2;
localparam [3:0] ST_DUMMY = 4'd3;
localparam [3:0] ST_WRITE = 4'd4;
localparam [3:0] ST_READ  = 4'd5;
localparam [3:0] ST_HOLD  = 4'd6;
localparam [3:0] ST_GAP   = 4'd7;

reg [3:0] state;
reg [3:0] dq_out;
reg       dq_oe;
wire [3:0] dq_in = PSRAM_DQ;
reg [5:0] units_left;
reg [23:0] shift_register;
reg        transaction_qpi;
reg  [7:0] transaction_command;
reg        transaction_address;
reg        transaction_write;
reg        transaction_read;
reg  [2:0] transaction_write_bytes;
reg  [2:0] transaction_read_bytes;
reg  [5:0] divider_count;
reg  [2:0] hold_count;
reg  [2:0] gap_count;

assign PSRAM_DQ = dq_oe ? dq_out : 4'bzzzz;

function [5:0] nonzero_divider;
	input [5:0] value;
	begin
		nonzero_divider = value ? value : 6'd1;
	end
endfunction

// PSRAM_CLK is changed by another register on this same controller edge. The
// input register therefore captures the value that was stable before the new
// external SCLK edge propagates out of the FPGA. At divider=1 this is one full
// 14.76 ns half-period after the PSRAM falling edge, instead of only 7.38 ns as
// with a controller-negedge capture. Keeping this register reset-free still
// allows placement in the input I/O cell.
always @(posedge clk) begin
	dq_sample <= dq_in;
end

task begin_hold;
	begin
		PSRAM_CLK   <= 1'b0;
		dq_oe        <= 1'b0;
		// Four controller cycles provide a 59 ns CE# hold guard.
		hold_count   <= 3'd4;
		state        <= ST_HOLD;
	end
endtask

always @(posedge clk) begin
	if (reset) begin
		state                   <= ST_IDLE;
		busy                    <= 1'b0;
		done                    <= 1'b0;
		read_data               <= 48'd0;
		PSRAM_CE_N              <= 1'b1;
		dq_out                  <= 4'd0;
		dq_oe                   <= 1'b0;
		PSRAM_CLK               <= 1'b0;
		units_left              <= 6'd0;
		shift_register          <= 24'd0;
		transaction_qpi         <= 1'b0;
		transaction_command     <= 8'd0;
		transaction_address     <= 1'b0;
		transaction_write       <= 1'b0;
		transaction_read        <= 1'b0;
		transaction_write_bytes <= 3'd0;
		transaction_read_bytes  <= 3'd0;
		divider_count           <= 6'd0;
		hold_count              <= 3'd0;
		gap_count               <= 3'd0;
	end
	else begin
		done <= 1'b0;

		case (state)
			ST_IDLE: begin
				busy          <= 1'b0;
				PSRAM_CE_N    <= 1'b1;
				dq_oe         <= 1'b0;
				dq_out        <= 4'd0;
				PSRAM_CLK     <= 1'b0;
				divider_count <= 6'd0;

				if (start) begin
					busy                    <= 1'b1;
					PSRAM_CE_N              <= 1'b0;
					read_data               <= 48'd0;
					transaction_qpi         <= qpi;
					transaction_command     <= command;
					transaction_address     <= address_enable;
					transaction_write       <= write_enable;
					transaction_read        <= read_enable;
					transaction_write_bytes <= write_bytes;
					transaction_read_bytes  <= read_bytes;
					divider_count           <= nonzero_divider(half_divider) - 1'b1;
					units_left              <= qpi ? 6'd2 : 6'd8;
					shift_register          <= {command, 16'd0};
					dq_oe                   <= 1'b1;
					dq_out                  <= qpi ? command[7:4] :
					                           {3'b000, command[7]};
					// CE# and DQ remain stable for one complete divided half
					// phase before the first PSRAM clock rising edge.
					state                   <= ST_CMD;
				end
			end

			ST_HOLD: begin
				PSRAM_CLK <= 1'b0;
				dq_oe        <= 1'b0;
				if (hold_count == 1) begin
					PSRAM_CE_N <= 1'b1;
					gap_count  <= 3'd4;
					state      <= ST_GAP;
				end
				else hold_count <= hold_count - 1'b1;
			end

			ST_GAP: begin
				PSRAM_CE_N <= 1'b1;
				if (gap_count == 1) begin
					busy  <= 1'b0;
					done  <= 1'b1;
					state <= ST_IDLE;
				end
				else gap_count <= gap_count - 1'b1;
			end

			default: begin
				if (divider_count != 0)
					divider_count <= divider_count - 1'b1;
				else begin
					divider_count <= nonzero_divider(half_divider) - 1'b1;
					if (!PSRAM_CLK) begin
						// Rising edge: memory samples writes, while dq_sample has
						// captured returned data that was stable since the prior
						// falling edge.
						PSRAM_CLK <= 1'b1;
					end
					else begin
						// Falling edge: advance protocol state and launch the next
						// output unit for the following rising edge.
						PSRAM_CLK <= 1'b0;
						case (state)
						ST_CMD: begin
							if (units_left == 1) begin
								if (transaction_address) begin
									state          <= ST_ADDR;
									shift_register <= address;
									units_left     <= transaction_qpi ? 6'd6 : 6'd24;
									dq_out         <= transaction_qpi ? address[23:20] :
									                                  {3'b000, address[23]};
								end
								else if (transaction_write) begin
									state          <= ST_WRITE;
									shift_register <= write_data;
									units_left     <= transaction_qpi ?
									                  {transaction_write_bytes, 1'b0} :
									                  {transaction_write_bytes, 3'b000};
									dq_out         <= transaction_qpi ? write_data[23:20] :
									                                  {3'b000, write_data[23]};
								end
								else if (transaction_read) begin
									dq_oe <= 1'b0;
									if (transaction_qpi) begin
										state      <= ST_DUMMY;
										units_left <= (transaction_command == 8'h0B) ?
										              6'd4 : 6'd6;
									end
									else begin
										state      <= ST_READ;
										units_left <= {transaction_read_bytes, 3'b000};
									end
								end
								else begin_hold();
							end
							else begin
								units_left <= units_left - 1'b1;
								if (transaction_qpi) begin
									shift_register <= {shift_register[19:0], 4'd0};
									dq_out <= shift_register[19:16];
								end
								else begin
									shift_register <= {shift_register[22:0], 1'b0};
									dq_out <= {3'b000, shift_register[22]};
								end
							end
						end

						ST_ADDR: begin
							if (units_left == 1) begin
								if (transaction_write) begin
									state          <= ST_WRITE;
									shift_register <= write_data;
									units_left     <= transaction_qpi ?
									                  {transaction_write_bytes, 1'b0} :
									                  {transaction_write_bytes, 3'b000};
									dq_out         <= transaction_qpi ? write_data[23:20] :
									                                  {3'b000, write_data[23]};
								end
								else if (transaction_read) begin
									dq_oe <= 1'b0;
									if (transaction_qpi) begin
										state      <= ST_DUMMY;
										units_left <= (transaction_command == 8'h0B) ?
										              6'd4 : 6'd6;
									end
									else begin
										state      <= ST_READ;
										units_left <= {transaction_read_bytes, 3'b000};
									end
								end
								else begin_hold();
							end
							else begin
								units_left <= units_left - 1'b1;
								if (transaction_qpi) begin
									shift_register <= {shift_register[19:0], 4'd0};
									dq_out <= shift_register[19:16];
								end
								else begin
									shift_register <= {shift_register[22:0], 1'b0};
									dq_out <= {3'b000, shift_register[22]};
								end
							end
						end

						ST_DUMMY: begin
							if (units_left == 1) begin
								state      <= ST_READ;
								units_left <= {transaction_read_bytes, 1'b0};
							end
							else units_left <= units_left - 1'b1;
						end

						ST_WRITE: begin
							if (units_left == 1) begin_hold();
							else begin
								units_left <= units_left - 1'b1;
								if (transaction_qpi) begin
									shift_register <= {shift_register[19:0], 4'd0};
									dq_out <= shift_register[19:16];
								end
								else begin
									shift_register <= {shift_register[22:0], 1'b0};
									dq_out <= {3'b000, shift_register[22]};
								end
							end
						end

						ST_READ: begin
							if (transaction_qpi) begin
								// With divider=1, dq_sample is written by a separate
								// posedge process on this same controller edge.  Using
								// it here would therefore consume the previous nibble
								// (01234A instead of 1234A5).  Capture dq_in directly
								// just before the registered external clock falls.
								read_data <= {read_data[43:0],
								              (half_divider == 6'd1) ? dq_in : dq_sample};
							end
							else
								read_data <= {read_data[46:0], dq_sample[1]};

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
