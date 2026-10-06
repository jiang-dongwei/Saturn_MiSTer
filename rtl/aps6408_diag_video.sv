// 320x240p status display for the standalone PSRAM diagnostic.
// A 6.77376 MHz pixel enable gives approximately 15.68 kHz horizontal and
// 59.84 Hz vertical timing, suitable for the SuperDock analog video path.
module aps6408_diag_video
(
	input             clk,
	input       [1:0] result_code,
	input       [7:0] stage_code,
	input      [47:0] id_value,
	input             id_kgd_ok,
	input      [23:0] failure_address,
	input      [15:0] expected_data,
	input      [15:0] actual_data,
	input       [2:0] speed_index,
	input       [1:0] mode,
	input      [23:0] matrix_a,
	input      [23:0] matrix_b,
	input      [23:0] matrix_c,
	input      [15:0] read_edge_pair,
	input      [15:0] read_sample_early,
	input      [15:0] read_sample_mid,
    input      [15:0] read_sample_center,
	input      [15:0] read_sample_late,
	input      [15:0] retry_read_data,
	input             retry_read_valid,
	input      [1:0]  read_capture_tap,
    input      [1:0] read_capture_tap_second,

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

localparam [383:0] TXT_TITLE = {"APS6408L DDR OPI DIAGNOSTIC", {21{8'h20}}};
localparam [383:0] TXT_RESULT = {"RESULT:", {41{8'h20}}};
localparam [383:0] TXT_STAGE = {"STAGE:", {42{8'h20}}};
localparam [383:0] TXT_ID = {"MR1/MR2:", {40{8'h20}}};
localparam [383:0] TXT_KGD = {"INTERFACE: X8 DDR", {31{8'h20}}};
localparam [383:0] TXT_SPEED8 = {"TARGET: 8.47 MHZ", {32{8'h20}}};
localparam [383:0] TXT_SPEED16 = {"TARGET: 16.93 MHZ", {31{8'h20}}};
localparam [383:0] TXT_SPEED33 = {"TARGET: 33.87 MHZ", {31{8'h20}}};
localparam [383:0] TXT_ADDRESS = {"ADDRESS:", {40{8'h20}}};
localparam [383:0] TXT_EXPECTED = {"EXPECTED:", {39{8'h20}}};
localparam [383:0] TXT_ACTUAL = {"ACTUAL:", {41{8'h20}}};
localparam [383:0] TXT_MODE = {"MODE:", {43{8'h20}}};
localparam [383:0] TXT_HELP1 = {"4 PASSES X 256 LOCATIONS", {24{8'h20}}};
localparam [383:0] TXT_HELP_DDIO = {"DQS CAPTURE AT LOW SPEED", {24{8'h20}}};
localparam [383:0] TXT_HELP2 = {"ADDRESS RANGE 000000 TO 7FFFFE", {18{8'h20}}};
localparam [383:0] TXT_HELP3 = {"E1 DQS E2 DATA E4 SAMPLE E5 MR MAP E6 EDGE", {6{8'h20}}};
localparam [383:0] TXT_HELP4 = {"OSD SELECT CLOCK  LED7 FAIL LED6 PASS", {11{8'h20}}};
localparam [383:0] TXT_E2_SAMPLES = {"EARLY:      MID:      LATE:    ", {17{8'h20}}};
localparam [383:0] TXT_E2_EDGES = {"DQS EDGES:", {38{8'h20}}};
localparam [383:0] TXT_RX_EARLY = {"RX TAP: EARLY", {35{8'h20}}};
localparam [383:0] TXT_RX_MID = {"RX TAP: MID", {37{8'h20}}};
localparam [383:0] TXT_RX_LATE = {"RX TAP: LATE", {36{8'h20}}};
localparam [383:0] TXT_RX_CENTER = {"RX TAP: CENTER", {34{8'h20}}};

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

function [7:0] id_char;
	input [4:0] offset;
	begin
		case (offset)
			0:  id_char = hex_char(id_value[47:44]);
			1:  id_char = hex_char(id_value[43:40]);
			2:  id_char = 8'h20;
			3:  id_char = hex_char(id_value[39:36]);
			4:  id_char = hex_char(id_value[35:32]);
			default: id_char = 8'h20;
		endcase
	end
endfunction

function [7:0] result_char;
	input [2:0] offset;
	begin
		case (result_code)
			2'd3: begin
				case (offset)
					0: result_char = "T";
					1: result_char = "R";
					2: result_char = "A";
					3: result_char = "C";
					4: result_char = "E";
					default: result_char = 8'h20;
				endcase
			end
			2'd1: begin
				case (offset)
					0: result_char = "P";
					1: result_char = "A";
					2: result_char = "S";
					3: result_char = "S";
					default: result_char = 8'h20;
				endcase
			end
			2'd2: begin
				case (offset)
					0: result_char = "F";
					1: result_char = "A";
					2: result_char = "I";
					3: result_char = "L";
					default: result_char = 8'h20;
				endcase
			end
			default: begin
				case (offset)
					0: result_char = "R";
					1: result_char = "U";
					2: result_char = "N";
					3: result_char = "N";
					4: result_char = "I";
					5: result_char = "N";
					default: result_char = "G";
				endcase
			end
		endcase
	end
endfunction

function [7:0] mode_char;
	input [4:0] offset;
	begin
		case (mode)
			2'd1: begin
				case (offset)
					0: mode_char = "L"; 1: mode_char = "O";
					2: mode_char = "O"; 3: mode_char = "P";
					4: mode_char = " "; 5: mode_char = "S";
					6: mode_char = "P"; 7: mode_char = "I";
					8: mode_char = " "; 9: mode_char = "I";
					default: mode_char = "D";
				endcase
			end
			2'd2: begin
				case (offset)
					0: mode_char = "L"; 1: mode_char = "O";
					2: mode_char = "O"; 3: mode_char = "P";
					4: mode_char = " "; 5: mode_char = "W";
					6: mode_char = "R"; 7: mode_char = "I";
					8: mode_char = "T"; 9: mode_char = "E";
					default: mode_char = 8'h20;
				endcase
			end
			2'd3: begin
				case (offset)
					0: mode_char = "L"; 1: mode_char = "O";
					2: mode_char = "O"; 3: mode_char = "P";
					4: mode_char = " "; 5: mode_char = "R";
					6: mode_char = "E"; 7: mode_char = "A";
					8: mode_char = "D";
					default: mode_char = 8'h20;
				endcase
			end
			default: begin
				case (offset)
					0: mode_char = "A"; 1: mode_char = "U";
					2: mode_char = "T"; 3: mode_char = "O";
					default: mode_char = 8'h20;
				endcase
			end
		endcase
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
            2: begin
                value = fixed_char({"WRITE:            READ: ", {24{8'h20}}}, column);
                if (column >= 7 && column < 16)
                    value = fixed_char((mode == 1 || speed_index == 0) ? {"8.47 MHZ", {40{8'h20}}} :
                        speed_index == 1 ? {"16.93 MHZ", {39{8'h20}}} : {"33.87 MHZ", {39{8'h20}}}, column-7);
                if (column >= 24 && column < 33)
                    value = fixed_char((mode == 2 || speed_index == 0) ? {"8.47 MHZ", {40{8'h20}}} :
                        speed_index == 1 ? {"16.93 MHZ", {39{8'h20}}} : {"33.87 MHZ", {39{8'h20}}}, column-24);
            end
            3: value = fixed_char(mode == 1 ? {"MODE: LOW WRITE", {33{8'h20}}} :
                                  mode == 2 ? {"MODE: LOW READ", {34{8'h20}}} :
                                  {"MODE: SAME SPEED", {32{8'h20}}}, column);
			4: begin
				value = fixed_char(TXT_RESULT, column);
				if ((column >= 8) && (column < 15))
					value = result_char(column - 8);
			end
			6: begin
				value = fixed_char(TXT_STAGE, column);
				if (column == 8) value = hex_char(stage_code[7:4]);
				if (column == 9) value = hex_char(stage_code[3:0]);
			end
			8: begin
				if (stage_code == 8'hE1) begin
					value = fixed_char(TXT_ADDRESS, column);
					if ((column >= 10) && (column < 16))
						value = hex_char(failure_address[23-((column-10)*4) -: 4]);
				end
				else begin
					value = fixed_char(TXT_ID, column);
					if ((column >= 10) && (column < 14))
						value = hex_char(id_value[15-((column-10)*4) -: 4]);
				end
			end
			10: value = fixed_char(TXT_KGD, column);
			12: value = fixed_char(speed_index == 3'd0 ? TXT_SPEED8 :
			                       speed_index == 3'd1 ? TXT_SPEED16 : TXT_SPEED33, column);
			14: begin
				if (stage_code == 8'h58) begin
					value = fixed_char({"A QPI8   :", {38{8'h20}}}, column);
					if ((column >= 10) && (column < 16))
						value = hex_char(matrix_a[23-((column-10)*4) -: 4]);
				end
				else if (stage_code == 8'h52) begin
					value = fixed_char({"A EB6  :", {40{8'h20}}}, column);
					if ((column >= 10) && (column < 16))
						value = hex_char(matrix_a[23-((column-10)*4) -: 4]);
				end
				else if (stage_code == 8'hE4) begin
					value = fixed_char({"EARLY MR:", {39{8'h20}}}, column);
					if ((column >= 10) && (column < 14))
						value = hex_char(matrix_a[15-((column-10)*4) -: 4]);
				end
				else if (stage_code == 8'hE5) begin
					value = fixed_char({"MR0/1:", {42{8'h20}}}, column);
					if ((column >= 10) && (column < 14))
						value = hex_char(matrix_a[15-((column-10)*4) -: 4]);
				end
				else if (stage_code == 8'hE1 || stage_code == 8'hE6) begin
					value = fixed_char({"DQS EDGE:", {39{8'h20}}}, column);
					if ((column >= 10) && (column < 14))
						value = hex_char(matrix_a[15-((column-10)*4) -: 4]);
				end
				else begin
					value = fixed_char(TXT_ADDRESS, column);
					if ((column >= 10) && (column < 16))
						value = hex_char(failure_address[23-((column-10)*4) -: 4]);
				end
			end
			16: begin
				if (stage_code == 8'h58) begin
					value = fixed_char({"B QPI16  :", {38{8'h20}}}, column);
					if ((column >= 10) && (column < 16))
						value = hex_char(matrix_b[23-((column-10)*4) -: 4]);
				end
				else if (stage_code == 8'h52) begin
					value = fixed_char({"B 0B4  :", {40{8'h20}}}, column);
					if ((column >= 10) && (column < 16))
						value = hex_char(matrix_b[23-((column-10)*4) -: 4]);
				end
				else if (stage_code == 8'hE4) begin
					value = fixed_char({"MID MR:", {41{8'h20}}}, column);
					if ((column >= 10) && (column < 14))
						value = hex_char(matrix_b[15-((column-10)*4) -: 4]);
				end
				else if (stage_code == 8'hE5) begin
					value = fixed_char({"MR1/2:", {42{8'h20}}}, column);
					if ((column >= 10) && (column < 14))
						value = hex_char(matrix_b[15-((column-10)*4) -: 4]);
				end
				else if (stage_code == 8'hE1 || stage_code == 8'hE6) begin
					value = fixed_char({"DQS DATA:", {39{8'h20}}}, column);
					if ((column >= 10) && (column < 14))
						value = hex_char(matrix_b[15-((column-10)*4) -: 4]);
				end
				else begin
					value = fixed_char(TXT_EXPECTED, column);
					if ((column >= 11) && (column < 15))
						value = hex_char(expected_data[15-((column-11)*4) -: 4]);
				end
			end
			18: begin
				if (stage_code == 8'h58) begin
					value = fixed_char({"C QPI33  :", {38{8'h20}}}, column);
					if ((column >= 10) && (column < 16))
						value = hex_char(matrix_c[23-((column-10)*4) -: 4]);
				end
				else if (stage_code == 8'h52) begin
					value = fixed_char({"C 0B4S :", {40{8'h20}}}, column);
					if ((column >= 10) && (column < 16))
						value = hex_char(matrix_c[23-((column-10)*4) -: 4]);
				end
				else if (stage_code == 8'hE4) begin
					value = fixed_char({"LATE MR:", {40{8'h20}}}, column);
					if ((column >= 10) && (column < 14))
						value = hex_char(matrix_c[15-((column-10)*4) -: 4]);
				end
				else if (stage_code == 8'hE5) begin
					value = fixed_char({"MR2/3:", {42{8'h20}}}, column);
					if ((column >= 10) && (column < 14))
						value = hex_char(matrix_c[15-((column-10)*4) -: 4]);
				end
				else if (stage_code == 8'hE1 || stage_code == 8'hE6) begin
					value = fixed_char({"CLK DATA:", {39{8'h20}}}, column);
					if ((column >= 10) && (column < 14))
						value = hex_char(matrix_c[15-((column-10)*4) -: 4]);
				end
				else begin
					value = fixed_char(TXT_ACTUAL, column);
					if ((column >= 9) && (column < 13))
						value = hex_char(actual_data[15-((column-9)*4) -: 4]);
				end
			end
			20: begin
                value = fixed_char({"CENTER:", {41{8'h20}}}, column);
                if (column >= 10 && column < 14)
                    value = hex_char(read_sample_center[15-((column-10)*4) -: 4]);
			end
            21: begin
                value = fixed_char(read_capture_tap == 2 ? TXT_RX_LATE : read_capture_tap == 1 ? TXT_RX_MID :
                                   read_capture_tap == 3 ? TXT_RX_CENTER : TXT_RX_EARLY, column);
                if (column >= 20 && column < 24) value = fixed_char({"D1: ", {44{8'h20}}}, column-20);
                if (column >= 24) value = fixed_char(read_capture_tap_second == 2 ? TXT_RX_LATE :
                    read_capture_tap_second == 1 ? TXT_RX_MID : read_capture_tap_second == 3 ? TXT_RX_CENTER : TXT_RX_EARLY, column-16);
            end
			23: begin
				value = fixed_char((stage_code == 8'hE2 || stage_code == 8'hE6) ? TXT_E2_SAMPLES :
				                   stage_code == 8'h58 ? TXT_HELP_DDIO : TXT_HELP1, column);
				if (stage_code == 8'hE2 || stage_code == 8'hE6) begin
					if (column >= 7 && column < 11)
						value = hex_char(read_sample_early[15-((column-7)*4) -: 4]);
					if (column >= 17 && column < 21)
						value = hex_char(read_sample_mid[15-((column-17)*4) -: 4]);
					if (column >= 28 && column < 32)
						value = hex_char(read_sample_late[15-((column-28)*4) -: 4]);
				end
			end
			25: begin
				value = fixed_char(stage_code == 8'hE2 ? TXT_E2_EDGES : TXT_HELP2, column);
				if (stage_code == 8'hE2 && column >= 11 && column < 15)
					value = hex_char(read_edge_pair[15-((column-11)*4) -: 4]);
				if (stage_code == 8'hE2 && retry_read_valid) begin
					if (column >= 18 && column < 23)
						value = fixed_char({"R8:  ", {43{8'h20}}}, column-18);
					if (column >= 24 && column < 28)
						value = hex_char(retry_read_data[15-((column-24)*4) -: 4]);
				end
			end
			26: value = fixed_char(TXT_HELP3, column);
			27: value = fixed_char(TXT_HELP4, column);
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
