// 320x240 status display for the standalone Saturn RAMH/PSRAM stress core.
module psram_stress_video
#(
	parameter [1:0] MODE_CODE = 2'd0
)
(
	input             clk,
	input       [1:0] result_code,
	input       [7:0] phase_code,
	input       [3:0] pattern_id,
	input      [31:0] loop_count,
	input      [31:0] operation_count,
	input      [15:0] device_id,
	input      [23:0] current_address,
	input      [31:0] expected_data,
	input      [31:0] actual_data,
	input      [31:0] xor_data,
	input       [3:0] byte_mask,

	output            ce_pixel,
	output reg  [7:0] red,
	output reg  [7:0] green,
	output reg  [7:0] blue,
	output            hsync,
	output            vsync,
	output            de
);

reg [9:0] h_count = 10'd0;
reg [9:0] v_count = 10'd0;
reg [2:0] pixel_divider = 3'd0;

wire pixel_tick = (pixel_divider == 3'd4);
assign ce_pixel = pixel_tick;
assign hsync = ~((h_count >= 10'd336) && (h_count < 10'd368));
assign vsync = ~((v_count >= 10'd243) && (v_count < 10'd246));
assign de = (h_count < 10'd320) && (v_count < 10'd240);

always @(posedge clk) begin
	if (pixel_tick) begin
		pixel_divider <= 3'd0;
		if (h_count == 10'd431) begin
			h_count <= 10'd0;
			if (v_count == 10'd261) v_count <= 10'd0;
			else v_count <= v_count + 1'b1;
		end
		else h_count <= h_count + 1'b1;
	end
	else pixel_divider <= pixel_divider + 1'b1;
end

localparam [383:0] TXT_TITLE = {"SATURN PSRAM STRESS TEST", {24{8'h20}}};
localparam [383:0] TXT_RESULT = {"RESULT:", {41{8'h20}}};
localparam [383:0] TXT_PHASE = {"PHASE:", {42{8'h20}}};
localparam [383:0] TXT_PATTERN = {"PATTERN:", {40{8'h20}}};
localparam [383:0] TXT_LOOPS = {"LOOPS:", {42{8'h20}}};
localparam [383:0] TXT_ID = {"SPI ID:", {41{8'h20}}};
localparam [383:0] TXT_ADDRESS = {"ADDRESS:", {40{8'h20}}};
localparam [383:0] TXT_OPERATIONS = {"OPERATIONS:", {37{8'h20}}};
localparam [383:0] TXT_EXPECTED = {"EXPECTED:", {39{8'h20}}};
localparam [383:0] TXT_ACTUAL = {"ACTUAL:", {41{8'h20}}};
localparam [383:0] TXT_XOR = {"XOR:", {44{8'h20}}};
localparam [383:0] TXT_MASK = {"BYTE MASK:", {38{8'h20}}};
localparam [383:0] TXT_HELP1 = {"QPI 16.93 MHZ 16B LINE", {26{8'h20}}};
localparam [383:0] TXT_HELP1_4B = {"QPI 16.93 MHZ 4B READ", {27{8'h20}}};
localparam [383:0] TXT_HELP1_SLOW = {"QPI 8.47 MHZ 16B LINE", {27{8'h20}}};
localparam [383:0] TXT_HELP2 = {"CONTINUOUS TEST; FIRST ERROR FREEZES", {12{8'h20}}};
localparam [383:0] TXT_HELP3 = {"LED7 FAIL LED6 LOOP PASS", {24{8'h20}}};

function [7:0] fixed_char;
	input [383:0] text;
	input [5:0] column;
	begin
		if (column < 48) fixed_char = text[383-(column*8) -: 8];
		else fixed_char = 8'h20;
	end
endfunction

function [7:0] hex_char;
	input [3:0] value;
	begin
		case (value)
			4'h0: hex_char = "0"; 4'h1: hex_char = "1";
			4'h2: hex_char = "2"; 4'h3: hex_char = "3";
			4'h4: hex_char = "4"; 4'h5: hex_char = "5";
			4'h6: hex_char = "6"; 4'h7: hex_char = "7";
			4'h8: hex_char = "8"; 4'h9: hex_char = "9";
			4'hA: hex_char = "A"; 4'hB: hex_char = "B";
			4'hC: hex_char = "C"; 4'hD: hex_char = "D";
			4'hE: hex_char = "E"; default: hex_char = "F";
		endcase
	end
endfunction

function [7:0] result_char;
	input [3:0] offset;
	begin
		result_char = 8'h20;
		if (result_code == 2'd2) begin
			case (offset)
				0: result_char = "F"; 1: result_char = "A";
				2: result_char = "I"; 3: result_char = "L";
				default: result_char = 8'h20;
			endcase
		end
		else if (result_code == 2'd1) begin
			case (offset)
				0: result_char = "P"; 1: result_char = "A";
				2: result_char = "S"; 3: result_char = "S";
				default: result_char = 8'h20;
			endcase
		end
		else if (phase_code == 0) begin
			case (offset)
				0: result_char = "I"; 1: result_char = "N";
				2: result_char = "I"; 3: result_char = "T";
				default: result_char = 8'h20;
			endcase
		end
		else begin
			case (offset)
				0: result_char = "R"; 1: result_char = "U";
				2: result_char = "N"; 3: result_char = "N";
				4: result_char = "I"; 5: result_char = "N";
				default: result_char = "G";
			endcase
		end
	end
endfunction

function [7:0] screen_char;
	input [5:0] column;
	input [4:0] row;
	reg [7:0] value;
	begin
		value = 8'h20;
		case (row)
			1: value = fixed_char(TXT_TITLE, column);
			4: begin
				value = fixed_char(TXT_RESULT, column);
				if ((column >= 8) && (column < 15))
					value = result_char(column - 8);
			end
			6: begin
				value = fixed_char(TXT_PHASE, column);
				if ((column >= 8) && (column < 10))
					value = hex_char(phase_code[7-((column-8)*4) -: 4]);
			end
			8: begin
				value = fixed_char(TXT_PATTERN, column);
				if (column == 10) value = hex_char(pattern_id);
			end
			10: begin
				value = fixed_char(TXT_LOOPS, column);
				if ((column >= 8) && (column < 16))
					value = hex_char(loop_count[31-((column-8)*4) -: 4]);
			end
			12: begin
				value = fixed_char(TXT_ID, column);
				if ((column >= 8) && (column < 12))
					value = hex_char(device_id[15-((column-8)*4) -: 4]);
			end
			14: begin
				value = fixed_char(TXT_ADDRESS, column);
				if ((column >= 10) && (column < 16))
					value = hex_char(current_address[23-((column-10)*4) -: 4]);
			end
			16: begin
				value = fixed_char(TXT_OPERATIONS, column);
				if ((column >= 13) && (column < 21))
					value = hex_char(operation_count[31-((column-13)*4) -: 4]);
			end
			18: begin
				value = fixed_char(TXT_EXPECTED, column);
				if ((column >= 11) && (column < 19))
					value = hex_char(expected_data[31-((column-11)*4) -: 4]);
			end
			20: begin
				value = fixed_char(TXT_ACTUAL, column);
				if ((column >= 9) && (column < 17))
					value = hex_char(actual_data[31-((column-9)*4) -: 4]);
			end
			22: begin
				value = fixed_char(TXT_XOR, column);
				if ((column >= 6) && (column < 14))
					value = hex_char(xor_data[31-((column-6)*4) -: 4]);
			end
			24: begin
				value = fixed_char(TXT_MASK, column);
				if (column == 12) value = hex_char(byte_mask);
			end
			26: begin
				case (MODE_CODE)
					2'd1: value = fixed_char(TXT_HELP1_4B, column);
					2'd2: value = fixed_char(TXT_HELP1_SLOW, column);
					default: value = fixed_char(TXT_HELP1, column);
				endcase
			end
			27: value = fixed_char(TXT_HELP2, column);
			28: value = fixed_char(TXT_HELP3, column);
			default: begin end
		endcase
		screen_char = value;
	end
endfunction

function [34:0] glyph;
	input [7:0] character;
	begin
		case (character)
			"0": glyph = {5'b01110,5'b10001,5'b10011,5'b10101,5'b11001,5'b10001,5'b01110};
			"1": glyph = {5'b00100,5'b01100,5'b00100,5'b00100,5'b00100,5'b00100,5'b01110};
			"2": glyph = {5'b01110,5'b10001,5'b00001,5'b00010,5'b00100,5'b01000,5'b11111};
			"3": glyph = {5'b11110,5'b00001,5'b00001,5'b01110,5'b00001,5'b00001,5'b11110};
			"4": glyph = {5'b00010,5'b00110,5'b01010,5'b10010,5'b11111,5'b00010,5'b00010};
			"5": glyph = {5'b11111,5'b10000,5'b10000,5'b11110,5'b00001,5'b00001,5'b11110};
			"6": glyph = {5'b01110,5'b10000,5'b10000,5'b11110,5'b10001,5'b10001,5'b01110};
			"7": glyph = {5'b11111,5'b00001,5'b00010,5'b00100,5'b01000,5'b01000,5'b01000};
			"8": glyph = {5'b01110,5'b10001,5'b10001,5'b01110,5'b10001,5'b10001,5'b01110};
			"9": glyph = {5'b01110,5'b10001,5'b10001,5'b01111,5'b00001,5'b00001,5'b01110};
			"A": glyph = {5'b01110,5'b10001,5'b10001,5'b11111,5'b10001,5'b10001,5'b10001};
			"B": glyph = {5'b11110,5'b10001,5'b10001,5'b11110,5'b10001,5'b10001,5'b11110};
			"C": glyph = {5'b01111,5'b10000,5'b10000,5'b10000,5'b10000,5'b10000,5'b01111};
			"D": glyph = {5'b11110,5'b10001,5'b10001,5'b10001,5'b10001,5'b10001,5'b11110};
			"E": glyph = {5'b11111,5'b10000,5'b10000,5'b11110,5'b10000,5'b10000,5'b11111};
			"F": glyph = {5'b11111,5'b10000,5'b10000,5'b11110,5'b10000,5'b10000,5'b10000};
			"G": glyph = {5'b01111,5'b10000,5'b10000,5'b10111,5'b10001,5'b10001,5'b01110};
			"H": glyph = {5'b10001,5'b10001,5'b10001,5'b11111,5'b10001,5'b10001,5'b10001};
			"I": glyph = {5'b01110,5'b00100,5'b00100,5'b00100,5'b00100,5'b00100,5'b01110};
			"J": glyph = {5'b00111,5'b00010,5'b00010,5'b00010,5'b10010,5'b10010,5'b01100};
			"K": glyph = {5'b10001,5'b10010,5'b10100,5'b11000,5'b10100,5'b10010,5'b10001};
			"L": glyph = {5'b10000,5'b10000,5'b10000,5'b10000,5'b10000,5'b10000,5'b11111};
			"M": glyph = {5'b10001,5'b11011,5'b10101,5'b10101,5'b10001,5'b10001,5'b10001};
			"N": glyph = {5'b10001,5'b11001,5'b10101,5'b10011,5'b10001,5'b10001,5'b10001};
			"O": glyph = {5'b01110,5'b10001,5'b10001,5'b10001,5'b10001,5'b10001,5'b01110};
			"P": glyph = {5'b11110,5'b10001,5'b10001,5'b11110,5'b10000,5'b10000,5'b10000};
			"Q": glyph = {5'b01110,5'b10001,5'b10001,5'b10001,5'b10101,5'b10010,5'b01101};
			"R": glyph = {5'b11110,5'b10001,5'b10001,5'b11110,5'b10100,5'b10010,5'b10001};
			"S": glyph = {5'b01111,5'b10000,5'b10000,5'b01110,5'b00001,5'b00001,5'b11110};
			"T": glyph = {5'b11111,5'b00100,5'b00100,5'b00100,5'b00100,5'b00100,5'b00100};
			"U": glyph = {5'b10001,5'b10001,5'b10001,5'b10001,5'b10001,5'b10001,5'b01110};
			"V": glyph = {5'b10001,5'b10001,5'b10001,5'b10001,5'b10001,5'b01010,5'b00100};
			"W": glyph = {5'b10001,5'b10001,5'b10001,5'b10101,5'b10101,5'b10101,5'b01010};
			"X": glyph = {5'b10001,5'b10001,5'b01010,5'b00100,5'b01010,5'b10001,5'b10001};
			"Y": glyph = {5'b10001,5'b10001,5'b01010,5'b00100,5'b00100,5'b00100,5'b00100};
			"Z": glyph = {5'b11111,5'b00001,5'b00010,5'b00100,5'b01000,5'b10000,5'b11111};
			":": glyph = {5'b00000,5'b00100,5'b00100,5'b00000,5'b00100,5'b00100,5'b00000};
			"=": glyph = {5'b00000,5'b11111,5'b00000,5'b11111,5'b00000,5'b00000,5'b00000};
			".": glyph = {5'b00000,5'b00000,5'b00000,5'b00000,5'b00000,5'b00110,5'b00110};
			";": glyph = {5'b00000,5'b00100,5'b00100,5'b00000,5'b00100,5'b00100,5'b01000};
			"-": glyph = {5'b00000,5'b00000,5'b00000,5'b11111,5'b00000,5'b00000,5'b00000};
			default: glyph = 35'd0;
		endcase
	end
endfunction

integer x_relative;
integer y_relative;
integer character_column;
integer character_row;
integer glyph_x;
integer glyph_y;
reg [7:0] current_character;
reg [34:0] current_glyph;
reg text_pixel;

always @* begin
	x_relative = h_count - 16;
	y_relative = v_count - 8;
	character_column = x_relative / 6;
	character_row = y_relative / 8;
	glyph_x = x_relative - (character_column * 6);
	glyph_y = y_relative[2:0];
	current_character = screen_char(character_column[5:0], character_row[4:0]);
	current_glyph = glyph(current_character);
	text_pixel = 1'b0;

	if ((h_count >= 16) && (h_count < 304) &&
	    (v_count >= 8) && (v_count < 240) &&
	    (glyph_x >= 0) && (glyph_x < 5) && (glyph_y >= 0) && (glyph_y < 7))
		text_pixel = current_glyph[34-(glyph_y*5+glyph_x)];

	if (!de) begin
		red = 8'd0;
		green = 8'd0;
		blue = 8'd0;
	end
	else if (text_pixel) begin
		red = 8'hFF;
		green = 8'hFF;
		blue = 8'hFF;
	end
	else if (result_code == 2'd2) begin
		red = 8'h38;
		green = 8'h04;
		blue = 8'h04;
	end
	else if (result_code == 2'd1) begin
		red = 8'h02;
		green = 8'h30;
		blue = 8'h0C;
	end
	else begin
		red = 8'h02;
		green = 8'h12;
		blue = 8'h30;
	end
end

endmodule
