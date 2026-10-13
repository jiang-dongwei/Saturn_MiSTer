`timescale 1ns/1ps

// Event-binding unit test; pipeline inputs are seeded, not executed as a program.
// Run on Runner with actual SH_pkg, SH_regfile (SIM), and SH_core sources.
module tb_plan_a_core_fault;
    import SH2_PKG::*;

    reg clk = 0, rst_n = 0, res_n = 0, ce = 1, en = 1;
    reg bus_wait = 0, int_req = 0;
    wire event_taken;
    wire [62:0] details;
    integer checks = 0;

    SH_core #(.VER(1)) dut (
        .CLK(clk), .RST_N(rst_n), .RES_N(res_n), .CE(ce), .EN(en),
        .NMI_N(1'b1), .BUS_DI(32'h00090009), .BUS_WAIT(bus_wait),
        .INT_LVL(4'd1), .INT_VEC(8'h41), .INT_REQ(int_req), .VECT_WAIT(1'b0),
        .BUS_A(), .BUS_DO(), .BUS_WR(), .BUS_BA(), .BUS_REQ(), .BUS_ID(),
        .BUS_TAS(), .MAC_SEL(), .MAC_OP(), .MAC_S(), .MAC_WE(),
        .INT_MASK(), .INT_ACK(), .INT_ACP(), .VECT_REQ(), .SLEEP(),
        .PA_FAULT_EVENT(event_taken), .PA_FAULT_DETAILS(details)
    );

    task automatic edge_tick;
        #2; clk = 1;
        #2; clk = 0;
        #2;
    endtask

    task automatic seed;
        clk = 0;
        rst_n = 0; res_n = 0; ce = 1; en = 1;
        bus_wait = 0; int_req = 0;
        edge_tick();
        rst_n = 1; res_n = 1;
        #2;
        // Clock stays low throughout stimulus/checks. Avoid force on struct members.
        dut.RES_EXP = 0;
        dut.INT_REQ_LATCH = 0;
        dut.ILI_EXP = 0;
        dut.STATE = 0;
        dut.IFID_STALL = 0;
        dut.MA_ACTIVE = 0;
        dut.IF_ACTIVE = 0;
        dut.VECT_ACTIVE = 0;
        dut.INST_SPLIT = 0;
        dut.MAWB_STALL = 0;
        dut.SLP = 0;
        dut.PIPE.ID.IR = 16'hffff;
        dut.PIPE.ID.PC = 32'h06001002;
        dut.PIPE.EX.IR = 16'h0009;
        dut.PIPE.EX.PC = 32'h06002004;
        dut.PIPE.EX.DI = DECI_RESET;
        #2;
    endtask

    task automatic expect_event(input string name, input bit expected);
        #2;
        if (event_taken !== expected)
            $fatal(1, "%s: event=%b expected=%b DEC_IR=%h ILI=%b ID_STALL=%b", 
                   name, event_taken, expected, dut.DEC_IR, dut.ID_DECI.ILI, dut.ID_STALL);
        checks = checks + 1;
        $display("PASS %s event=%b details=%h", name, event_taken, details);
    endtask

    task automatic expect_details(input string name, input [31:0] pc,
                                  input [15:0] ir, input [7:0] vector,
                                  input bit ds, input bit ifid, input [2:0] state);
        #2;
        if (details[31:0] !== pc || details[47:32] !== ir ||
            details[55:48] !== vector || details[58:56] !== state ||
            details[61] !== ifid || details[62] !== ds ||
            details[60] !== dut.MA_ACTIVE || details[59] !== dut.IF_ACTIVE)
            $fatal(1, "%s: bad details=%h pc=%h ir=%h vector=%h ds=%b ifid=%b state=%d",
                   name, details, pc, ir, vector, ds, ifid, state);
        if (dut.DEC_IR !== ir || !dut.ID_DECI.ILI)
            $fatal(1, "%s: stimulus did not reach actual illegal decode", name);
    endtask

    task automatic accept_illegal(input string name, input bit slot);
        edge_tick();
        if (!dut.ILI_EXP || dut.ILSI !== slot)
            $fatal(1, "%s: actual exception latch not set: ILI_EXP=%b ILSI=%b",
                   name, dut.ILI_EXP, dut.ILSI);
        if (event_taken)
            $fatal(1, "%s: event repeated after ILI_EXP was set", name);
    endtask

    initial begin
        seed();
        dut.PIPE.ID.IR = 16'h0009;
        expect_event("legal NOP", 0);
        if (dut.ID_DECI.ILI) $fatal(1, "NOP decoded as illegal");
        edge_tick();
        if (dut.ILI_EXP) $fatal(1, "NOP set actual exception latch");

        seed();
        expect_event("FFFF illegal instruction", 1);
        expect_details("ID pairing", 32'h06001002, 16'hffff, 8'h04, 0, 0, 0);
        accept_illegal("illegal vector4", 0);

        seed();
        dut.PIPE.EX.DI.BR.BI = 0;
        dut.PIPE.EX.DI.BR.BT = UCB;
        dut.PIPE.EX.DI.BR.BD = 1;
        expect_event("delayed branch slot illegal", 1);
        expect_details("slot pairing", 32'h06001002, 16'hffff, 8'h06, 1, 0, 0);
        accept_illegal("illegal slot vector6", 1);

        seed();
        dut.PIPE.EX.DI.BR.BI = 0;
        dut.PIPE.EX.DI.BR.BT = UCB;
        dut.PIPE.EX.DI.BR.BD = 0;
        expect_event("non-delayed branch substitutes NOP", 0);
        if (dut.DEC_IR !== 16'h0009) $fatal(1, "branch did not substitute NOP");

        seed();
        dut.IFID_STALL = 1;
        dut.STATE = 1;
        dut.PIPE.ID.IR = 16'h0009;
        dut.PIPE.EX.IR = 16'hffff;
        expect_event("IFID selects illegal EX IR", 1);
        expect_details("EX pairing", 32'h06002004, 16'hffff, 8'h04, 0, 1, 1);
        accept_illegal("EX selected illegal", 0);

        seed();
        dut.IFID_STALL = 1;
        dut.STATE = 1;
        expect_event("IFID ignores illegal ID when EX is NOP", 0);
        if (dut.DEC_IR !== 16'h0009) $fatal(1, "IFID failed to select EX NOP");

        seed(); en = 0;
        expect_event("EN blocks event", 0);
        edge_tick();
        if (dut.ILI_EXP) $fatal(1, "EN=0 set actual exception latch");
        seed(); ce = 0;
        expect_event("CE blocks event", 0);
        edge_tick();
        if (dut.ILI_EXP) $fatal(1, "CE=0 set actual exception latch");

        seed(); dut.MA_ACTIVE = 1; bus_wait = 1;
        expect_event("bus-derived ID_STALL blocks event", 0);
        if (!dut.ID_STALL) $fatal(1, "BUS_WAIT did not produce actual ID_STALL");
        edge_tick();
        if (dut.ILI_EXP) $fatal(1, "ID_STALL set actual exception latch");
        seed(); dut.INST_SPLIT = 1;
        expect_event("split-derived ID_STALL blocks event", 0);
        if (!dut.ID_STALL) $fatal(1, "INST_SPLIT did not produce actual ID_STALL");

        seed(); rst_n = 0;
        expect_event("RST_N blocks event", 0);
        seed(); res_n = 0;
        expect_event("RES_N blocks event", 0);
        seed(); dut.RES_EXP = 1;
        expect_event("reset exception pending blocks illegal", 0);
        seed(); int_req = 1;
        expect_event("live interrupt blocks illegal", 0);
        if (!dut.INT_EXP) $fatal(1, "INT_REQ did not produce actual INT_EXP");
        seed(); dut.INT_REQ_LATCH = 1;
        expect_event("latched interrupt blocks illegal", 0);
        if (!dut.INT_EXP) $fatal(1, "INT_REQ_LATCH did not produce actual INT_EXP");
        seed(); dut.ILI_EXP = 1;
        expect_event("existing illegal exception blocks repeat", 0);

        seed();
        dut.PIPE.EX.DI.BR.BI = 0;
        dut.PIPE.EX.DI.BR.BT = UCB;
        dut.PIPE.EX.DI.BR.BD = 1;
        int_req = 1;
        expect_event("interrupt deferred in illegal delay slot", 1);
        if (dut.INT_EXP) $fatal(1, "live interrupt not deferred in slot");
        expect_details("slot with pending IRQ", 32'h06001002, 16'hffff, 8'h06, 1, 0, 0);
        accept_illegal("slot wins deferred IRQ", 1);

        $display("PASS: %0d actual-core fault binding cases; not execution/cache/memory coverage", checks);
        $finish;
    end
    initial begin #100000; $fatal(1,"Core observer timeout"); end
endmodule
