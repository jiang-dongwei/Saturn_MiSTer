module aps6408_diag_rx (
    input clk,
    input reset,
    input arm,
    input [1:0] speed,
    input [1:0] d1_mode,
    input psram_clk,
    input [7:0] dq,
    input dqs,
    output reg done = 0,
    output reg [15:0] early_word = 0,
    output reg [15:0] mid_word = 0,
    output reg [15:0] center_word = 0,
    output reg [15:0] late_word = 0,
    output reg [15:0] edge_word = 0,
    output reg [15:0] clock_word = 0,
    output reg clock_done = 0
);
    wire [8:0] input_rising, input_falling;
    aps6408_diag_ddio_input input_capture (
        .clk(clk), .data({dqs, dq}),
        .rising(input_rising), .falling(input_falling)
    );
    (* preserve *) reg [8:0] pair_low, pair_high;
    reg [8:0] previous_low, previous_high, older_high;
    reg clock_negative, clock_rising, clock_falling;
    reg clock_low, clock_high, previous_clock_low, previous_clock_high, older_clock_high;
    (* preserve, altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *) reg arm_meta = 0;
    (* preserve, altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *) reg arm_sync = 0;
    reg armed = 0;
    reg [1:0] active_speed = 0;
    reg [1:0] active_d1_mode = 0;
    reg [6:0] edge_count = 0;
    reg [1:0] byte_count = 0;
    reg [2:0] second_delay = 0;
    reg second_phase = 0;
    reg [1:0] rise_event, fall_event, clock_event;
    reg [6:0] edge_low, edge_high;
    (* preserve *) reg [31:0] data_low, data_high;
    reg reference_pending = 0;
    reg [1:0] reference_delay = 0;
    reg reference_phase = 0;
    reg reference_byte = 0;
    wire clock_change_low = previous_clock_low != older_clock_high;
    wire clock_change_high = previous_clock_high != previous_clock_low;
    wire first_capture = byte_count == 0 && (|rise_event);
    wire fixed_second = active_speed != 0 && active_d1_mode != 3;
    wire [2:0] nominal_second_delay = active_speed == 1 ? 3'd3 : 3'd1;
    wire second_capture = byte_count == 1 &&
        (fixed_second ? second_delay == 0 : (|fall_event));
    wire capture_phase = byte_count == 0 ? rise_event[1] :
                         fixed_second ? second_phase : fall_event[1];
    wire [31:0] capture_data = capture_phase ? data_high : data_low;

    always @(negedge clk) clock_negative <= psram_clk;
    always @(posedge clk) begin
        clock_rising <= psram_clk;
        clock_falling <= clock_negative;
        pair_low <= input_falling;
        pair_high <= input_rising;
        previous_low <= pair_low;
        previous_high <= pair_high;
        older_high <= previous_high;
        clock_low <= clock_falling;
        clock_high <= clock_rising;
        previous_clock_low <= clock_low;
        previous_clock_high <= clock_high;
        older_clock_high <= previous_clock_high;
        // EARLY (-1), MID (0), CENTER (+2) and LATE (+3) DDR samples.
        data_low <= {older_high[7:0], previous_low[7:0], pair_low[7:0], pair_high[7:0]};
        data_high <= {previous_low[7:0], previous_high[7:0], pair_high[7:0], input_falling[7:0]};
        rise_event <= {previous_high[8] && !previous_low[8],
                       previous_low[8] && !older_high[8]};
        fall_event <= {!previous_high[8] && previous_low[8],
                       !previous_low[8] && older_high[8]};
        clock_event <= {clock_change_high, clock_change_low};
        edge_low <= edge_count;
        edge_high <= edge_count + clock_change_low;
        arm_meta <= arm;
        arm_sync <= arm_meta;

        if (reset || !arm_sync) begin
            armed <= 0;
            done <= 0;
            byte_count <= 0;
            edge_count <= 0;
            reference_pending <= 0;
            clock_done <= 0;
        end else if (!armed) begin
            armed <= 1;
            active_speed <= speed;
            active_d1_mode <= speed == 0 ? 2'd0 : d1_mode;
            early_word <= 0;
            mid_word <= 0;
            center_word <= 0;
            late_word <= 0;
            edge_word <= 0;
            clock_word <= 0;
        end else begin
            edge_count <= edge_count + clock_change_low + clock_change_high;
            if (reference_pending) begin
                if (reference_delay != 0) reference_delay <= reference_delay - 1'b1;
                else begin
`ifdef APS6408_DIAG_SIM
                    if ($test$plusargs("trace_rx")) $display("REF capture t=%0t byte=%b phase=%b low=%h high=%h", $time, reference_byte, reference_phase, data_low, data_high);
`endif
                    reference_pending <= 0;
                    if (reference_byte) begin
                        clock_word[7:0] <= reference_phase ? data_high[7:0] : data_low[7:0];
                        clock_done <= 1;
                    end else clock_word[15:8] <= reference_phase ? data_high[7:0] : data_low[7:0];
                end
            end
            // The receive history includes the final CA falling edge.
            if ((clock_event[0] && (edge_low == 9 || edge_low == 10)) ||
                (clock_event[1] && (edge_high == 9 || edge_high == 10))) begin
`ifdef APS6408_DIAG_SIM
                if ($test$plusargs("trace_rx")) $display("REF trigger t=%0t clock_event=%b edge_low=%d edge_high=%d speed=%d low=%h high=%h", $time, clock_event, edge_low, edge_high, active_speed, data_low, data_high);
`endif
                reference_pending <= 1;
                reference_delay <= active_speed == 0 ? 2 : 0;
                reference_phase <= clock_event[1];
                reference_byte <= clock_event[1] ? edge_high == 10 : edge_low == 10;
            end
            if (!done) begin
                if (byte_count == 1 && second_delay != 0) second_delay <= second_delay - 1'b1;
                if (active_speed != 0 && byte_count != 0 && (|fall_event) && edge_word[7:0] == 0)
                    edge_word[7:0] <= {1'b0, fall_event[1] ? edge_high : edge_low};
                if (first_capture || second_capture) begin
                    if (byte_count == 0) begin
                        early_word[15:8] <= capture_data[31:24];
                        mid_word[15:8] <= capture_data[23:16];
                        center_word[15:8] <= capture_data[15:8];
                        late_word[15:8] <= capture_data[7:0];
                        edge_word[15:8] <= {1'b0, capture_phase ? edge_high : edge_low};
                        second_phase <= capture_phase;
                        second_delay <= nominal_second_delay;
                        // Adjacent DDIO phases are separated by one 3.69 ns sample.
                        if (active_d1_mode == 1) begin
                            second_phase <= !capture_phase;
                            second_delay <= nominal_second_delay - !capture_phase;
                        end else if (active_d1_mode == 2) begin
                            second_phase <= !capture_phase;
                            second_delay <= nominal_second_delay + capture_phase;
                        end
                    end else begin
                        early_word[7:0] <= capture_data[31:24];
                        mid_word[7:0] <= capture_data[23:16];
                        center_word[7:0] <= capture_data[15:8];
                        late_word[7:0] <= capture_data[7:0];
                        if (!fixed_second) edge_word[7:0] <= {1'b0, capture_phase ? edge_high : edge_low};
                        done <= 1;
                    end
                    byte_count <= byte_count + 1'b1;
                end
            end
        end
    end
endmodule
