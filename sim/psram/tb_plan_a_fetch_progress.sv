`timescale 1ns/1ps
module tb_plan_a_fetch_progress;
    reg clk=0, reset=1, sample_taken=0, accepted=0;
    wire progress;
    reg captured=0;
    reg [7:0] modulo_count=0;
    integer checks=0;
    plan_a_fetch_progress dut(.*);
    always @(posedge clk) begin
        if(sample_taken) captured<=progress;
        if(reset) modulo_count<=0;
        else if(accepted) modulo_count<=modulo_count+1'b1;
    end
    task automatic tick;
        #5 clk=1; #5 clk=0;
    endtask
    task automatic sample(input expected);
        sample_taken=1; tick;
        if(captured!==expected) $fatal(1,"Progress capture got=%b expected=%b",captured,expected);
        checks=checks+1; sample_taken=0;
    endtask
    initial begin
        tick; reset=0;
        sample(0);
        accepted=1; sample(1);
        accepted=0; sample(0);
        reset=1; tick; reset=0;
        accepted=1;
        for(integer n=0;n<256;n=n+1) tick;
        accepted=0;
        if(modulo_count!==0) $fatal(1,"Modulo alias setup failed");
        sample(1); sample(0);
        accepted=1; tick; accepted=0;
        reset=1; tick; reset=0; sample(0);
        $display("PASS fetch progress same-edge/256-alias/reset checks=%0d",checks);
        $finish;
    end
    initial begin #100000; $fatal(1,"Progress timeout"); end
endmodule
