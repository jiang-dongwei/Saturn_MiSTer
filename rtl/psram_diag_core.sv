// Staged hardware diagnostic for an 8 MiB SPI/QPI PSRAM.
//
// Stage codes shown on screen:
//   01 SPI Read-ID response
//   03 basic QPI write/read
//   04 data patterns
//   41 short-read tail fault (extended read recovered the target word)
//   42 extended read still bad (stored/write/data-path fault)
//   43 extended write recovered the target word (short-write tail fault)
//   44 extended write still bad (run raw alignment trace)
//   45 raw 24-bit alignment trace; ADDRESS shows the returned 24 bits
//   51 SPI-write/QPI-read data map; three asymmetric raw results are shown
//   52 QPI read command matrix; EB/6 is compared with 0B/4 at two speeds
//   53 DDIO source-synchronous QPI read map at 33.8688 MHz
//   54 divided DDIO clock/reset recovery trace
//   55 same-cell SPI/QPI cross-speed read matrix
//   56 50%-duty logic-analyzer trace: SPI 8.47 and repeated QPI 4.23 MHz
//   58 divider=1 late-capture fix, QPI ladder at 8.47/16.93/33.87 MHz
//   05 address walking/4 MiB alias rejection
//   06..0A frequency sweep from 1.06 through 33.87 MHz
module psram_diag_core
#(
	parameter integer POWERUP_CYCLES = 11000,
	parameter         DDIO_TRACE_MODE = 1'b0
)
(
	input             clk,
	input             reset,
	input       [1:0] mode,
	input       [2:0] max_speed_select,

	output reg  [1:0] result_code, // 0 running, 1 pass, 2 fail
	output reg  [7:0] stage_code,
	output reg [47:0] id_value,
	output reg        id_kgd_ok,
	output reg [23:0] failure_address,
	output reg [15:0] expected_data,
	output reg [15:0] actual_data,
	output reg  [2:0] speed_index,
	output reg  [7:0] diagnostic_leds,
	output            activity,
	output reg [23:0] matrix_a,
	output reg [23:0] matrix_b,
	output reg [23:0] matrix_c,

	output            PSRAM_CLK,
	output            PSRAM_CE_N,
	inout       [3:0] PSRAM_DQ
);

localparam [5:0] S_POWER          = 6'd0;
localparam [5:0] S_F5_START       = 6'd1;
localparam [5:0] S_F5_WAIT        = 6'd2;
localparam [5:0] S_66_START       = 6'd3;
localparam [5:0] S_66_WAIT        = 6'd4;
localparam [5:0] S_99_START       = 6'd5;
localparam [5:0] S_99_WAIT        = 6'd6;
localparam [5:0] S_ID_START       = 6'd7;
localparam [5:0] S_ID_WAIT        = 6'd8;
localparam [5:0] S_QPI_START      = 6'd9;
localparam [5:0] S_QPI_WAIT       = 6'd10;
localparam [5:0] S_BASIC_WR_START = 6'd11;
localparam [5:0] S_BASIC_WR_WAIT  = 6'd12;
localparam [5:0] S_BASIC_RD_START = 6'd13;
localparam [5:0] S_BASIC_RD_WAIT  = 6'd14;
localparam [5:0] S_DATA_WR_START  = 6'd15;
localparam [5:0] S_DATA_WR_WAIT   = 6'd16;
localparam [5:0] S_DATA_RD_START  = 6'd17;
localparam [5:0] S_DATA_RD_WAIT   = 6'd18;
localparam [5:0] S_ADDR_WR_START  = 6'd19;
localparam [5:0] S_ADDR_WR_WAIT   = 6'd20;
localparam [5:0] S_ADDR_RD_START  = 6'd21;
localparam [5:0] S_ADDR_RD_WAIT   = 6'd22;
localparam [5:0] S_FREQ_WR_START  = 6'd23;
localparam [5:0] S_FREQ_WR_WAIT   = 6'd24;
localparam [5:0] S_FREQ_RD_START  = 6'd25;
localparam [5:0] S_FREQ_RD_WAIT   = 6'd26;
localparam [5:0] S_PASS           = 6'd27;
localparam [5:0] S_FAIL           = 6'd28;
localparam [5:0] S_DATA_EXT_RD_START = 6'd29;
localparam [5:0] S_DATA_EXT_RD_WAIT  = 6'd30;
localparam [5:0] S_DATA_EXT_WR_START = 6'd31;
localparam [5:0] S_DATA_EXT_WR_WAIT  = 6'd32;
localparam [5:0] S_DATA_EXT_WR_RD_START = 6'd33;
localparam [5:0] S_DATA_EXT_WR_RD_WAIT  = 6'd34;
localparam [5:0] S_TRACE_TAIL_WR_START  = 6'd35;
localparam [5:0] S_TRACE_TAIL_WR_WAIT   = 6'd36;
localparam [5:0] S_TRACE_DATA_WR_START  = 6'd37;
localparam [5:0] S_TRACE_DATA_WR_WAIT   = 6'd38;
localparam [5:0] S_TRACE_DATA_RD_START  = 6'd39;
localparam [5:0] S_TRACE_DATA_RD_WAIT   = 6'd40;
localparam [5:0] S_MAP_EXIT_START        = 6'd41;
localparam [5:0] S_MAP_EXIT_WAIT         = 6'd42;
localparam [5:0] S_MAP_A_WR_START        = 6'd43;
localparam [5:0] S_MAP_A_WR_WAIT         = 6'd44;
localparam [5:0] S_MAP_A_GUARD_START     = 6'd45;
localparam [5:0] S_MAP_A_GUARD_WAIT      = 6'd46;
localparam [5:0] S_MAP_B_WR_START        = 6'd47;
localparam [5:0] S_MAP_B_WR_WAIT         = 6'd48;
localparam [5:0] S_MAP_B_GUARD_START     = 6'd49;
localparam [5:0] S_MAP_B_GUARD_WAIT      = 6'd50;
localparam [5:0] S_MAP_C_WR_START        = 6'd51;
localparam [5:0] S_MAP_C_WR_WAIT         = 6'd52;
localparam [5:0] S_MAP_C_GUARD_START     = 6'd53;
localparam [5:0] S_MAP_C_GUARD_WAIT      = 6'd54;
localparam [5:0] S_MAP_ENTER_START       = 6'd55;
localparam [5:0] S_MAP_ENTER_WAIT        = 6'd56;
localparam [5:0] S_MAP_A_RD_START        = 6'd57;
localparam [5:0] S_MAP_A_RD_WAIT         = 6'd58;
localparam [5:0] S_MAP_B_RD_START        = 6'd59;
localparam [5:0] S_MAP_B_RD_WAIT         = 6'd60;
localparam [5:0] S_MAP_C_RD_START        = 6'd61;
localparam [5:0] S_MAP_C_RD_WAIT         = 6'd62;
localparam [5:0] S_MATRIX_HOLD           = 6'd63;

reg [5:0] state;
integer power_count;
reg [4:0] test_index;
reg [15:0] short_read_data;
reg [15:0] extended_read_data;

reg        bus_start;
reg        bus_qpi;
reg  [7:0] bus_command;
reg        bus_address_enable;
reg [23:0] bus_address;
reg        bus_write_enable;
reg [23:0] bus_write_data;
reg  [2:0] bus_write_bytes;
reg        bus_read_enable;
reg  [2:0] bus_read_bytes;
reg  [5:0] bus_half_divider;
wire       bus_busy;
wire       bus_done;
wire [47:0] bus_read_data;
wire  [3:0] bus_dq_sample;

assign activity = bus_busy;

psram_diag_bus bus
(
	.clk(clk),
	.reset(reset),
	.start(bus_start),
	.qpi(bus_qpi),
	.command(bus_command),
	.address_enable(bus_address_enable),
	.address(bus_address),
	.write_enable(bus_write_enable),
	.write_data(bus_write_data),
	.write_bytes(bus_write_bytes),
	.read_enable(bus_read_enable),
	.read_bytes(bus_read_bytes),
	.half_divider(bus_half_divider),
	.busy(bus_busy),
	.done(bus_done),
	.read_data(bus_read_data),
	.dq_sample(bus_dq_sample),
	.PSRAM_CLK(PSRAM_CLK),
	.PSRAM_CE_N(PSRAM_CE_N),
	.PSRAM_DQ(PSRAM_DQ)
);

function [15:0] data_pattern;
	input [4:0] index;
	begin
		case (index)
			0: data_pattern = 16'h0000;
			1: data_pattern = 16'hFFFF;
			2: data_pattern = 16'hAAAA;
			3: data_pattern = 16'h5555;
			4: data_pattern = 16'h00FF;
			5: data_pattern = 16'hFF00;
			6: data_pattern = 16'h0F0F;
			7: data_pattern = 16'hF0F0;
			8: data_pattern = 16'h0001;
			9: data_pattern = 16'h8000;
			default: data_pattern = 16'hFFFF;
		endcase
	end
endfunction

function [23:0] data_address;
	input [4:0] index;
	begin
		// First isolate data patterns at one cell, then reprobe the
		// original failing FFFF location as index 10.
		data_address = (index < 5'd10) ? 24'h000100 : 24'h000102;
	end
endfunction

function [23:0] walking_address;
	input [4:0] index;
	begin
		if (index == 0) walking_address = 24'h000000;
		else walking_address = 24'h000001 << index;
	end
endfunction

function [15:0] walking_pattern;
	input [4:0] index;
	begin
		walking_pattern = 16'hA500 | {11'd0, index};
	end
endfunction

function [5:0] divider_for_speed;
	input [2:0] index;
	begin
		case (index)
			// A complete 18-clock QPI read must keep CE# low for less
			// than the LY68L6400 tCEM maximum of 8 us.  2.8224 MHz is
			// the slowest diagnostic rate with comfortable margin.
			0: divider_for_speed = 6'd12; // 2.8224 MHz
			1: divider_for_speed = 6'd8;  // 4.2336 MHz
			2: divider_for_speed = 6'd4;  // 8.4672 MHz
			3: divider_for_speed = 6'd2;  // 16.9344 MHz
			default: divider_for_speed = 6'd1; // 33.8688 MHz
		endcase
	end
endfunction

function [2:0] selected_speed_limit;
	input [2:0] selection;
	begin
		case (selection)
			0: selected_speed_limit = 3'd4;
			1: selected_speed_limit = 3'd3;
			2: selected_speed_limit = 3'd2;
			3: selected_speed_limit = 3'd1;
			default: selected_speed_limit = 3'd0;
		endcase
	end
endfunction

task configure_command;
	input       use_qpi;
	input [7:0] cmd;
	begin
		bus_qpi            <= use_qpi;
		bus_command        <= cmd;
		bus_address_enable <= 1'b0;
		bus_address        <= 24'd0;
		bus_write_enable   <= 1'b0;
		bus_write_data     <= 24'd0;
		bus_write_bytes    <= 3'd0;
		bus_read_enable    <= 1'b0;
		bus_read_bytes     <= 3'd0;
		bus_start          <= 1'b1;
	end
endtask

task configure_byte_write;
	input [23:0] address_value;
	input  [7:0] data_value;
	input  [5:0] divider_value;
	begin
		bus_qpi            <= 1'b1;
		bus_command        <= 8'h02;
		bus_address_enable <= 1'b1;
		bus_address        <= address_value;
		bus_write_enable   <= 1'b1;
		bus_write_data     <= {data_value, 16'd0};
		bus_write_bytes    <= 3'd1;
		bus_read_enable    <= 1'b0;
		bus_read_bytes     <= 3'd0;
		bus_half_divider   <= divider_value;
		bus_start          <= 1'b1;
	end
endtask

task configure_byte_read;
	input [23:0] address_value;
	input  [5:0] divider_value;
	begin
		bus_qpi            <= 1'b1;
		bus_command        <= 8'hEB;
		bus_address_enable <= 1'b1;
		bus_address        <= address_value;
		bus_write_enable   <= 1'b0;
		bus_write_data     <= 24'd0;
		bus_write_bytes    <= 3'd0;
		bus_read_enable    <= 1'b1;
		bus_read_bytes     <= 3'd1;
		bus_half_divider   <= divider_value;
		bus_start          <= 1'b1;
	end
endtask

task configure_spi_write;
	input [23:0] address_value;
	input [23:0] data_value;
	input  [5:0] divider_value;
	begin
		bus_qpi            <= 1'b0;
		bus_command        <= 8'h02;
		bus_address_enable <= 1'b1;
		bus_address        <= address_value;
		bus_write_enable   <= 1'b1;
		bus_write_data     <= data_value;
		bus_write_bytes    <= 3'd3;
		bus_read_enable    <= 1'b0;
		bus_read_bytes     <= 3'd0;
		bus_half_divider   <= divider_value;
		bus_start          <= 1'b1;
	end
endtask

task configure_spi_read;
	input [23:0] address_value;
	input  [5:0] divider_value;
	begin
		bus_qpi            <= 1'b0;
		bus_command        <= 8'h03;
		bus_address_enable <= 1'b1;
		bus_address        <= address_value;
		bus_write_enable   <= 1'b0;
		bus_write_data     <= 24'd0;
		bus_write_bytes    <= 3'd0;
		bus_read_enable    <= 1'b1;
		bus_read_bytes     <= 3'd3;
		// SPI needs 56 clocks for command, address and three data bytes.
		// 8.4672 MHz keeps CE# low below the 8 us tCEM limit.
		bus_half_divider   <= divider_value;
		bus_start          <= 1'b1;
	end
endtask

task configure_write;
	input [23:0] address_value;
	input [15:0] data_value;
	input  [5:0] divider_value;
	begin
		bus_qpi            <= 1'b1;
		bus_command        <= 8'h02;
		bus_address_enable <= 1'b1;
		bus_address        <= address_value;
		bus_write_enable   <= 1'b1;
		bus_write_data     <= {data_value, 8'd0};
		bus_write_bytes    <= 3'd2;
		bus_read_enable    <= 1'b0;
		bus_read_bytes     <= 3'd0;
		bus_half_divider   <= divider_value;
		bus_start          <= 1'b1;
	end
endtask

task configure_read;
	input [23:0] address_value;
	input  [5:0] divider_value;
	begin
		bus_qpi            <= 1'b1;
		bus_command        <= 8'hEB;
		bus_address_enable <= 1'b1;
		bus_address        <= address_value;
		bus_write_enable   <= 1'b0;
		bus_write_data     <= 24'd0;
		bus_write_bytes    <= 3'd0;
		bus_read_enable    <= 1'b1;
		bus_read_bytes     <= 3'd2;
		bus_half_divider   <= divider_value;
		bus_start          <= 1'b1;
	end
endtask

task configure_extended_write;
	input [23:0] address_value;
	input [15:0] data_value;
	input  [7:0] guard_byte;
	input  [5:0] divider_value;
	begin
		bus_qpi            <= 1'b1;
		bus_command        <= 8'h02;
		bus_address_enable <= 1'b1;
		bus_address        <= address_value;
		bus_write_enable   <= 1'b1;
		// The target word is followed by a guard byte, so it is not at
		// the end of the write transaction.
		bus_write_data     <= {data_value, guard_byte};
		bus_write_bytes    <= 3'd3;
		bus_read_enable    <= 1'b0;
		bus_read_bytes     <= 3'd0;
		bus_half_divider   <= divider_value;
		bus_start          <= 1'b1;
	end
endtask

task configure_extended_read;
	input [23:0] address_value;
	input  [5:0] divider_value;
	begin
		bus_qpi            <= 1'b1;
		bus_command        <= 8'hEB;
		bus_address_enable <= 1'b1;
		bus_address        <= address_value;
		bus_write_enable   <= 1'b0;
		bus_write_data     <= 16'd0;
		bus_read_enable    <= 1'b1;
		// Read one extra byte so the target 16-bit word is no longer
		// located at the end of the QPI transaction.
		bus_read_bytes     <= 3'd3;
		bus_half_divider   <= divider_value;
		bus_start          <= 1'b1;
	end
endtask

task configure_qpi_0b_read;
	input [23:0] address_value;
	input  [5:0] divider_value;
	begin
		bus_qpi            <= 1'b1;
		bus_command        <= 8'h0B;
		bus_address_enable <= 1'b1;
		bus_address        <= address_value;
		bus_write_enable   <= 1'b0;
		bus_write_data     <= 16'd0;
		bus_read_enable    <= 1'b1;
		bus_read_bytes     <= 3'd3;
		bus_half_divider   <= divider_value;
		bus_start          <= 1'b1;
	end
endtask

task stop_with_failure;
	input  [7:0] failed_stage;
	input [23:0] failed_address;
	input [15:0] wanted_data;
	input [15:0] received_data;
	begin
		stage_code       <= failed_stage;
		failure_address  <= failed_address;
		expected_data    <= wanted_data;
		actual_data      <= received_data;
		result_code      <= 2'd2;
		diagnostic_leds[7] <= 1'b1;
		state             <= S_FAIL;
	end
endtask

always @(posedge clk) begin
	bus_start <= 1'b0;

	if (reset) begin
		state              <= S_POWER;
		power_count        <= 0;
		test_index         <= 5'd0;
		short_read_data    <= 16'd0;
		extended_read_data <= 16'd0;
		matrix_a           <= 24'd0;
		matrix_b           <= 24'd0;
		matrix_c           <= 24'd0;
		result_code        <= 2'd0;
		stage_code         <= 8'd0;
		id_value           <= 48'd0;
		id_kgd_ok          <= 1'b0;
		failure_address    <= 24'd0;
		expected_data      <= 16'd0;
		actual_data        <= 16'd0;
		speed_index        <= 3'd0;
		diagnostic_leds     <= 8'd0;
		bus_start          <= 1'b0;
		bus_qpi            <= 1'b0;
		bus_command        <= 8'd0;
		bus_address_enable <= 1'b0;
		bus_address        <= 24'd0;
		bus_write_enable   <= 1'b0;
		bus_write_data     <= 24'd0;
		bus_write_bytes    <= 3'd0;
		bus_read_enable    <= 1'b0;
		bus_read_bytes     <= 3'd0;
		bus_half_divider   <= 6'd32;
	end
	else begin
		case (state)
			S_POWER: begin
				if (power_count >= POWERUP_CYCLES) begin
					diagnostic_leds[0] <= 1'b1;
					stage_code <= 8'h01;
					state <= S_F5_START;
				end
				else power_count <= power_count + 1;
			end

			// An FPGA-only reload may find the chip already in QPI.  F5 is
			// harmless in SPI and exits QPI, after which 66/99 establishes a
			// known SPI state.
			S_F5_START: begin
				bus_half_divider <= 6'd4;
				configure_command(1'b1, 8'hF5);
				state <= S_F5_WAIT;
			end
			S_F5_WAIT: if (bus_done) state <= S_66_START;

			S_66_START: begin
				configure_command(1'b0, 8'h66);
				state <= S_66_WAIT;
			end
			S_66_WAIT: if (bus_done) state <= S_99_START;

			S_99_START: begin
				configure_command(1'b0, 8'h99);
				state <= S_99_WAIT;
			end
			S_99_WAIT: if (bus_done) state <= S_ID_START;

			S_ID_START: begin
				bus_qpi            <= 1'b0;
				bus_command        <= 8'h9F;
				bus_address_enable <= 1'b1;
				bus_address        <= 24'd0;
				bus_write_enable   <= 1'b0;
				bus_read_enable    <= 1'b1;
				// Only the two-byte EID/KGD pair is required.  Reading
				// six bytes at the old 1.06 MHz diagnostic rate violated
				// the device's 8 us maximum CE#-low interval.
				bus_read_bytes     <= 3'd2;
				bus_half_divider   <= 6'd4;
				bus_start          <= 1'b1;
				state              <= S_ID_WAIT;
			end

			S_ID_WAIT: if (bus_done) begin
				id_value  <= {bus_read_data[15:0], 32'd0};
				id_kgd_ok <= (bus_read_data[7:0] == 8'h5D);
				actual_data <= bus_read_data[15:0];
				expected_data <= 16'h005D; // Working Known-Good-Die byte.

				if ((bus_read_data[15:0] == 16'h0000) ||
				    (bus_read_data[15:0] == 16'hFFFF)) begin
					diagnostic_leds[1] <= 1'b0;
					if (mode == 2'd1) begin
						result_code <= 2'd2;
						diagnostic_leds[7] <= 1'b1;
						state <= S_F5_START;
					end
					else stop_with_failure(8'h01, 24'd0, 16'h005D,
					                       bus_read_data[15:0]);
				end
				else begin
					diagnostic_leds[1] <= 1'b1;
					diagnostic_leds[7] <= 1'b0;
					result_code <= 2'd0;
					if (mode == 2'd1) state <= S_F5_START;
					else state <= S_QPI_START;
				end
			end

			S_QPI_START: begin
				configure_command(1'b0, 8'h35);
				state <= S_QPI_WAIT;
			end
			S_QPI_WAIT: if (bus_done) begin
				if (DDIO_TRACE_MODE) begin
					stage_code <= 8'h58;
					speed_index <= 3'd4;
					result_code <= 2'd0;
					matrix_a <= 24'd0;
					matrix_b <= 24'd0;
					matrix_c <= 24'd0;
					state <= S_MAP_EXIT_START;
				end
				else begin
					stage_code <= 8'h03;
					state <= S_BASIC_WR_START;
				end
			end

			S_BASIC_WR_START: begin
				failure_address <= 24'h000200;
				expected_data <= 16'hA55A;
				configure_write(24'h000200, 16'hA55A, 6'd12);
				state <= S_BASIC_WR_WAIT;
			end
			S_BASIC_WR_WAIT: if (bus_done) begin
				if (mode == 2'd2) begin
					diagnostic_leds[2] <= 1'b1;
					state <= S_BASIC_WR_START;
				end
				else state <= S_BASIC_RD_START;
			end

			S_BASIC_RD_START: begin
				configure_read(24'h000200, 6'd12);
				state <= S_BASIC_RD_WAIT;
			end
			S_BASIC_RD_WAIT: if (bus_done) begin
				actual_data <= bus_read_data[15:0];
				if (bus_read_data[15:0] != 16'hA55A) begin
					if (mode == 2'd3) begin
						result_code <= 2'd2;
						diagnostic_leds[7] <= 1'b1;
						state <= S_BASIC_RD_START;
					end
					else stop_with_failure(8'h03, 24'h000200, 16'hA55A,
					                       bus_read_data[15:0]);
				end
				else begin
					diagnostic_leds[2] <= 1'b1;
					diagnostic_leds[7] <= 1'b0;
					result_code <= 2'd0;
					if (mode == 2'd3) state <= S_BASIC_RD_START;
					else begin
						stage_code <= 8'h04;
						test_index <= 5'd0;
						state <= S_DATA_WR_START;
					end
				end
			end

			S_DATA_WR_START: begin
				failure_address <= data_address(test_index);
				expected_data <= data_pattern(test_index);
				configure_write(data_address(test_index), data_pattern(test_index), 6'd12);
				state <= S_DATA_WR_WAIT;
			end
			S_DATA_WR_WAIT: if (bus_done) state <= S_DATA_RD_START;

			S_DATA_RD_START: begin
				configure_read(data_address(test_index), 6'd12);
				state <= S_DATA_RD_WAIT;
			end
			S_DATA_RD_WAIT: if (bus_done) begin
				actual_data <= bus_read_data[15:0];
				if (bus_read_data[15:0] != data_pattern(test_index)) begin
					// The hardware failure is deterministic on FFFF and only
					// affects the final nibble of a two-byte transaction.  Keep
					// that result, then read an extra byte to move the same word
					// away from the transaction tail.
					if ((test_index == 5'd1) &&
					    (data_pattern(test_index) == 16'hFFFF)) begin
						short_read_data <= bus_read_data[15:0];
						state <= S_DATA_EXT_RD_START;
					end
					else stop_with_failure(8'h04, data_address(test_index),
					                       data_pattern(test_index), bus_read_data[15:0]);
				end
				else if (test_index == 5'd10) begin
					diagnostic_leds[3] <= 1'b1;
					stage_code <= 8'h05;
					test_index <= 5'd0;
					state <= S_ADDR_WR_START;
				end
				else begin
					test_index <= test_index + 1'b1;
					state <= S_DATA_WR_START;
				end
			end

			S_DATA_EXT_RD_START: begin
				configure_extended_read(data_address(test_index), 6'd12);
				state <= S_DATA_EXT_RD_WAIT;
			end

			S_DATA_EXT_RD_WAIT: if (bus_done) begin
				// Three returned bytes occupy read_data[23:0].  The original
				// target word is the first two bytes at [23:8].
				if (bus_read_data[23:8] == data_pattern(test_index))
					stop_with_failure(8'h41, data_address(test_index),
					                  data_pattern(test_index), short_read_data);
				else begin
					extended_read_data <= bus_read_data[23:8];
					stage_code <= 8'h42;
					state <= S_DATA_EXT_WR_START;
				end
			end

			S_DATA_EXT_WR_START: begin
				configure_extended_write(data_address(test_index),
				                         data_pattern(test_index), 8'h00, 6'd12);
				state <= S_DATA_EXT_WR_WAIT;
			end
			S_DATA_EXT_WR_WAIT: if (bus_done) state <= S_DATA_EXT_WR_RD_START;

			S_DATA_EXT_WR_RD_START: begin
				configure_extended_read(data_address(test_index), 6'd12);
				state <= S_DATA_EXT_WR_RD_WAIT;
			end

			S_DATA_EXT_WR_RD_WAIT: if (bus_done) begin
				if (bus_read_data[23:8] == data_pattern(test_index))
					stop_with_failure(8'h43, data_address(test_index),
					                  data_pattern(test_index), extended_read_data);
				else begin
					// FFFF00 returning as FFF0 can be explained by a one-nibble
					// read-start slip.  Run a non-symmetric stream before stopping
					// so hardware can expose the exact 24-bit alignment.
					stage_code <= 8'h44;
					state <= S_TRACE_TAIL_WR_START;
				end
			end

			// Seed the byte after the 3-byte trace with CD EF.  If the read
			// capture starts one nibble late, 12 34 A5 should appear as
			// 23 4A 5C rather than 12 34 A5.
			S_TRACE_TAIL_WR_START: begin
				configure_write(24'h000103, 16'hCDEF, 6'd12);
				state <= S_TRACE_TAIL_WR_WAIT;
			end
			S_TRACE_TAIL_WR_WAIT: if (bus_done) state <= S_TRACE_DATA_WR_START;

			S_TRACE_DATA_WR_START: begin
				configure_extended_write(24'h000100, 16'h1234, 8'hA5, 6'd12);
				state <= S_TRACE_DATA_WR_WAIT;
			end
			S_TRACE_DATA_WR_WAIT: if (bus_done) state <= S_TRACE_DATA_RD_START;

			S_TRACE_DATA_RD_START: begin
				configure_extended_read(24'h000100, 6'd12);
				state <= S_TRACE_DATA_RD_WAIT;
			end
			S_TRACE_DATA_RD_WAIT: if (bus_done) begin
				// The mixed trace must be aligned before the SPI-write/QPI-read
				// data map is meaningful.
				if (bus_read_data[23:0] == 24'h1234A5) begin
					stage_code <= 8'h52;
					speed_index <= 3'd2;
					result_code <= 2'd0;
					matrix_a <= 24'd0;
					matrix_b <= 24'd0;
					matrix_c <= 24'd0;
					state <= S_MAP_EXIT_START;
				end
				else
					stop_with_failure(8'h45, bus_read_data[23:0],
					                  16'h1234, bus_read_data[23:8]);
			end

			// Leave QPI and seed known data through SPI. Stage 58 keeps the
			// restored square-clock engine and reads the same address/data with
			// the same QPI EB command at 8.47, 16.93 and 33.87 MHz. Thus speed is
			// the only changed variable. The non-trace path retains the Stage 52
			// EB/0B command matrix.
			S_MAP_EXIT_START: begin
				configure_command(1'b1, 8'hF5);
				state <= S_MAP_EXIT_WAIT;
			end
			S_MAP_EXIT_WAIT: if (bus_done) state <= S_MAP_A_WR_START;

			S_MAP_A_WR_START: begin
				configure_spi_write(24'h000100, 24'h1234A5, 6'd4);
				state <= S_MAP_A_WR_WAIT;
			end
			S_MAP_A_WR_WAIT: if (bus_done) state <= S_MAP_A_GUARD_START;
			S_MAP_A_GUARD_START: begin
				configure_spi_write(24'h000103, 24'hCDEF5A, 6'd4);
				state <= S_MAP_A_GUARD_WAIT;
			end
			S_MAP_A_GUARD_WAIT: if (bus_done) begin
				if (DDIO_TRACE_MODE)
					state <= S_MAP_ENTER_START;
				else
					state <= S_MAP_B_WR_START;
			end

			S_MAP_B_WR_START: begin
				if (DDIO_TRACE_MODE)
					configure_spi_read(24'h000100, 6'd4);
				else
					configure_spi_write(24'h000110, 24'h84210F, 6'd4);
				state <= S_MAP_B_WR_WAIT;
			end
			S_MAP_B_WR_WAIT: if (bus_done) begin
				if (DDIO_TRACE_MODE) begin
					matrix_a <= bus_read_data[23:0];
					state <= S_MAP_ENTER_START;
				end
				else state <= S_MAP_B_GUARD_START;
			end
			S_MAP_B_GUARD_START: begin
				configure_spi_write(24'h000113, 24'hCDEF5A, 6'd4);
				state <= S_MAP_B_GUARD_WAIT;
			end
			S_MAP_B_GUARD_WAIT: if (bus_done) state <= S_MAP_C_WR_START;

			S_MAP_C_WR_START: begin
				configure_spi_write(24'h000120, 24'hFF00FF, 6'd4);
				state <= S_MAP_C_WR_WAIT;
			end
			S_MAP_C_WR_WAIT: if (bus_done) state <= S_MAP_C_GUARD_START;
			S_MAP_C_GUARD_START: begin
				configure_spi_write(24'h000123, 24'hCDEF5A, 6'd4);
				state <= S_MAP_C_GUARD_WAIT;
			end
			S_MAP_C_GUARD_WAIT: if (bus_done) state <= S_MAP_ENTER_START;

			S_MAP_ENTER_START: begin
				configure_command(1'b0, 8'h35);
				state <= S_MAP_ENTER_WAIT;
			end
			S_MAP_ENTER_WAIT: if (bus_done) state <= S_MAP_A_RD_START;

			S_MAP_A_RD_START: begin
				if (DDIO_TRACE_MODE)
					configure_extended_read(24'h000100, 6'd4);
				else
					// QPI EBh, six wait cycles, 8.47 MHz.
					configure_extended_read(24'h000120, 6'd4);
				state <= S_MAP_A_RD_WAIT;
			end
			S_MAP_A_RD_WAIT: if (bus_done) begin
				if (DDIO_TRACE_MODE)
					matrix_a <= bus_read_data[23:0];
				else
					matrix_a <= bus_read_data[23:0];
				state <= S_MAP_B_RD_START;
			end
			S_MAP_B_RD_START: begin
				if (DDIO_TRACE_MODE)
					configure_extended_read(24'h000100, 6'd2);
				else
					// QPI 0Bh, four wait cycles, 8.47 MHz.
					configure_qpi_0b_read(24'h000120, 6'd4);
				state <= S_MAP_B_RD_WAIT;
			end
			S_MAP_B_RD_WAIT: if (bus_done) begin
				if (DDIO_TRACE_MODE) begin
					matrix_b <= bus_read_data[23:0];
					state <= S_MAP_C_RD_START;
				end
				else begin
					matrix_b <= bus_read_data[23:0];
					state <= S_MAP_C_RD_START;
				end
			end
			S_MAP_C_RD_START: begin
				if (DDIO_TRACE_MODE)
					configure_extended_read(24'h000100, 6'd1);
				else
					// Repeat 0Bh at 2.82 MHz to expose frequency dependence.
					configure_qpi_0b_read(24'h000120, 6'd12);
				state <= S_MAP_C_RD_WAIT;
			end
			S_MAP_C_RD_WAIT: if (bus_done) begin
				matrix_c <= bus_read_data[23:0];
				result_code <= 2'd3;
				state <= S_MATRIX_HOLD;
			end
			S_MATRIX_HOLD: result_code <= 2'd3;

			// Write all addresses before reading any of them.  A board/device
			// that aliases A22 to A0 overwrites the sentinel at address zero
			// and is therefore identified explicitly.
			S_ADDR_WR_START: begin
				failure_address <= walking_address(test_index);
				expected_data <= walking_pattern(test_index);
				configure_write(walking_address(test_index),
				                walking_pattern(test_index), 6'd12);
				state <= S_ADDR_WR_WAIT;
			end
			S_ADDR_WR_WAIT: if (bus_done) begin
				if (test_index == 5'd22) begin
					test_index <= 5'd0;
					state <= S_ADDR_RD_START;
				end
				else begin
					test_index <= test_index + 1'b1;
					state <= S_ADDR_WR_START;
				end
			end

			S_ADDR_RD_START: begin
				failure_address <= walking_address(test_index);
				expected_data <= walking_pattern(test_index);
				configure_read(walking_address(test_index), 6'd12);
				state <= S_ADDR_RD_WAIT;
			end
			S_ADDR_RD_WAIT: if (bus_done) begin
				actual_data <= bus_read_data[15:0];
				if (bus_read_data[15:0] != walking_pattern(test_index))
					stop_with_failure(8'h05, walking_address(test_index),
					                  walking_pattern(test_index), bus_read_data[15:0]);
				else if (test_index == 5'd22) begin
					diagnostic_leds[4] <= 1'b1;
					speed_index <= 3'd0;
					stage_code <= 8'h06;
					state <= S_FREQ_WR_START;
				end
				else begin
					test_index <= test_index + 1'b1;
					state <= S_ADDR_RD_START;
				end
			end

			S_FREQ_WR_START: begin
				failure_address <= 24'h000700 + {20'd0, speed_index, 1'b0};
				expected_data <= 16'hC300 | {13'd0, speed_index};
				configure_write(24'h000700 + {20'd0, speed_index, 1'b0},
				                16'hC300 | {13'd0, speed_index},
				                divider_for_speed(speed_index));
				state <= S_FREQ_WR_WAIT;
			end
			S_FREQ_WR_WAIT: if (bus_done) state <= S_FREQ_RD_START;

			S_FREQ_RD_START: begin
				configure_read(24'h000700 + {20'd0, speed_index, 1'b0},
				               divider_for_speed(speed_index));
				state <= S_FREQ_RD_WAIT;
			end
			S_FREQ_RD_WAIT: if (bus_done) begin
				actual_data <= bus_read_data[15:0];
				if (bus_read_data[15:0] != (16'hC300 | {13'd0, speed_index}))
					stop_with_failure(8'h06 + {5'd0, speed_index},
					                  24'h000700 + {20'd0, speed_index, 1'b0},
					                  16'hC300 | {13'd0, speed_index},
					                  bus_read_data[15:0]);
				else if (speed_index >= selected_speed_limit(max_speed_select)) begin
					diagnostic_leds[5] <= 1'b1;
					state <= S_PASS;
				end
				else begin
					speed_index <= speed_index + 1'b1;
					stage_code <= 8'h07 + {5'd0, speed_index};
					state <= S_FREQ_WR_START;
				end
			end

			S_PASS: begin
				result_code <= 2'd1;
				diagnostic_leds[6] <= 1'b1;
			end

			S_FAIL: begin
				result_code <= 2'd2;
				diagnostic_leds[7] <= 1'b1;
			end

			default: state <= S_POWER;
		endcase
	end
end

endmodule
