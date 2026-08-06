// Standalone MiSTer stress core for the Saturn RAMH QPI PSRAM backend.
// This revision contains no Saturn console logic and requires no BIOS or ROM.
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
	inout   [3:0] PSRAM_DQ,

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
	"SATURNPSRAMSTRESS;;",
	"T6,Restart stress test;",
	"R0,Reset;",
	"-;",
	"I,Tests the full 1 MiB Saturn RAMH through QPI PSRAM;",
	"I,First error freezes phase address expected actual and XOR;",
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
wire clk_101;
wire pll_locked;

psram_diag_pll pll
(
	.refclk(CLK_50M),
	.rst(1'b0),
	.outclk_0(clk_33),
	.outclk_1(clk_67),
	.outclk_2(clk_101),
	.locked(pll_locked)
);

(* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *)
reg [6:0] status_meta = 7'd0;
(* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *)
reg [6:0] status_sync = 7'd0;
always @(posedge clk_67) begin
	status_meta <= status[6:0];
	status_sync <= status_meta;
end

wire stress_reset_request = RESET | buttons[1] | status_sync[0] |
	                          status_sync[6] | !pll_locked;
reg [2:0] stress_reset_pipe = 3'b111;
always @(posedge clk_67) begin
	if (stress_reset_request) stress_reset_pipe <= 3'b111;
	else stress_reset_pipe <= {stress_reset_pipe[1:0], 1'b0};
end
wire stress_reset = stress_reset_pipe[2];

wire [1:0] result_code;
wire [7:0] phase_code;
wire [3:0] pattern_id;
wire [31:0] loop_count;
wire [31:0] operation_count;
wire [23:0] current_address;
wire [31:0] expected_data;
wire [31:0] actual_data;
wire [31:0] xor_data;
wire [31:0] confirm_data1;
wire [31:0] confirm_data2;
wire [3:0] byte_mask;
wire [15:0] device_id;
wire init_done;
wire init_error;
wire stress_failed;
wire stress_activity;

`ifdef PSRAM_STRESS_CONFIRM
localparam [5:0] STRESS_HALF_DIVIDER = 6'd4;
localparam integer STRESS_READ_LINE_BYTES = 4;
localparam [1:0] STRESS_MODE_CODE = 2'd3;
localparam integer STRESS_CONFIRM_ON_MISMATCH = 1;
`elsif PSRAM_STRESS_SAFE
localparam [5:0] STRESS_HALF_DIVIDER = 6'd4;
localparam integer STRESS_READ_LINE_BYTES = 4;
localparam [1:0] STRESS_MODE_CODE = 2'd3;
localparam integer STRESS_CONFIRM_ON_MISMATCH = 0;
`elsif PSRAM_STRESS_4B
localparam [5:0] STRESS_HALF_DIVIDER = 6'd2;
localparam integer STRESS_READ_LINE_BYTES = 4;
localparam [1:0] STRESS_MODE_CODE = 2'd1;
localparam integer STRESS_CONFIRM_ON_MISMATCH = 0;
`elsif PSRAM_STRESS_SLOW
localparam [5:0] STRESS_HALF_DIVIDER = 6'd4;
localparam integer STRESS_READ_LINE_BYTES = 16;
localparam [1:0] STRESS_MODE_CODE = 2'd2;
localparam integer STRESS_CONFIRM_ON_MISMATCH = 0;
`else
localparam [5:0] STRESS_HALF_DIVIDER = 6'd2;
localparam integer STRESS_READ_LINE_BYTES = 16;
localparam [1:0] STRESS_MODE_CODE = 2'd0;
localparam integer STRESS_CONFIRM_ON_MISMATCH = 0;
`endif

psram_stress_core
#(
	.HALF_DIVIDER(STRESS_HALF_DIVIDER),
	.READ_LINE_BYTES(STRESS_READ_LINE_BYTES),
	.CONFIRM_ON_MISMATCH(STRESS_CONFIRM_ON_MISMATCH)
)
stress
(
	.clk(clk_67),
	.reset(stress_reset),
	.result_code(result_code),
	.phase_code(phase_code),
	.pattern_id(pattern_id),
	.loop_count(loop_count),
	.operation_count(operation_count),
	.current_address(current_address),
	.expected_data(expected_data),
	.actual_data(actual_data),
	.xor_data(xor_data),
	.confirm_data1(confirm_data1),
	.confirm_data2(confirm_data2),
	.byte_mask(byte_mask),
	.device_id(device_id),
	.init_done(init_done),
	.init_error(init_error),
	.failed(stress_failed),
	.activity(stress_activity),
	.PSRAM_CLK(PSRAM_CLK),
	.PSRAM_CE_N(PSRAM_CE_N),
	.PSRAM_DQ(PSRAM_DQ)
);

psram_stress_video
#(
	.MODE_CODE(STRESS_MODE_CODE),
	.CONFIRM_VIEW(STRESS_CONFIRM_ON_MISMATCH)
)
video
(
	.clk(clk_33),
	.result_code(result_code),
	.phase_code(phase_code),
	.pattern_id(pattern_id),
	.loop_count(loop_count),
	.operation_count(operation_count),
	.device_id(device_id),
	.current_address(current_address),
	.expected_data(expected_data),
	.actual_data(actual_data),
	.xor_data(xor_data),
	.confirm_data1(confirm_data1),
	.confirm_data2(confirm_data2),
	.byte_mask(byte_mask),
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

assign LED_USER = stress_activity | stress_failed;
assign LED_POWER = 2'd0;
assign LED_DISK = 2'd0;
assign BUTTONS = 2'd0;
`ifdef MISTER_PSRAM_DIAG
assign DIAG_LED = {stress_failed, (loop_count != 0) | stress_activity, 6'd0};
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
