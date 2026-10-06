// Low-speed, standalone APS6408L-3OBM-BA DDR OPI board diagnostic.
// A separate receive clock oversamples the source-synchronous DQS input. This is a
// switchable bring-up diagnostic, not a Saturn RAMH backend.
module aps6408_diag_core #(
    parameter integer POWERUP_CYCLES = 135476, // 2 ms at 67.7376 MHz
    parameter integer RESET_RECOVERY_CYCLES = 136 // at least 2 us
) (
    input clk,
    input clk_phy,
    input reset,
    input [1:0] speed_select,
    output reg [1:0] result_code,
    output reg [7:0] stage_code,
    output reg [23:0] failure_address,
    output reg [15:0] id_word,
    output reg [15:0] expected_data,
    output reg [15:0] actual_data,
    output reg [15:0] sample_early,
    output reg [15:0] sample_mid,
    output reg [15:0] sample_center,
    output reg [15:0] sample_late,
    output reg [15:0] retry_read_data,
    output reg retry_read_valid,
    output reg [1:0] read_capture_tap,
    output reg [1:0] read_capture_tap_second,
    output reg [15:0] mr_pair0,
    output reg [15:0] mr_pair1,
    output reg [15:0] mr_pair2,
    output reg [15:0] dqs_edge_pair1,
    output reg [15:0] clk_pair1,
    output reg [7:0] diagnostic_leds,
    output activity,
    output reg PSRAM_CLK,
    output reg PSRAM_CE_N,
    inout [7:0] PSRAM_DQ,
    inout PSRAM_DQS
);
    localparam [3:0] S_POWER=0, S_START=1, S_CMD=2, S_LATENCY=3,
                     S_WRITE=4, S_READ=5, S_END=6, S_GAP=7,
                     S_ADVANCE=8, S_PASS=9, S_FAIL=10, S_TURN=11,
                     S_RESET_START=12, S_RESET_CMD=13,
                     S_RESET_END=14, S_RESET_WAIT=15;
    reg [3:0] state;
    reg did_global_reset = 1'b0;
    reg [17:0] power_count;
    reg [2:0] div_count;
    reg [7:0] gap_count;
    reg [6:0] timeout_edges;
    reg [4:0] edge_index;
    reg [3:0] data_index;
    reg [7:0] cell_index;
    reg [1:0] pattern_pass;
    reg id_phase;
    reg reference_phase;
    reg [15:0] reference_mr0, reference_mr1, clk_previous_pair;
    reg [1:0] reference_tap_first, reference_tap_second;
    reg [1:0] id_slot;
    reg read_phase;
    reg retry_slow;
    reg [7:0] dq_out;
    reg dq_oe;
    reg dm_oe;
    reg [15:0] read_word;
    reg [15:0] mr0_early;
    reg [15:0] mr0_mid;
    reg [15:0] mr0_center;
    reg [15:0] mr0_late;
    reg [15:0] dqs_edge_word;
    reg [7:0] tx_data;
    (* preserve, dont_merge *) reg psram_clock_monitor;
    reg tx_oe;
    reg tx_dm_oe;
    wire rx_done;
    wire [15:0] rx_early, rx_mid, rx_late, rx_edges;
    wire [15:0] rx_center;
    wire [15:0] rx_clock;
    wire rx_clock_done;
    reg rx_done_meta, rx_done_sync;
    reg rx_clock_done_meta, rx_clock_done_sync;
    reg [15:0] rx_early_hold, rx_mid_hold, rx_late_hold, rx_edges_hold;
    reg [15:0] rx_center_hold;
    reg [15:0] rx_clock_hold;
    reg [15:0] clk_read_word;

    assign PSRAM_DQ = dq_oe ? dq_out : 8'hzz;
    assign PSRAM_DQS = dm_oe ? 1'b0 : 1'bz; // DM=0 enables both write bytes
    assign activity = (state != S_PASS) && (state != S_FAIL);

    function valid_training_pair;
        input [15:0] first_pair;
        input [15:0] second_pair;
        begin
            valid_training_pair = (first_pair[7:0] == second_pair[15:8]) &&
                ((second_pair[15:8] & 8'h1F) == 8'h0D) &&
                ((second_pair[7:0] & 8'h1F) == 8'h13);
        end
    endfunction

    function [23:0] address_for;
        input [7:0] index;
        reg [7:0] spread;
        begin
            if (index == 0) address_for = 24'h000000;
            else if (index <= 22) address_for = 24'h000001 << index;
            else if (index == 23) address_for = 24'h3FFFFE;
            else if (index == 24) address_for = 24'h7FFFFE;
            else begin
                spread = index - 8'd25;
                address_for = {1'b0, spread, spread ^ 8'h5A,
                               spread[5:0] ^ 6'h15, 1'b0};
            end
        end
    endfunction

    function [15:0] pattern_for;
        input [7:0] index;
        input [1:0] pass;
        begin
            case (pass)
                0: pattern_for = {8'h00, index};
                1: pattern_for = {8'hFF, ~index};
                2: pattern_for = 16'hA55A ^ {index, index};
                default: pattern_for = 16'h5AA5 ^ {index, ~index};
            endcase
        end
    endfunction

    wire [23:0] address = id_phase ? {22'd0,id_slot} : address_for(cell_index);
    wire [15:0] pattern = pattern_for(cell_index, pattern_pass);
    wire [1:0] active_speed = id_phase && reference_phase ? 2'd0 : retry_slow ? 2'd1 : speed_select;
    wire [2:0] half_period = active_speed == 0 ? 3'd4 : active_speed == 1 ? 3'd2 : 3'd1;
    wire tick = (div_count == half_period-1'b1);
    wire rx_arm = (state == S_TURN || state == S_READ);
    function [15:0] tap_word;
        input [1:0] tap;
        input [15:0] early_value, mid_value, late_value, center_value;
        begin
            case (tap)
                0: tap_word = early_value;
                1: tap_word = mid_value;
                2: tap_word = late_value;
                default: tap_word = center_value;
            endcase
        end
    endfunction
    function [1:0] first_tap_order;
        input [1:0] index;
        begin
            case (index)
                0: first_tap_order = 1;
                1: first_tap_order = 2;
                2: first_tap_order = 3;
                default: first_tap_order = 0;
            endcase
        end
    endfunction
    function [1:0] second_tap_order;
        input [1:0] index;
        begin
            case (index)
                0: second_tap_order = 2;
                1: second_tap_order = 3;
                2: second_tap_order = 1;
                default: second_tap_order = 0;
            endcase
        end
    endfunction
    wire [15:0] valid_tap_pairs;
    genvar first_index, second_index;
    generate for (first_index=0; first_index<4; first_index=first_index+1) begin : first_training
        for (second_index=0; second_index<4; second_index=second_index+1) begin : second_training
            wire [1:0] first_tap = first_tap_order(first_index);
            wire [1:0] second_tap = second_tap_order(second_index);
            wire [15:0] previous_first = tap_word(first_tap, mr0_early, mr0_mid, mr0_late, mr0_center);
            wire [15:0] previous_second = tap_word(second_tap, mr0_early, mr0_mid, mr0_late, mr0_center);
            wire [15:0] current_first = tap_word(first_tap, sample_early, sample_mid, sample_late, sample_center);
            wire [15:0] current_second = tap_word(second_tap, sample_early, sample_mid, sample_late, sample_center);
            wire [15:0] previous_pair = {previous_first[15:8], previous_second[7:0]};
            wire [15:0] current_pair = {current_first[15:8], current_second[7:0]};
            assign valid_tap_pairs[first_index*4+second_index] =
                valid_training_pair(previous_pair, current_pair) &&
                (reference_phase ? previous_pair == clk_previous_pair && current_pair == clk_read_word :
                                   previous_pair == reference_mr0 && current_pair == reference_mr1);
        end
    end endgenerate
    reg [3:0] trained_pair;
    integer pair_index;
    always @* begin
        trained_pair = 0;
        for (pair_index=15; pair_index>=0; pair_index=pair_index-1)
            if (valid_tap_pairs[pair_index]) trained_pair = pair_index;
    end
    wire training_valid = |valid_tap_pairs;
    wire [1:0] trained_tap = first_tap_order(trained_pair[3:2]);
    wire [1:0] trained_tap_second = second_tap_order(trained_pair[1:0]);
    wire [15:0] trained_previous_hi = tap_word(trained_tap, mr0_early, mr0_mid, mr0_late, mr0_center);
    wire [15:0] trained_previous_lo = tap_word(trained_tap_second, mr0_early, mr0_mid, mr0_late, mr0_center);
    wire [15:0] trained_current_hi = tap_word(trained_tap, sample_early, sample_mid, sample_late, sample_center);
    wire [15:0] trained_current_lo = tap_word(trained_tap_second, sample_early, sample_mid, sample_late, sample_center);
    wire [15:0] trained_first = {trained_previous_hi[15:8], trained_previous_lo[7:0]};
    wire [15:0] trained_second = {trained_current_hi[15:8], trained_current_lo[7:0]};
    wire [15:0] receive_hi = tap_word(retry_slow ? reference_tap_first : read_capture_tap, rx_early_hold, rx_mid_hold, rx_late_hold, rx_center_hold);
    wire [15:0] receive_lo = tap_word(retry_slow ? reference_tap_second : read_capture_tap_second, rx_early_hold, rx_mid_hold, rx_late_hold, rx_center_hold);

    aps6408_diag_rx rx (
        .clk(clk_phy), .reset(reset), .arm(rx_arm), .speed(active_speed),
        .psram_clk(psram_clock_monitor), .dq(PSRAM_DQ), .dqs(PSRAM_DQS),
        .done(rx_done), .early_word(rx_early), .mid_word(rx_mid),
        .late_word(rx_late), .center_word(rx_center), .edge_word(rx_edges), .clock_word(rx_clock),
        .clock_done(rx_clock_done)
    );

    always @(negedge clk) begin
        dq_out <= tx_data;
        dq_oe <= tx_oe && state != S_TURN;
        dm_oe <= tx_dm_oe;
    end

    always @(posedge clk) begin
        rx_done_meta <= rx_done;
        rx_done_sync <= rx_done_meta;
        rx_clock_done_meta <= rx_clock_done;
        rx_clock_done_sync <= rx_clock_done_meta;
        rx_early_hold <= rx_early;
        rx_mid_hold <= rx_mid;
        rx_center_hold <= rx_center;
        rx_late_hold <= rx_late;
        rx_edges_hold <= rx_edges;
        rx_clock_hold <= rx_clock;
        if (reset) begin
            state <= S_POWER;
            rx_done_meta <= 0;
            rx_done_sync <= 0;
            rx_clock_done_meta <= 0;
            rx_clock_done_sync <= 0;
            power_count <= 0;
            div_count <= 0;
            gap_count <= 0;
            timeout_edges <= 0;
            edge_index <= 0;
            data_index <= 0;
            cell_index <= 0;
            pattern_pass <= 0;
            id_phase <= 1;
            reference_phase <= 1;
            reference_mr0 <= 0;
            reference_mr1 <= 0;
            reference_tap_first <= 1;
            reference_tap_second <= 2;
            clk_previous_pair <= 0;
            id_slot <= 0;
            read_phase <= 0;
            retry_slow <= 0;
            tx_data <= 0;
            tx_oe <= 0;
            tx_dm_oe <= 0;
            PSRAM_CLK <= 0;
            psram_clock_monitor <= 0;
            PSRAM_CE_N <= 1;
            read_word <= 0;
            mr0_early <= 0;
            mr0_mid <= 0;
            mr0_center <= 0;
            mr0_late <= 0;
            read_capture_tap <= 2'd1;
            read_capture_tap_second <= 2'd2;
            dqs_edge_word <= 0;
            clk_read_word <= 0;
            result_code <= 0;
            stage_code <= 8'h01;
            failure_address <= 0;
            id_word <= 0;
            expected_data <= 0;
            actual_data <= 0;
            sample_early <= 0;
            sample_mid <= 0;
            sample_center <= 0;
            sample_late <= 0;
            retry_read_data <= 0;
            retry_read_valid <= 0;
            mr_pair0 <= 0;
            mr_pair1 <= 0;
            mr_pair2 <= 0;
            dqs_edge_pair1 <= 0;
            clk_pair1 <= 0;
            diagnostic_leds <= 0;
        end else begin
            if (tick) div_count <= 0;
            else div_count <= div_count + 1'b1;

            case (state)
                S_POWER: begin
                    PSRAM_CE_N <= 1;
                    PSRAM_CLK <= 0;
                    psram_clock_monitor <= 0;
                    if (power_count == POWERUP_CYCLES-1)
                        state <= did_global_reset ? S_START : S_RESET_START;
                    else power_count <= power_count + 1'b1;
                end

                S_RESET_START: begin
                    PSRAM_CE_N <= 0;
                    PSRAM_CLK <= 0;
                    psram_clock_monitor <= 0;
                    tx_oe <= 1;
                    tx_data <= 8'hFF;
                    tx_dm_oe <= 0;
                    div_count <= 0;
                    edge_index <= 0;
                    stage_code <= 8'h02;
                    state <= S_RESET_CMD;
                end

                S_RESET_CMD: if (tick) begin
                    PSRAM_CLK <= ~PSRAM_CLK;
                    psram_clock_monitor <= ~PSRAM_CLK;
                    edge_index <= edge_index + 1'b1;
                    if (edge_index == 1) tx_oe <= 0;
                    if (edge_index == 7) state <= S_RESET_END;
                end

                S_RESET_END: if (tick) begin
                    PSRAM_CE_N <= 1;
                    PSRAM_CLK <= 0;
                    psram_clock_monitor <= 0;
                    did_global_reset <= 1;
                    power_count <= 0;
                    state <= S_RESET_WAIT;
                end

                S_RESET_WAIT: begin
                    if (power_count == RESET_RECOVERY_CYCLES-1)
                        state <= S_START;
                    else power_count <= power_count + 1'b1;
                end

                S_START: begin
                    PSRAM_CE_N <= 0;
                    PSRAM_CLK <= 0;
                    psram_clock_monitor <= 0;
                    tx_oe <= 1;
                    tx_data <= id_phase ? 8'h40 : (read_phase ? 8'h20 : 8'hA0);
                    tx_dm_oe <= 0;
                    div_count <= 0;
                    edge_index <= 0;
                    data_index <= 0;
                    timeout_edges <= 0;
                    dqs_edge_word <= 0;
                    clk_read_word <= 0;
                    read_word <= 0;
                    if (!retry_slow) begin
                        sample_early <= 0;
                        sample_mid <= 0;
                        sample_center <= 0;
                        sample_late <= 0;
                        retry_read_valid <= 0;
                    end
                    stage_code <= id_phase ? 8'h08 : (read_phase ? 8'h20 : 8'h10);
                    state <= S_CMD;
                end

                S_CMD: if (tick) begin
                    PSRAM_CLK <= ~PSRAM_CLK;
                    psram_clock_monitor <= ~PSRAM_CLK;
                    edge_index <= edge_index + 1'b1;
                    case (edge_index)
                        1: tx_data <= 8'h00;
                        2: tx_data <= address[23:16];
                        3: tx_data <= address[15:8];
                        4: tx_data <= address[7:0];
                    endcase
                    if (edge_index == 5) begin
                        state <= S_TURN;
                        edge_index <= 0;
                    end
                end

                // Preserve address hold time after the final falling edge.
                S_TURN: begin
                    tx_oe <= 0;
                    state <= (id_phase || read_phase) ? S_READ : S_LATENCY;
                end

                S_LATENCY: if (tick) begin
                    PSRAM_CLK <= ~PSRAM_CLK;
                    psram_clock_monitor <= ~PSRAM_CLK;
                    edge_index <= edge_index + 1'b1;
                    // LC=5 includes the final address cycle. Four more
                    // full clocks (eight DDR edges) precede the first data.
                    if (edge_index == 7) begin
                        state <= S_WRITE;
                        data_index <= 0;
                        tx_oe <= 1;
                        tx_dm_oe <= 1;
                        tx_data <= pattern[15:8];
                    end
                end

                S_WRITE: if (tick) begin
                    PSRAM_CLK <= ~PSRAM_CLK;
                    psram_clock_monitor <= ~PSRAM_CLK;
                    if (data_index == 0) begin
                        data_index <= 1;
                        tx_data <= pattern[7:0];
                    end else begin
                        state <= S_END;
                    end
                end

                S_READ: begin
                    if (tick) begin
                        PSRAM_CLK <= ~PSRAM_CLK;
                        psram_clock_monitor <= ~PSRAM_CLK;
                        timeout_edges <= timeout_edges + 1'b1;
                        // Bound a missing-DQS transaction. Register reads use
                        // fixed LC=5; memory reads may incur refresh pushout.
                        if (timeout_edges == (id_phase ? 7'd17 : 7'd50)) begin
                            stage_code <= 8'hE1; // no two DQS data edges
                            failure_address <= address;
                            dqs_edge_pair1 <= dqs_edge_word;
                            mr_pair1 <= read_word;
                            clk_pair1 <= rx_clock_hold;
                            state <= S_FAIL;
                        end
                    end
                    if (rx_done_sync && (!id_phase || rx_clock_done_sync)) begin
                        read_word <= {receive_hi[15:8], receive_lo[7:0]};
                        dqs_edge_word <= rx_edges_hold;
                        clk_read_word <= rx_clock_hold;
                        if (!retry_slow) begin
                            sample_early <= rx_early_hold;
                            sample_mid <= rx_mid_hold;
                            sample_center <= rx_center_hold;
                            sample_late <= rx_late_hold;
                        end
                        state <= S_END;
                    end
                end

                S_END: if (tick) begin
                    PSRAM_CE_N <= 1;
                    PSRAM_CLK <= 0;
                    psram_clock_monitor <= 0;
                    tx_oe <= 0;
                    tx_dm_oe <= 0;
                    gap_count <= 0;
                    state <= S_GAP;
                end

                S_GAP: if (tick) begin
                    gap_count <= gap_count + 1'b1;
                    if (gap_count == 8'd31) state <= S_ADVANCE;
                end

                S_ADVANCE: begin
                    if (retry_slow) begin
                        retry_read_data <= read_word;
                        retry_read_valid <= 1;
                        retry_slow <= 0;
                        stage_code <= 8'hE2;
                        state <= S_FAIL;
                    end else if (id_phase) begin
                        if (id_slot == 0) begin
                            mr_pair0 <= read_word;
                            mr0_early <= sample_early;
                            mr0_mid <= sample_mid;
                            mr0_center <= sample_center;
                            clk_previous_pair <= clk_read_word;
                            mr0_late <= sample_late;
                            id_slot <= 1;
                            state <= S_START;
                        end else if (id_slot == 1) begin
                            mr_pair1 <= read_word;
                            id_word <= read_word;
                            dqs_edge_pair1 <= dqs_edge_word;
                            clk_pair1 <= clk_read_word;
                            // MR1[4:0] is APM vendor 0Dh; MR2[4:0]
                            // identifies generation 3 and 64 Mbit density.
                            // The CLK-domain reference capture is checked
                            // only for 8.47 MHz. At faster settings, DQS is
                            // the read timing reference; the memory tests
                            // still check every returned data word.
                            if (training_valid) begin
                                read_capture_tap <= trained_tap;
                                read_capture_tap_second <= trained_tap_second;
                                mr_pair0 <= trained_first;
                                mr_pair1 <= trained_second;
                                id_word <= trained_second;
                                if (reference_phase) begin
                                    reference_mr0 <= clk_previous_pair;
                                    reference_mr1 <= clk_read_word;
                                    reference_tap_first <= trained_tap;
                                    reference_tap_second <= trained_tap_second;
                                    reference_phase <= 0;
                                end
                                if (reference_phase && speed_select != 0) id_slot <= 0;
                                else id_phase <= 0;
                                state <= S_START;
                            end else begin
                                stage_code <= 8'hE6;
                                failure_address <= 24'h000001;
                                expected_data <= 16'h0D13;
                                actual_data <= read_word;
                                state <= S_FAIL;
                            end
                        end else begin
                            state <= S_FAIL;
                        end
                    end else if (read_phase && read_word != pattern) begin
                        stage_code <= 8'hE2;
                        failure_address <= address;
                        expected_data <= pattern;
                        actual_data <= read_word;
                        dqs_edge_pair1 <= dqs_edge_word;
                        if (speed_select == 2'd2) begin
                            retry_slow <= 1;
                            state <= S_START;
                        end else state <= S_FAIL;
                    end else if (cell_index == 8'hFF) begin
                        if (read_phase) begin
                            if (pattern_pass == 2'd3) state <= S_PASS;
                            else begin
                                pattern_pass <= pattern_pass + 1'b1;
                                read_phase <= 0;
                                cell_index <= 0;
                                state <= S_START;
                            end
                        end else begin
                            read_phase <= 1;
                            cell_index <= 0;
                            state <= S_START;
                        end
                    end else begin
                        cell_index <= cell_index + 1'b1;
                        state <= S_START;
                    end
                end

                S_PASS: begin
                    result_code <= 1;
                    stage_code <= 8'hFF;
                    diagnostic_leds <= 8'h40;
                end
                S_FAIL: begin
                    result_code <= 2;
                    diagnostic_leds <= 8'h80;
                    PSRAM_CE_N <= 1;
                    PSRAM_CLK <= 0;
                    psram_clock_monitor <= 0;
                    tx_oe <= 0;
                    tx_dm_oe <= 0;
                end
                default: state <= S_FAIL;
            endcase
        end
    end
endmodule
