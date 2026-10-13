`timescale 1ns/1ps
module tb_plan_a_dcc_owners;
    reg clk=0, rst=0, ce=1, breq=1, exbreq=1, bgr=1;
    wire [1:0] owners;
    wire back, exback, release_n;
    integer checks=0;
    DCC dut(.CLK(clk),.RST_N(rst),.CE_R(ce),.CE_F(1'b1),.RES_N(rst),
        .A(24'b0),.BS_N(1'b1),.CS0_N(1'b1),.CS1_N(1'b1),.CS2_N(1'b1),
        .RD_WR_N(1'b1),.WE_N(2'b11),.RD_N(1'b1),
        .BRLS_N(release_n),.BGR_N(bgr),.BREQ_N(breq),.BACK_N(back),
        .EXBREQ_N(exbreq),.EXBACK_N(exback),.WTIN_N(1'b1),.IVECF_N(1'b1),
        .HINT_N(1'b1),.VINT_N(1'b1),.DWAIT_N(1'b1),.FAST(1'b0),.PA_BUS_OWNERS(owners));
    task automatic tick;
        #5 clk=1; #5 clk=0;
    endtask
    task automatic check(input [1:0] expected, input expected_back, expected_exback);
        if(owners!==expected || back!==expected_back || exback!==expected_exback)
            $fatal(1,"DCC ownership flags/grants mismatch owners=%b back=%b exback=%b",owners,back,exback);
        checks=checks+1;
    endtask
    initial begin
        tick; rst=1; tick; check(0,1,1);
        breq=0; tick; check(2,1,1);
        if(release_n!==0) $fatal(1,"Master release request missing");
        bgr=0; #1; check(2,0,1);
        ce=0; breq=1; tick; check(2,0,1);
        ce=1; tick; check(0,1,1);
        exbreq=0; tick; check(1,1,0);
        breq=0; tick; check(1,1,0);
        exbreq=1; tick; check(0,1,1);
        tick; check(2,0,1);
        rst=0; tick; check(0,1,1);
        $display("PASS DCC observer ownership/grants/clock-enable/reset checks=%0d",checks);
        $finish;
    end
    initial begin #10000; $fatal(1,"DCC observer timeout"); end
endmodule
