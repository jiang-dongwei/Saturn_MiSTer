`timescale 1ns/1ps
module tb_plan_a_trace_address_bank;
    reg clk = 0, sample_taken = 0;
    reg [2:0] page = 0;
    reg [31:0] cbus_address = 0, ibus_address = 0;
    reg advance_source = 0;
    reg [31:0] next_cbus_address = 0, next_ibus_address = 0;
    wire [15:0] word;
    reg [15:0] sampled_word = 0;
    integer checks = 0;
    plan_a_trace_address_bank dut(.*);
    always @(posedge clk) begin
        if (sample_taken) sampled_word <= word;
        if (advance_source) begin
            cbus_address <= next_cbus_address;
            ibus_address <= next_ibus_address;
        end
    end
    task automatic tick;
        #5 clk = 1;
        #1;
        #4 clk = 0;
    endtask
    task automatic check_sample(input [2:0] selected_page, input [15:0] expected);
        page = selected_page;
        sample_taken = 1;
        tick();
        if (sampled_word !== expected)
            $fatal(1, "Address bank page=%0d got=%h expected=%h", page, sampled_word, expected);
        checks = checks + 1;
        sample_taken = 0;
    endtask
    task automatic check_tail(input [31:0] expected_cbus, expected_ibus);
        check_sample(3, expected_cbus[31:16]);
        check_sample(4, expected_ibus[15:0]);
        check_sample(5, expected_ibus[31:16]);
    endtask
    task automatic capture_pair(input [31:0] expected_cbus, expected_ibus);
        cbus_address = expected_cbus;
        ibus_address = expected_ibus;
        check_sample(2, expected_cbus[15:0]);
        cbus_address = ~expected_cbus;
        ibus_address = ~expected_ibus;
        check_tail(expected_cbus, expected_ibus);
    endtask
    initial begin
        check_tail(0, 0);
        capture_pair(32'h1234fffe, 32'h89ab5678);

        // A page transition without a sample must not replace the frozen pair.
        page = 2;
        cbus_address = 32'hdeadc0de;
        ibus_address = 32'h10203040;
        sample_taken = 0;
        tick();
        check_tail(32'h1234fffe, 32'h89ab5678);

        // Model page crossing one cycle later than the snapshot request.
        cbus_address = 32'habcde120;
        ibus_address = 32'h06001234;
        check_sample(1, 0);
        page = 2;
        check_sample(2, 16'he120);
        cbus_address = 32'hffffffff;
        ibus_address = 32'h77777777;
        check_tail(32'habcde120, 32'h06001234);

        // Synchronous address producers may update on the snapshot edge.
        cbus_address = 32'hfedcba98;
        ibus_address = 32'h76543210;
        page = 2;
        sample_taken = 1;
        next_cbus_address = 32'h11112222;
        next_ibus_address = 32'h33334444;
        advance_source = 1;
        #5 clk = 1;
        #1;
        if (sampled_word !== 16'hba98)
            $fatal(1, "Snapshot used the following cycle's address");
        checks = checks + 1;
        #4 clk = 0;
        advance_source = 0;
        sample_taken = 0;
        check_tail(32'hfedcba98, 32'h76543210);

        for (integer p = 0; p < 8; p = p + 1) begin
            if (p < 2 || p > 5) check_sample(3'(p), 0);
        end
        check_tail(32'hfedcba98, 32'h76543210);
        capture_pair(32'h0700ffff, 32'h20000001);
        capture_pair(32'hffffffff, 32'h00000000);
        $display("PASS address bank capture/sample page skew/freeze/NBA checks=%0d", checks);
        $finish;
    end
    initial begin
        #100000;
        $fatal(1, "Address bank regression timeout");
    end
endmodule
