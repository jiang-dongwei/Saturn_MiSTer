`timescale 1ns/1ps
module tb_plan_a_uart_trace;
    parameter integer DIVIDER = 8;
    localparam integer BIT_NS = 20 * DIVIDER;
    reg clk = 0, ram_clk = 0, engine_clk = 0, sys_clk = 0;
    reg engine_running = 1, reset = 1;
    always #10 clk = !clk;
    always #7 ram_clk = !ram_clk;
    always #13 if (engine_running) engine_clk = !engine_clk;
    always #17 sys_clk = !sys_clk;
    reg [15:0] ram_data = 16'h1357;
    reg [7:0] engine_data = 8'hc6;
    reg [23:0] sys_data = 24'habcdef;
    wire tx;
    plan_a_uart_trace #(.DIVIDER(DIVIDER)) dut(.*);
    reg [7:0] frame [0:10];
    integer frames = 0;
    reg stopped_request;
    task automatic byte_read(output reg [7:0] value);
        @(negedge tx);
        #(BIT_NS / 2);
        if (tx !== 0) $fatal(1, "Missing start bit");
        for (integer bit_index = 0; bit_index < 8; bit_index = bit_index + 1) begin
            #(BIT_NS);
            value[bit_index] = tx;
        end
        #(BIT_NS);
        if (tx !== 1) $fatal(1, "Invalid stop bit");
    endtask
    task automatic frame_read(input integer expected_sequence);
        reg [7:0] sum;
        sum = 0;
        for (integer index = 0; index < 11; index = index + 1) begin
            byte_read(frame[index]);
            sum = sum ^ frame[index];
        end
        if (frame[0] !== 8'ha5 || frame[1] !== 8'h5a || sum !== 0)
            $fatal(1, "Header/checksum failure");
        if (frame[2] !== expected_sequence[7:0]) $fatal(1, "Sequence discontinuity");
        frames = frames + 1;
        $display("FRAME total=%0d sequence=%0d valid=%h", frames, frame[2], frame[3]);
    endtask
    task automatic contents(input reg [7:0] valid_mask,
                             input reg [15:0] ram_value,
                             input reg [7:0] engine_value,
                             input reg [23:0] sys_value);
        if (frame[3] !== valid_mask || {frame[5],frame[4]} !== ram_value ||
            frame[6] !== engine_value || {frame[9],frame[8],frame[7]} !== sys_value)
            $fatal(1, "Snapshot payload mismatch valid=%h RAM=%h stage=%h SYS=%h",
                   frame[3], {frame[5],frame[4]}, frame[6], {frame[9],frame[8],frame[7]});
    endtask
    initial begin
        #45;
        if (tx !== 1) $fatal(1, "Reset must hold UART idle high");
        reset = 0;
        frame_read(0);
        contents(0, 0, 0, 0);
        frame_read(1);
        contents(7, 16'h1357, 8'hc6, 24'habcdef);
        frame_read(2);
        contents(7, 16'h1357, 8'hc6, 24'habcdef);
        ram_data = 16'h2468;
        engine_data = 8'h3c;
        sys_data = 24'h123456;
        frame_read(3);
        contents(7, 16'h1357, 8'hc6, 24'habcdef);
        frame_read(4);
        contents(7, 16'h2468, 8'h3c, 24'h123456);
        engine_running = 0;
        frame_read(5);
        stopped_request = dut.engine_request;
        frame_read(6);
        if (dut.engine_request !== stopped_request) $fatal(1, "Stopped-source request toggled");
        if (frame[3] !== 5) $fatal(1, "Stopped engine must be invalid without blocking UART");
        frame_read(7);
        if (dut.engine_request !== stopped_request) $fatal(1, "Pending-source request toggled");
        if (frame[3] !== 5) $fatal(1, "Pending request must not toggle/alias while source stopped");
        engine_data = 8'h69;
        engine_running = 1;
        frame_read(8);
        frame_read(9);
        contents(7, 16'h2468, 8'h69, 24'h123456);
        @(negedge tx);
        #33 reset = 1;
        #40;
        if (tx !== 1) $fatal(1, "Mid-packet reset must restore idle high");
        reset = 0;
        frame_read(0);
        contents(0, 0, 0, 0);
        frame_read(1);
        frame_read(2);
        contents(7, 16'h2468, 8'h69, 24'h123456);
        wait (dut.engine_request == 1 && dut.engine_ready && dut.engine_valid);
        engine_running = 0;
        reset = 1;
        #50 reset = 0;
        frame_read(0);
        frame_read(1);
        if (frame[3] & 2) $fatal(1, "Reset/stopped-source old ACK must not validate stale data");
        frame_read(2);
        contents(5, 16'h2468, 0, 24'h123456);
        reset = 1;
        #50 reset = 0;
        frame_read(0);
        frame_read(1);
        if (frame[3] & 2) $fatal(1, "Reset of pending request must stay invalid");
        frame_read(2);
        contents(5, 16'h2468, 0, 24'h123456);
        engine_data = 8'h96;
        engine_running = 1;
        frame_read(3);
        frame_read(4);
        frame_read(5);
        frame_read(6);
        contents(7, 16'h2468, 8'h96, 24'h123456);
        $display("PASS UART 8N1 checksum/sequence/atomic frame/reset/stopped-clock recovery divider=%0d frames=%0d", DIVIDER, frames);
        $finish;
    end
    initial begin
        #(BIT_NS * 110 * 40);
        $fatal(1, "UART regression timeout");
    end
endmodule
