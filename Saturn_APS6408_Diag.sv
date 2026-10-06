// Standalone MiSTer diagnostic for bringing up the Saturn project's
// APS6408L DDR OPI PSRAM adapter. This revision contains no Saturn core logic.
module emu
(
	input         CLK_50M,
	input         RESET,
	inout  [48:0] HPS_BUS,

	output        CLK_VIDEO,
	output        CE_PIXEL,
	output [12:0] VIDEO_ARX,
	output [12:0] VIDEO_ARY,
	output  [7:0] VGA_R,
	output  [7:0] VGA_G,
	output  [7:0] VGA_B,
	output        VGA_HS,
	output        VGA_VS,
	output        VGA_DE,
	output        VGA_F1,
	output  [1:0] VGA_SL,
	output        VGA_SCALER,
	output        VGA_DISABLE,

	input  [11:0] HDMI_WIDTH,
	input  [11:0] HDMI_HEIGHT,
	output        HDMI_FREEZE,
	output        HDMI_BLACKOUT,
	output        HDMI_BOB_DEINT,

	output        LED_USER,
	output  [1:0] LED_POWER,
	output  [1:0] LED_DISK,
	output  [1:0] BUTTONS,
`ifdef MISTER_PSRAM_DIAG
	output  [7:0] DIAG_LED,
`endif

	input         CLK_AUDIO,
	output [15:0] AUDIO_L,
	output [15:0] AUDIO_R,
	output        AUDIO_S,
	output  [1:0] AUDIO_MIX,
	inout   [3:0] ADC_BUS,

	output        SD_SCK,
	output        SD_MOSI,
	input         SD_MISO,
	output        SD_CS,
	input         SD_CD,

	output        DDRAM_CLK,
	input         DDRAM_BUSY,
	output  [7:0] DDRAM_BURSTCNT,
	output [28:0] DDRAM_ADDR,
	input  [63:0] DDRAM_DOUT,
	input         DDRAM_DOUT_READY,
	output        DDRAM_RD,
	output [63:0] DDRAM_DIN,
	output  [7:0] DDRAM_BE,
	output        DDRAM_WE,

	output        SDRAM_CLK,
	output        SDRAM_CKE,
	output [12:0] SDRAM_A,
	output  [1:0] SDRAM_BA,
	inout  [15:0] SDRAM_DQ,
	output        SDRAM_DQML,
	output        SDRAM_DQMH,
	output        SDRAM_nCS,
	output        SDRAM_nCAS,
	output        SDRAM_nRAS,
	output        SDRAM_nWE,

	output        PSRAM_CLK,
	output        PSRAM_CE_N,
	inout   [7:0] PSRAM_DQ,
	inout         PSRAM_DQS,

	input         UART_CTS,
	output        UART_RTS,
	input         UART_RXD,
	output        UART_TXD,
	output        UART_DTR,
	input         UART_DSR,

	input   [6:0] USER_IN,
	output  [6:0] USER_OUT,
	input         OSD_STATUS
);

`include "build_id.v"
parameter CONF_STR = {
    "APS6408L DDR DIAG;;",
    "O34,PSRAM clock,8.47 MHz,16.93 MHz,33.87 MHz;",
    "O78,Test mode,Same speed,8 MHz write,8 MHz read;",
    "T6,Restart test;",
    "R0,Reset;",
    "-;",
    "I,Tests octal DDR write/read and 8 MiB address reach;",
    "V,v",`BUILD_DATE
};

wire [127:0] status;
wire [1:0] buttons;

hps_io #(.CONF_STR(CONF_STR)) hps_io
(
	.clk_sys(CLK_50M),
	.HPS_BUS(HPS_BUS),
	.buttons(buttons),
	.status(status),
	.status_in(status),
	.status_set(1'b0),
	.status_menumask(16'd0),
	.video_rotated(1'b0),
	.new_vmode(1'b0),
	.info_req(1'b0),
	.info(8'd0),
	.ioctl_upload_req(1'b0),
	.ioctl_upload_index(8'd0),
	.ioctl_din(8'd0),
	.ioctl_wait(1'b0)
);

wire clk_33;
wire clk_67;
wire clk_phy;
wire pll_locked;

aps6408_diag_pll pll
(
	.refclk(CLK_50M),
	.rst(1'b0),
	.outclk_0(clk_33),
	.outclk_1(clk_67),
	.outclk_2(clk_phy),
	.locked(pll_locked)
);

(* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *)
reg [8:0] status_meta = 9'd0;
(* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *)
reg [8:0] status_sync = 9'd0;
reg [1:0] selected_speed = 2'd0;
reg [1:0] selected_test_mode = 2'd0;
reg       mode_restart = 1'b0;
always @(posedge clk_67) begin
	status_meta <= status[8:0];
	status_sync <= status_meta;
	mode_restart <= 1'b0;
	if (selected_speed != status_sync[4:3] || selected_test_mode != status_sync[8:7]) begin
		selected_speed <= status_sync[4:3];
		selected_test_mode <= status_sync[8:7];
		mode_restart <= 1'b1;
	end
end

wire diagnostic_reset_request = RESET | buttons[1] | status_sync[0] |
	                              status_sync[6] | mode_restart |
	                              (selected_speed != status_sync[4:3] || selected_test_mode != status_sync[8:7]) | !pll_locked;

// Synchronous assertion stretching and release keep the diagnostic free of
// the asynchronous recovery violation seen in Stage 53.
reg [2:0] diagnostic_reset_pipe = 3'b111;
always @(posedge clk_67) begin
	if (diagnostic_reset_request)
		diagnostic_reset_pipe <= 3'b111;
	else
		diagnostic_reset_pipe <= {diagnostic_reset_pipe[1:0], 1'b0};
end
wire diagnostic_reset = diagnostic_reset_pipe[2];
wire [1:0] result_code;
wire [7:0] stage_code;
wire [15:0] id_word;
wire [47:0] id_value = {32'd0,id_word};
wire id_kgd_ok = 1'b0;
wire [23:0] failure_address;
wire [15:0] expected_data;
wire [15:0] actual_data;
wire [15:0] sample_early;
wire [15:0] sample_mid;
wire [15:0] sample_center;
wire [15:0] sample_late;
wire [15:0] retry_read_data;
wire retry_read_valid;
wire [1:0] read_capture_tap;
wire [1:0] read_capture_tap_second;
wire [15:0] mr_pair0;
wire [15:0] mr_pair1;
wire [15:0] mr_pair2;
wire [15:0] dqs_edge_pair1;
wire [15:0] clk_pair1;
wire [2:0] speed_index = {1'b0, selected_speed};
wire [7:0] diagnostic_leds;
wire diagnostic_activity;
wire [23:0] matrix_a = {8'd0, (stage_code == 8'hE1 || stage_code == 8'hE6) ? dqs_edge_pair1 :
                              stage_code == 8'hE5 ? mr_pair0 : sample_early};
wire [23:0] matrix_b = {8'd0, (stage_code == 8'hE1 || stage_code == 8'hE5 || stage_code == 8'hE6) ?
                              mr_pair1 : sample_mid};
wire [23:0] matrix_c = {8'd0, (stage_code == 8'hE1 || stage_code == 8'hE6) ? clk_pair1 :
                              stage_code == 8'hE5 ? mr_pair2 : sample_late};

aps6408_diag_core diagnostic
(
    .clk(clk_67),
    .clk_phy(clk_phy),
    .reset(diagnostic_reset),
    .speed_select(selected_speed),
    .test_mode(selected_test_mode),
    .result_code(result_code),
    .stage_code(stage_code),
    .failure_address(failure_address),
    .id_word(id_word),
    .expected_data(expected_data),
    .actual_data(actual_data),
    .sample_early(sample_early),
    .sample_mid(sample_mid),
    .sample_center(sample_center),
    .sample_late(sample_late),
    .retry_read_data(retry_read_data),
    .retry_read_valid(retry_read_valid),
    .read_capture_tap(read_capture_tap),
    .read_capture_tap_second(read_capture_tap_second),
    .mr_pair0(mr_pair0),
    .mr_pair1(mr_pair1),
    .mr_pair2(mr_pair2),
    .dqs_edge_pair1(dqs_edge_pair1),
    .clk_pair1(clk_pair1),
    .diagnostic_leds(diagnostic_leds),
    .activity(diagnostic_activity),
    .PSRAM_CLK(PSRAM_CLK),
    .PSRAM_CE_N(PSRAM_CE_N),
    .PSRAM_DQ(PSRAM_DQ),
    .PSRAM_DQS(PSRAM_DQS)
);

aps6408_diag_video video
(
	.clk(clk_33),
	.result_code(result_code),
	.stage_code(stage_code),
	.id_value(id_value),
	.id_kgd_ok(id_kgd_ok),
	.failure_address(failure_address),
	.expected_data(expected_data),
	.actual_data(actual_data),
	.speed_index(speed_index),
	.mode(selected_test_mode),
	.matrix_a(matrix_a),
	.matrix_b(matrix_b),
	.matrix_c(matrix_c),
	.read_edge_pair(dqs_edge_pair1),
	.read_sample_early(sample_early),
	.read_sample_mid(sample_mid),
    .read_sample_center(sample_center),
	.read_sample_late(sample_late),
	.retry_read_data(retry_read_data),
	.retry_read_valid(retry_read_valid),
	.read_capture_tap(read_capture_tap),
    .read_capture_tap_second(read_capture_tap_second),
	.ce_pixel(CE_PIXEL),
	.red(VGA_R),
	.green(VGA_G),
	.blue(VGA_B),
	.hsync(VGA_HS),
	.vsync(VGA_VS),
	.de(VGA_DE)
);

assign CLK_VIDEO = clk_33;
assign VIDEO_ARX = 13'd4;
assign VIDEO_ARY = 13'd3;
assign VGA_F1 = 1'b0;
assign VGA_SL = 2'd0;
assign VGA_SCALER = 1'b0;
assign VGA_DISABLE = 1'b0;
assign HDMI_FREEZE = 1'b0;
assign HDMI_BLACKOUT = 1'b0;
assign HDMI_BOB_DEINT = 1'b0;

assign LED_USER = diagnostic_activity | (result_code == 2'd2);
assign LED_POWER = 2'd0;
assign LED_DISK = 2'd0;
assign BUTTONS = 2'd0;
`ifdef MISTER_PSRAM_DIAG
assign DIAG_LED = diagnostic_leds;
`endif

assign AUDIO_L = 16'd0;
assign AUDIO_R = 16'd0;
assign AUDIO_S = 1'b1;
assign AUDIO_MIX = 2'd0;
assign ADC_BUS = 4'bzzzz;

assign SD_SCK = 1'b0;
assign SD_MOSI = 1'b0;
assign SD_CS = 1'b1;

assign DDRAM_CLK = 1'b0;
assign DDRAM_BURSTCNT = 8'd0;
assign DDRAM_ADDR = 29'd0;
assign DDRAM_RD = 1'b0;
assign DDRAM_DIN = 64'd0;
assign DDRAM_BE = 8'd0;
assign DDRAM_WE = 1'b0;

assign SDRAM_CLK = 1'b0;
assign SDRAM_CKE = 1'b0;
assign SDRAM_A = 13'd0;
assign SDRAM_BA = 2'd0;
assign SDRAM_DQ = 16'hzzzz;
assign SDRAM_DQML = 1'b1;
assign SDRAM_DQMH = 1'b1;
assign SDRAM_nCS = 1'b1;
assign SDRAM_nCAS = 1'b1;
assign SDRAM_nRAS = 1'b1;
assign SDRAM_nWE = 1'b1;

assign UART_RTS = 1'b0;
assign UART_TXD = 1'b0;
assign UART_DTR = 1'b0;
assign USER_OUT = 7'h7F;

endmodule
