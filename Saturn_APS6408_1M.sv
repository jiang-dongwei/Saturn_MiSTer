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
    "APS6408 RAMH 1M;;",
    "O34,PSRAM clock,8.47 MHz,16.93 MHz,33.87 MHz;",
    "O56,Data pattern,A55A8041,5AA57FBE,FFFFFFFF,00000000;",
    "T7,Restart test;",
    "R0,Reset;",
    "-;",
    "I,One full 1 MiB pattern; continue after compare errors;",
    "I,Uses original RAMH adapter; internal 50 ohm drive;",
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
reg [7:0] status_meta=0, status_sync=0;
reg [1:0] selected_speed=0, selected_seed=0;
reg mode_restart=0;
always @(posedge clk_67) begin
    status_meta <= status[7:0];
    status_sync <= status_meta;
    mode_restart <= 0;
    if (selected_speed != status_sync[4:3] || selected_seed != status_sync[6:5]) begin
        selected_speed <= status_sync[4:3];
        selected_seed <= status_sync[6:5];
        mode_restart <= 1;
    end
end
wire reset_request = RESET | buttons[1] | status_sync[0] | status_sync[7] |
                     mode_restart | !pll_locked |
                     (selected_speed != status_sync[4:3]) | (selected_seed != status_sync[6:5]);
reg [2:0] reset_pipe=3'b111;
always @(posedge clk_67) begin
    if (reset_request) reset_pipe <= 3'b111;
    else reset_pipe <= {reset_pipe[1:0],1'b0};
end
wire diagnostic_reset=reset_pipe[2];
wire [19:2] test_addr;
wire [31:0] test_din, test_dout;
wire [3:0] test_wr;
wire test_rd, test_busy, init_done, init_error, adapter_error, ready, failed;
wire [703:0] report;
wire [15:0] device_id;
wire [7:0] stage_code;
wire [1:0] result_code=ready ? (report[160 +: 32] != 0 ? 2'd2 : 2'd1) : failed ? 2'd2 : 2'd0;
wire [7:0] diagnostic_leds={6'd0,failed,ready};
wire diagnostic_activity=!ready && !failed;
ramh_aps6408_adapter ramh_psram (
    .clk(clk_33), .reset(diagnostic_reset), .engine_clk(clk_67),
    .engine_reset(diagnostic_reset), .clk_phy(clk_phy), .speed_select(selected_speed),
    .addr(test_addr), .din(test_din), .wr(test_wr), .rd(test_rd), .burst(1'b0), .rfs(1'b0),
    .dout(test_dout), .busy(test_busy), .init_done(init_done), .init_error(init_error),
    .adapter_error(adapter_error), .device_id(device_id), .stage_code(stage_code),
    .PSRAM_CLK(PSRAM_CLK), .PSRAM_CE_N(PSRAM_CE_N), .PSRAM_DQ(PSRAM_DQ), .PSRAM_DQS(PSRAM_DQS)
);
aps6408_ramh_statistics tester (
    .clk(clk_33), .reset(diagnostic_reset), .seed_select(selected_seed),
    .init_done(init_done), .init_error(init_error), .adapter_error(adapter_error),
    .busy(test_busy), .dout(test_dout), .addr(test_addr), .din(test_din), .wr(test_wr), .rd(test_rd),
    .ready(ready), .failed(failed), .report(report)
);
aps6408_statistics_video video (
    .clk(clk_33), .ready(ready), .failed(failed), .report(report), .ce_pixel(CE_PIXEL),
    .red(VGA_R), .green(VGA_G), .blue(VGA_B), .hsync(VGA_HS), .vsync(VGA_VS), .de(VGA_DE)
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
