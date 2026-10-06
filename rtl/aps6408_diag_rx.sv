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
    output reg [15:0] clock_word = 0,
    output reg clock_done = 0
);
    reg [7:0] dq_input_sample;
    reg dqs_sample;
    (* preserve *) reg dqs_history;
    (* preserve *) reg dqs_prev;
    (* preserve *) reg [7:0] dq_prev;
    (* preserve *) reg [7:0] dq_prev2;
    reg arm_meta = 0;
    reg arm_sync = 0;
    reg armed = 0;
    (* preserve *) reg clk_history;
    (* preserve *) reg clk_prev;
    reg [6:0] edge_count = 0;
    reg [1:0] active_speed = 0;
    reg [1:0] byte_count = 0;
    reg [2:0] second_delay = 0;
    reg [1:0] late_pending = 0;
    reg late_byte = 0;
    reg reference_pending = 0;
    reg [1:0] reference_delay = 0;
    reg reference_byte = 0;
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
            reference_pending <= 0;
            clock_done <= 0;
        end else if (!armed) begin
            armed <= 1;
            active_speed <= speed;
            early_word <= 0;
            mid_word <= 0;
            late_word <= 0;
            edge_word <= 0;
            clock_word <= 0;
        end else begin
            if (clk_history != clk_prev) edge_count <= edge_count + 1'b1;
            if (reference_pending) begin
                if (reference_delay != 0) reference_delay <= reference_delay - 1'b1;
                else begin
                    reference_pending <= 0;
                    if (reference_byte) begin
                        clock_word[7:0] <= dq_prev;
                        clock_done <= 1;
                    end else clock_word[15:8] <= dq_prev;
                end
            end
            if (clk_history != clk_prev && (edge_count == 8 || edge_count == 9)) begin
                reference_pending <= 1;
                reference_delay <= 2;
                reference_byte <= (edge_count == 9);
            end
            if (!done) begin
                if (byte_count == 1 && second_delay != 0)
                    second_delay <= second_delay - 1'b1;
                if (active_speed == 2 && byte_count != 0 && fall && edge_word[7:0] == 0)
                    edge_word[7:0] <= {1'b0, edge_count};
                late_pending <= {late_pending[0], 1'b0};
                if (late_pending[1]) begin
                    if (late_byte) begin
                        late_word[7:0] <= dq_prev;
                        done <= 1;
                    end else late_word[15:8] <= dq_prev;
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
                    late_pending <= 2'b01;
                    late_byte <= (byte_count != 0);
                    byte_count <= byte_count + 1'b1;
                end
            end
        end
    end
endmodule
