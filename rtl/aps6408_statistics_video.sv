module aps6408_statistics_video (
    input clk, ready, failed,
    input [703:0] report,
    output ce_pixel, hsync, vsync, de,
    output [7:0] red, green, blue
);
    reg [9:0] h_count=0, v_count=0;
    reg [2:0] pixel_divider=0;
    wire tick = pixel_divider == 4;
    assign ce_pixel = tick;
    assign hsync = !(h_count >= 336 && h_count < 368);
    assign vsync = !(v_count >= 243 && v_count < 246);
    assign de = h_count < 320 && v_count < 240;
    always @(posedge clk) begin
        if (tick) begin
            pixel_divider <= 0;
            if (h_count == 431) begin
                h_count <= 0;
                v_count <= v_count == 261 ? 0 : v_count + 1'b1;
            end else h_count <= h_count + 1'b1;
        end else pixel_divider <= pixel_divider + 1'b1;
    end
    reg [14:0] color;
    reg [31:0] field;
    wire [9:0] report_row = v_count - 4;
    always @* begin
        field = 0;
        color = failed ? 15'h001F : ready ?
                (report[160 +: 32] != 0 ? 15'h001F : 15'h03E0) : 15'h7C00;
        if (ready || failed) begin
            case (v_count)
                0: color = 15'h03FF;
                1: color = 15'h03E0;
                2: color = 15'h7C1F;
                3: color = 15'h7FE0;
                default: if (v_count < 180) begin
                    field = report[report_row[7:3]*32 +: 32];
                    color = {11'd0,field[report_row[2:0]*4 +: 4]};
                end
            endcase
        end
        if (!de) color = 0;
    end
    assign red = {color[4:0],3'b000};
    assign green = {color[9:5],3'b000};
    assign blue = {color[14:10],3'b000};
endmodule
