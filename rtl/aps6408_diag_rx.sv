module aps6408_diag_rx (
    input clk,
    input reset,
    input arm,
    input [1:0] speed,
    input psram_clk,
    input [7:0] dq,
    input dqs,
    output reg done = 0,
    output reg [15:0] early_word = 0,
    output reg [15:0] mid_word = 0,
    output reg [15:0] late_word = 0,
    output reg [15:0] edge_word = 0,
    output reg [7:0] dq_input_sample
);
    reg dqs_sample;
    reg dqs_history;
    reg dqs_prev;
    reg [7:0] dq_prev;
    reg [7:0] dq_prev2;
    reg arm_meta = 0;
    reg arm_sync = 0;
    reg armed = 0;
    reg clk_history;
    reg clk_prev;
    reg [6:0] edge_count = 0;
    reg [1:0] active_speed = 0;
    reg [1:0] byte_count = 0;
    reg [2:0] second_delay = 0;
    reg late_pending = 0;
    reg late_byte = 0;
    wire rise = dqs_history && !dqs_prev;
    wire fall = !dqs_history && dqs_prev;
    wire capture = armed && !done &&
        ((byte_count == 0 && rise) ||
         (byte_count == 1 && (active_speed == 2 ? second_delay == 0 : fall)));

    always @(posedge clk) begin
        dq_input_sample <= dq;
        dq_prev <= dq_input_sample;
        dq_prev2 <= dq_prev;
        dqs_sample <= dqs;
        dqs_history <= dqs_sample;
        dqs_prev <= dqs_history;
        clk_history <= psram_clk;
        clk_prev <= clk_history;
        arm_meta <= arm;
        arm_sync <= arm_meta;

        if (reset || !arm_sync) begin
            armed <= 0;
            done <= 0;
            byte_count <= 0;
            late_pending <= 0;
            edge_count <= 0;
        end else if (!armed) begin
            armed <= 1;
            active_speed <= speed;
            early_word <= 0;
            mid_word <= 0;
            late_word <= 0;
            edge_word <= 0;
        end else if (!done) begin
            if (clk_history != clk_prev) edge_count <= edge_count + 1'b1;
            if (byte_count == 1 && second_delay != 0)
                second_delay <= second_delay - 1'b1;
            if (active_speed == 2 && byte_count != 0 && fall && edge_word[7:0] == 0)
                edge_word[7:0] <= {1'b0, edge_count};
            if (late_pending) begin
                if (late_byte) begin
                    late_word[7:0] <= dq_input_sample;
                    done <= 1;
                end else late_word[15:8] <= dq_input_sample;
                late_pending <= 0;
            end
            if (capture) begin
                if (byte_count == 0) begin
                    early_word[15:8] <= dq_prev2;
                    mid_word[15:8] <= dq_prev;
                    edge_word[15:8] <= {1'b0, edge_count};
                    second_delay <= 3;
                end else begin
                    early_word[7:0] <= dq_prev2;
                    mid_word[7:0] <= dq_prev;
                    if (active_speed != 2) edge_word[7:0] <= {1'b0, edge_count};
                end
                late_pending <= 1;
                late_byte <= (byte_count != 0);
                byte_count <= byte_count + 1'b1;
            end
        end
    end
endmodule
