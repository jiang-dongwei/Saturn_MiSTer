`timescale 1ns/1ps

// Behavioral model for the exact command subset used by psram_diag_core.
// It is deliberately protocol-oriented rather than a full timing model.
module psram_diag_model
#(
	parameter [47:0] ID_VALUE = 48'h0D5D_0D5D_0D5D,
	parameter         FORCE_BAD_READ = 0,
	parameter         FORCE_SHORT_TAIL = 0,
	parameter         FORCE_SHORT_WRITE_TAIL = 0,
	parameter         FORCE_BAD_WRITE = 0,
	// Optional end-to-end DQ delay used by the fastest-read stress test.  The
	// delay includes the memory clock-to-output, the HDMI path and FPGA input
	// settling.  Normal regression instances leave it at zero.
	parameter integer READ_OUTPUT_DELAY_NS = 0,
	parameter [22:0]  ADDRESS_MASK = 23'h7FFFFF
)
(
	input       ce_n,
	input       sclk,
	inout [3:0] dq
);

localparam [3:0] M_SPI_CMD   = 4'd0;
localparam [3:0] M_SPI_ADDR  = 4'd1;
localparam [3:0] M_SPI_ID    = 4'd2;
localparam [3:0] M_QPI_CMD   = 4'd3;
localparam [3:0] M_QPI_ADDR  = 4'd4;
localparam [3:0] M_QPI_WRITE = 4'd5;
localparam [3:0] M_QPI_DUMMY = 4'd6;
localparam [3:0] M_QPI_READ  = 4'd7;
localparam [3:0] M_SPI_WRITE = 4'd8;
localparam [3:0] M_SPI_READ  = 4'd9;

reg [7:0] memory [0:8388607];
reg       qpi_mode = 1'b0;
reg       reset_enabled = 1'b0;
reg [3:0] mode = M_SPI_CMD;
reg [7:0] command_shift = 8'd0;
reg [5:0] count = 6'd0;
reg [23:0] address_shift = 24'd0;
reg [23:0] current_address = 24'd0;
reg [7:0] write_byte = 8'd0;
reg [3:0] dq_out = 4'd0;
reg       dq_oe = 1'b0;
reg [1:0] read_nibble = 2'd0;
reg [5:0] id_bit = 6'd0;
reg       short_tail_fault_fired = 1'b0;
reg       short_write_fault_fired = 1'b0;

assign dq = dq_oe ? dq_out : 4'bzzzz;

always @(negedge ce_n) begin
	command_shift <= 8'd0;
	address_shift <= 24'd0;
	count         <= 6'd0;
	dq_oe         <= 1'b0;
	dq_out        <= 4'd0;
	read_nibble   <= 2'd0;
	id_bit        <= 6'd0;
	mode          <= qpi_mode ? M_QPI_CMD : M_SPI_CMD;
end

always @(posedge ce_n) dq_oe <= #6 1'b0;

always @(posedge sclk) begin
	if (!ce_n) begin
		case (mode)
			M_SPI_CMD: begin
				command_shift <= {command_shift[6:0], dq[0]};
				if (count == 6'd7) begin
					count <= 6'd0;
					case ({command_shift[6:0], dq[0]})
						8'h66: reset_enabled <= 1'b1;
						8'h99: begin
							if (reset_enabled) begin
								qpi_mode <= 1'b0;
								reset_enabled <= 1'b0;
							end
						end
						8'h35: qpi_mode <= 1'b1;
						8'h9F, 8'h02, 8'h03: mode <= M_SPI_ADDR;
						default: begin end
					endcase
				end
				else count <= count + 1'b1;
			end

			M_SPI_ADDR: begin
				address_shift <= {address_shift[22:0], dq[0]};
				if (count == 6'd23) begin
					count  <= 6'd0;
					current_address <= {address_shift[22:0], dq[0]} &
					                   {1'b0, ADDRESS_MASK};
					if (command_shift == 8'h9F) begin
						id_bit <= 6'd0;
						mode   <= M_SPI_ID;
					end
					else if (command_shift == 8'h02) begin
						write_byte <= 8'd0;
						mode <= M_SPI_WRITE;
					end
					else mode <= M_SPI_READ;
				end
				else count <= count + 1'b1;
			end

			M_SPI_ID: begin
				if (id_bit < 6'd47) id_bit <= id_bit + 1'b1;
			end

			M_SPI_WRITE: begin
				write_byte <= {write_byte[6:0], dq[0]};
				if (count == 6'd7) begin
					memory[current_address] <= {write_byte[6:0], dq[0]};
					current_address <= (current_address + 1'b1) &
					                   {1'b0, ADDRESS_MASK};
					count <= 6'd0;
				end
				else count <= count + 1'b1;
			end

			M_SPI_READ: begin
				if (count == 6'd7) begin
					current_address <= (current_address + 1'b1) &
					                   {1'b0, ADDRESS_MASK};
					count <= 6'd0;
				end
				else count <= count + 1'b1;
			end

			M_QPI_CMD: begin
				if (count == 0) begin
					command_shift[7:4] <= dq;
					count <= 6'd1;
				end
				else begin
					command_shift[3:0] <= dq;
					count <= 6'd0;
					if ({command_shift[7:4], dq} == 8'hF5) begin
						qpi_mode <= 1'b0;
						mode <= M_SPI_CMD;
					end
					else mode <= M_QPI_ADDR;
				end
			end

			M_QPI_ADDR: begin
				address_shift <= {address_shift[19:0], dq};
				if (count == 6'd5) begin
					current_address <= {address_shift[19:0], dq} & {1'b0, ADDRESS_MASK};
					count <= 6'd0;
					if (command_shift == 8'h02) mode <= M_QPI_WRITE;
					else mode <= M_QPI_DUMMY;
				end
				else count <= count + 1'b1;
			end

			M_QPI_WRITE: begin
				if (!count[0]) begin
					write_byte[7:4] <= dq;
					count <= count + 1'b1;
				end
				else begin
					write_byte[3:0] <= dq;
					if (FORCE_SHORT_WRITE_TAIL && !short_write_fault_fired &&
					    (current_address[22:0] == 23'h000101) &&
					    ({write_byte[7:4], dq} == 8'hFF)) begin
						memory[current_address] <= 8'hF5;
						short_write_fault_fired <= 1'b1;
					end
					else if (FORCE_BAD_WRITE &&
					    (current_address[22:0] == 23'h000101) &&
					    ({write_byte[7:4], dq} == 8'hFF))
						memory[current_address] <= 8'hF5;
					else
						memory[current_address] <= {write_byte[7:4], dq};
					current_address <= (current_address + 1'b1) & {1'b0, ADDRESS_MASK};
					count <= count + 1'b1;
				end
			end

			M_QPI_DUMMY: begin
				if (count == ((command_shift == 8'h0B) ? 6'd3 : 6'd5)) begin
					mode <= M_QPI_READ;
					count <= 6'd0;
					read_nibble <= 2'd0;
				end
				else count <= count + 1'b1;
			end

			M_QPI_READ: begin
				if (read_nibble == 2'd3) begin
					current_address <= (current_address + 2'd2) & {1'b0, ADDRESS_MASK};
					read_nibble <= 2'd0;
				end
				else read_nibble <= read_nibble + 1'b1;
			end

			default: begin end
		endcase
	end
end

always @(negedge sclk) begin
	if (!ce_n) begin
		case (mode)
			M_SPI_ID: begin
				dq_oe <= #(READ_OUTPUT_DELAY_NS) 1'b1;
				dq_out <= #(READ_OUTPUT_DELAY_NS)
				          {2'b00, ID_VALUE[47-id_bit], 1'b0};
			end

			M_SPI_READ: begin
				dq_oe <= #(READ_OUTPUT_DELAY_NS) 1'b1;
				dq_out <= #(READ_OUTPUT_DELAY_NS)
				          {2'b00, memory[current_address][7-count[2:0]], 1'b0};
			end

			M_QPI_READ: begin
				dq_oe <= #(READ_OUTPUT_DELAY_NS) 1'b1;
				case (read_nibble)
					2'd0: dq_out <= #(READ_OUTPUT_DELAY_NS)
					                  memory[current_address][7:4];
					2'd1: dq_out <= #(READ_OUTPUT_DELAY_NS)
					                  memory[current_address][3:0];
					2'd2: dq_out <= #(READ_OUTPUT_DELAY_NS)
					                  memory[current_address + 1'b1][7:4];
					default: begin
						if (FORCE_SHORT_TAIL && !short_tail_fault_fired &&
						    (memory[current_address] == 8'hFF) &&
						    (memory[current_address + 1'b1] == 8'hFF)) begin
							dq_out <= #(READ_OUTPUT_DELAY_NS) 4'h5;
							short_tail_fault_fired <= 1'b1;
						end
						else if (FORCE_BAD_READ)
							dq_out <= #(READ_OUTPUT_DELAY_NS)
							          ~memory[current_address + 1'b1][3:0];
						else
							dq_out <= #(READ_OUTPUT_DELAY_NS)
							          memory[current_address + 1'b1][3:0];
					end
				endcase
			end

			default: dq_oe <= 1'b0;
		endcase
	end
end

endmodule
