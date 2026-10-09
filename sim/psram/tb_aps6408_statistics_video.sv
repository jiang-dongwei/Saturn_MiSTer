`timescale 1ns/1ps
module tb_aps6408_statistics_video;
    reg clk=0, ready=1, failed=0;
    reg [703:0] report=0;
    wire ce_pixel, hsync, vsync, de;
    wire [7:0] red, green, blue;
    aps6408_statistics_video dut (.*);
    always #5 clk=~clk;
    integer row, field_index;
    reg [14:0] color;
    reg [31:0] field;
    initial begin
        for (field_index=0;field_index<22;field_index=field_index+1)
            report[field_index*32+:32]=32'h01234567^(32'h89ABCDEF*field_index);
        for (row=0;row<240;row=row+1) begin
            wait(dut.v_count==row && dut.h_count==16 && ce_pixel);
            #1;
            case (row)
                0: color=15'h03FF;
                1: color=15'h03E0;
                2: color=15'h7C1F;
                3: color=15'h7FE0;
                default: begin
                    color=15'h001F;
                    if (row<180) begin
                        field=report[((row-4)/8)*32+:32];
                        color=(field>>(((row-4)%8)*4))&15;
                    end
                end
            endcase
            if ({red,green,blue}!=={color[4:0],3'b0,color[9:5],3'b0,color[14:10],3'b0})
                $fatal(1,"video barcode row %0d mismatch",row);
            @(negedge clk);
        end
        wait(dut.v_count==0 && dut.h_count==16);
        ready=0; #1;
        if ({red,green,blue}!==24'h0000F8) $fatal(1,"running screen mismatch");
        failed=1; #1;
        if ({red,green,blue}!==24'hF8F800) $fatal(1,"fault report header mismatch");
        $display("RAMH statistics video PASS: all 180 report rows and incomplete/fault screens");
        $finish;
    end
    initial begin #10000000; $fatal(1,"video timeout"); end
endmodule
