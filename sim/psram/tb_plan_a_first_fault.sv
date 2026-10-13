`timescale 1ns/1ps
module tb_plan_a_first_fault;
    reg clk=0,reset=0,master_event=0,slave_event=0;
    reg [62:0] master_details=0,slave_details=0;
    wire [63:0] fault;
    integer checks=0;
    plan_a_first_fault dut(.*);
    task automatic tick;
        #5 clk=1; #5 clk=0;
    endtask
    task automatic check(input [63:0] expected);
        if(fault!==expected) $fatal(1,"First fault got=%h expected=%h",fault,expected);
        checks=checks+1;
    endtask
    initial begin
        master_details={15'h0004,16'hffff,32'h06004020};
        slave_details={15'h4006,16'h1234,32'h06005040};
        tick; check(0);
        master_event=1; slave_event=1; reset=1; tick; check(0);
        reset=0; tick; check({16'h8004,16'hffff,32'h06004020});
        master_details=0; master_event=0; tick;
        check({16'h8004,16'hffff,32'h06004020});
        reset=1; tick; check(0);
        reset=0; tick; check({16'hc406,16'h1234,32'h06005040});
        slave_event=0; master_event=1; tick;
        check({16'hc406,16'h1234,32'h06005040});
        $display("PASS first illegal latch reset/first-only/master-priority/slave checks=%0d",checks);
        $finish;
    end
    initial begin #10000; $fatal(1,"First fault timeout"); end
endmodule
