// Low-speed, standalone APS6408L-3OBM-BA DDR OPI board diagnostic.
// A separate receive clock oversamples the source-synchronous DQS input. This is a
// switchable bring-up diagnostic, not a Saturn RAMH backend.
module aps6408_diag_core #(
    parameter integer POWERUP_CYCLES = 135476, // 2 ms at 67.7376 MHz
    parameter integer RESET_RECOVERY_CYCLES = 136, // at least 2 us
    parameter integer RUNTIME_API = 0,
    parameter integer MEMORY_TRAINING_ENABLE = 0
) (
    input clk,
    input clk_phy,
    input reset,
    input [1:0] speed_select,
    input [1:0] test_mode,
    input [1:0] d1_mode,
    input drive_half,
    input control_fast,
    input request_valid,
    input request_write,
    input [23:0] request_address,
    input [15:0] request_write_data,
    input [1:0] request_write_mask,
    output request_ready,
    output reg request_done,
    output reg request_error,
    output reg [15:0] request_read_data,
    output reg init_done,
    output reg init_error,
    output reg [1:0] result_code,
    output reg [7:0] stage_code,
    output reg [23:0] failure_address,
    output reg [15:0] id_word,
    output reg [15:0] expected_data,
    output reg [15:0] actual_data,
    output [15:0] sample_early,
    output [15:0] sample_mid,
    output [15:0] sample_center,
    output [15:0] sample_late,
    output reg [15:0] retry_read_data,
    output reg retry_read_valid,
    output reg [1:0] read_capture_tap,
    output reg [1:0] read_capture_tap_second,
    output reg [15:0] mr_pair0,
    output reg [15:0] mr_pair1,
    output reg [15:0] mr_pair2,
    output reg [15:0] dqs_edge_pair1,
    output reg [15:0] clk_pair1,
    output reg [15:0] reference_mr0,
    output reg [15:0] reference_mr1,
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
    reg [5:0] wait_count;
    reg [2:0] edge_index;
    reg [3:0] data_index;
    reg [7:0] cell_index;
    reg [1:0] pattern_pass;
    reg id_phase;
    reg memory_training = 0;
    reg reference_phase;
    reg drive_config_pending;
    reg drive_config_phase;
    reg drive_verify;
    reg [7:0] drive_target;
    reg [15:0] clk_previous_pair;
    reg [1:0] reference_tap_first, reference_tap_second;
    reg [1:0] id_slot;
    reg read_phase;
    reg retry_slow;
    reg [7:0] dq_out;
    reg dq_oe;
    reg dm_oe;
    reg dm_out;
    reg tx_dm_data;
    reg [23:0] runtime_address;
    reg [15:0] runtime_data;
    reg [1:0] runtime_mask;
    reg runtime_pending;
    reg [15:0] read_word;
    reg [15:0] mr0_early;
    reg [15:0] mr0_mid;
    reg [15:0] mr0_center;
    reg [15:0] mr0_late;
    reg [15:0] dqs_edge_word;
    reg [7:0] tx_data;
    (* preserve, dont_merge *) reg psram_clock_monitor;
    (* preserve, dont_merge *) reg tx_oe;
    reg tx_dm_oe;
    wire rx_done;
    wire [15:0] rx_early, rx_mid, rx_late, rx_edges;
    wire [15:0] rx_center;
    wire [15:0] rx_clock;
    wire rx_clock_done;
    (* preserve, altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *) reg rx_done_meta, rx_done_sync;
    (* preserve, altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *) reg rx_clock_done_meta, rx_clock_done_sync;
    (* preserve, dont_merge *) reg [1:0] rx_speed_hold;
    (* preserve, dont_merge *) reg [15:0] rx_early_hold, rx_mid_hold, rx_late_hold;
    reg [15:0] rx_edges_hold;
    (* preserve, dont_merge *) reg [15:0] rx_center_hold;
    (* preserve, dont_merge *) reg [15:0] rx_clock_hold;
    reg [15:0] clk_read_word;
    reg [15:0] diagnostic_sample_early, diagnostic_sample_mid;
    reg [15:0] diagnostic_sample_center, diagnostic_sample_late;

    assign sample_early = RUNTIME_API != 0 ? rx_early_hold : diagnostic_sample_early;
    assign sample_mid = RUNTIME_API != 0 ? rx_mid_hold : diagnostic_sample_mid;
    assign sample_center = RUNTIME_API != 0 ? rx_center_hold : diagnostic_sample_center;
    assign sample_late = RUNTIME_API != 0 ? rx_late_hold : diagnostic_sample_late;

    assign PSRAM_DQ = dq_oe ? dq_out : 8'hzz;
    assign PSRAM_DQS = dm_oe ? dm_out : 1'bz;
    assign request_ready = RUNTIME_API != 0 && init_done && !init_error && state == S_PASS;
    assign activity = (state != S_PASS) && (state != S_FAIL);

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

    wire [23:0] address = drive_config_phase ? 24'd0 : id_phase ? {22'd0,id_slot} :
                          memory_training ? {21'h020000,id_slot,1'b0} :
                          RUNTIME_API != 0 ? runtime_address : address_for(cell_index);
    wire [15:0] memory_pattern = (id_slot[1] ? 16'h5AA5 : 16'hA55A) ^
                                (id_slot[0] ? 16'h99CC : 16'h0000);
    wire [15:0] pattern = memory_training ? memory_pattern :
                          RUNTIME_API != 0 ? runtime_data : pattern_for(cell_index, pattern_pass);
    wire [1:0] write_speed = test_mode == 1 ? 2'd0 : speed_select;
    wire [1:0] read_speed = test_mode == 2 ? 2'd0 : speed_select;
    wire [1:0] active_speed = drive_config_phase || retry_slow || (id_phase && reference_phase) ? 2'd0 :
                              id_phase || read_phase ? read_speed : write_speed;
    wire use_reference_taps = retry_slow || (!id_phase && read_phase && read_speed == 0);
    wire fast_control = RUNTIME_API != 0 && control_fast;
    wire [2:0] half_period = active_speed == 0 ? (fast_control ? 3'd6 : 3'd4) :
                             active_speed == 1 ? (fast_control ? 3'd3 : 3'd2) : 3'd1;
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
        input fast_mode;
        begin
            case (index)
                0: second_tap_order = fast_mode ? 3 : 2;
                1: second_tap_order = fast_mode ? 1 : 3;
                2: second_tap_order = fast_mode ? 2 : 1;
                default: second_tap_order = 0;
            endcase
        end
    endfunction
    wire [15:0] training_previous = memory_training ? 16'hA55A : reference_phase ? clk_previous_pair : reference_mr0;
    wire [15:0] training_current = memory_training ? 16'h5AA5 : reference_phase ? clk_read_word : reference_mr1;
    wire [3:0] valid_first_taps, valid_second_taps;
    genvar tap_index;
    generate for (tap_index=0; tap_index<4; tap_index=tap_index+1) begin : training
        wire [1:0] first_tap = first_tap_order(tap_index);
        wire [1:0] second_tap = second_tap_order(tap_index, fast_control);
        wire [15:0] previous_first = tap_word(first_tap, mr0_early, mr0_mid, mr0_late, mr0_center);
        wire [15:0] previous_second = tap_word(second_tap, mr0_early, mr0_mid, mr0_late, mr0_center);
        wire [15:0] current_first = tap_word(first_tap, sample_early, sample_mid, sample_late, sample_center);
        wire [15:0] current_second = tap_word(second_tap, sample_early, sample_mid, sample_late, sample_center);
        assign valid_first_taps[tap_index] =
            previous_first[15:8] == training_previous[15:8] &&
            current_first[15:8] == training_current[15:8] &&
            (memory_training || (current_first[15:8] & 8'h1F) == 8'h0D);
        assign valid_second_taps[tap_index] =
            previous_second[7:0] == training_previous[7:0] &&
            current_second[7:0] == training_current[7:0] &&
            (memory_training || (current_second[7:0] & 8'h1F) == 8'h13);
    end endgenerate
    wire training_valid = (training_previous[7:0] == training_current[15:8]) &&
                          (|valid_first_taps) && (|valid_second_taps);
    reg [3:0] trained_pair;
    integer pair_index;
    always @* begin
        trained_pair = 0;
        if (training_valid) begin
            for (pair_index=3; pair_index>=0; pair_index=pair_index-1) begin
                if (valid_first_taps[pair_index]) trained_pair[3:2] = pair_index;
                if (valid_second_taps[pair_index]) trained_pair[1:0] = pair_index;
            end
            if (memory_training && !fast_control) begin
                if (valid_first_taps[2]) trained_pair[3:2] = 2;
                if (valid_second_taps[1]) trained_pair[1:0] = 1;
                else if (valid_second_taps[2]) trained_pair[1:0] = 2;
            end
        end
    end
    wire [1:0] trained_tap = first_tap_order(trained_pair[3:2]);
    wire [1:0] trained_tap_second = second_tap_order(trained_pair[1:0], fast_control);
    wire [15:0] trained_previous_hi = tap_word(trained_tap, mr0_early, mr0_mid, mr0_late, mr0_center);
    wire [15:0] trained_previous_lo = tap_word(trained_tap_second, mr0_early, mr0_mid, mr0_late, mr0_center);
    wire [15:0] trained_current_hi = tap_word(trained_tap, sample_early, sample_mid, sample_late, sample_center);
    wire [15:0] trained_current_lo = tap_word(trained_tap_second, sample_early, sample_mid, sample_late, sample_center);
    wire [15:0] trained_first = {trained_previous_hi[15:8], trained_previous_lo[7:0]};
    wire [15:0] trained_second = {trained_current_hi[15:8], trained_current_lo[7:0]};
    wire [15:0] receive_hi = tap_word(use_reference_taps ? reference_tap_first : read_capture_tap, rx_early_hold, rx_mid_hold, rx_late_hold, rx_center_hold);
    wire [15:0] receive_lo = tap_word(use_reference_taps ? reference_tap_second : read_capture_tap_second, rx_early_hold, rx_mid_hold, rx_late_hold, rx_center_hold);

    aps6408_diag_rx rx (
        .clk(clk_phy), .reset(reset), .arm(rx_arm), .speed(rx_speed_hold),
        .d1_mode(d1_mode),
        .psram_clk(psram_clock_monitor), .dq(PSRAM_DQ), .dqs(PSRAM_DQS),
        .done(rx_done), .early_word(rx_early), .mid_word(rx_mid),
        .late_word(rx_late), .center_word(rx_center), .edge_word(rx_edges), .clock_word(rx_clock),
        .clock_done(rx_clock_done)
    );

    always @(negedge clk) begin
        dq_out <= tx_data;
        dq_oe <= tx_oe;
        dm_oe <= tx_dm_oe;
        dm_out <= tx_dm_data;
    end

    always @(posedge clk) begin
        request_done <= 0;
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
            wait_count <= 0;
            edge_index <= 0;
            data_index <= 0;
            cell_index <= 0;
            pattern_pass <= 0;
            id_phase <= 1;
            memory_training <= 0;
            reference_phase <= 1;
            drive_config_pending <= 1;
            drive_config_phase <= 0;
            drive_verify <= 0;
            drive_target <= 0;
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
            rx_speed_hold <= 0;
            tx_dm_oe <= 0;
            tx_dm_data <= 0;
            runtime_address <= 0;
            runtime_data <= 0;
            runtime_mask <= 0;
            runtime_pending <= 0;
            request_done <= 0;
            request_error <= 0;
            request_read_data <= 0;
            init_done <= 0;
            init_error <= 0;
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
            diagnostic_sample_early <= 0;
            diagnostic_sample_mid <= 0;
            diagnostic_sample_center <= 0;
            diagnostic_sample_late <= 0;
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
                    rx_speed_hold <= active_speed;
                    PSRAM_CE_N <= 0;
                    PSRAM_CLK <= 0;
                    psram_clock_monitor <= 0;
                    tx_oe <= 1;
                    tx_data <= drive_config_phase ? 8'hC0 : id_phase ? 8'h40 : (read_phase ? 8'h20 : 8'hA0);
                    tx_dm_oe <= 0;
                    div_count <= 0;
                    edge_index <= 0;
                    data_index <= 0;
                    wait_count <= 0;
                    dqs_edge_word <= 0;
                    clk_read_word <= 0;
                    read_word <= 0;
                    if (!retry_slow) begin
                        diagnostic_sample_early <= 0;
                        diagnostic_sample_mid <= 0;
                        diagnostic_sample_center <= 0;
                        diagnostic_sample_late <= 0;
                        retry_read_valid <= 0;
                    end
                    stage_code <= drive_config_phase ? 8'h03 : id_phase ? 8'h08 : (read_phase ? 8'h20 : 8'h10);
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
                        if (drive_config_phase) begin
                            // MR writes capture one byte at the next rising edge (LC=1).
                            tx_data <= drive_target;
                            state <= S_WRITE;
                        end else begin
                            tx_oe <= 0;
                            state <= S_TURN;
                        end
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
                        tx_dm_data <= RUNTIME_API != 0 && !memory_training && !runtime_mask[1];
                        tx_data <= pattern[15:8];
                    end
                end

                S_WRITE: if (tick) begin
                    PSRAM_CLK <= ~PSRAM_CLK;
                    psram_clock_monitor <= ~PSRAM_CLK;
                    if (data_index == 0) begin
                        data_index <= 1;
                        if (!drive_config_phase) begin
                            tx_data <= pattern[7:0];
                            tx_dm_data <= RUNTIME_API != 0 && !memory_training && !runtime_mask[0];
                        end
                    end else begin
                        state <= S_END;
                    end
                end

                S_READ: begin
                    if (tick) begin
                        PSRAM_CLK <= ~PSRAM_CLK;
                        psram_clock_monitor <= ~PSRAM_CLK;
                        wait_count <= wait_count + 1'b1;
                        // Bound a missing-DQS transaction. Register reads use
                        // fixed LC=5; memory reads may incur refresh pushout.
                        if (wait_count == (id_phase ? 6'd17 : 6'd50)) begin
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
                            diagnostic_sample_early <= rx_early_hold;
                            diagnostic_sample_mid <= rx_mid_hold;
                            diagnostic_sample_center <= rx_center_hold;
                            diagnostic_sample_late <= rx_late_hold;
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
                    wait_count <= 0;
                    state <= S_GAP;
                end

                S_GAP: if (tick) begin
                    wait_count <= wait_count + 1'b1;
                    if (wait_count == (RUNTIME_API != 0 && !id_phase && !drive_config_phase ? 6'd3 : 6'd31)) state <= S_ADVANCE;
                end

                S_ADVANCE: begin
                    if (drive_config_phase) begin
                        drive_config_phase <= 0;
                        state <= S_START;
                    end else if (retry_slow) begin
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
                                if (reference_phase && drive_config_pending) begin
                                    drive_target <= (clk_previous_pair[15:8] & 8'h3C) | (drive_half ? 8'h00 : 8'h01);
                                    drive_config_pending <= 0;
                                    drive_config_phase <= 1;
                                    drive_verify <= 1;
                                    id_slot <= 0;
                                    state <= S_START;
                                end else if (reference_phase && drive_verify && trained_first[15:8] != drive_target) begin
                                    expected_data <= {drive_target, trained_first[7:0]};
                                    actual_data <= trained_first;
                                    stage_code <= 8'hE7;
                                    state <= S_FAIL;
                                end else begin
                                    if (reference_phase) begin
                                        reference_mr0 <= clk_previous_pair;
                                        reference_mr1 <= clk_read_word;
                                        reference_tap_first <= trained_tap;
                                        reference_tap_second <= trained_tap_second;
                                        reference_phase <= 0;
                                        drive_verify <= 0;
                                    end
                                    if (reference_phase && read_speed != 0) id_slot <= 0;
                                    else id_phase <= 0;
                                    if (RUNTIME_API != 0 && !(reference_phase && read_speed != 0)) begin
                                        if (MEMORY_TRAINING_ENABLE != 0) begin
                                            memory_training <= 1;
                                            id_slot <= 0;
                                            read_phase <= 0;
                                            state <= S_START;
                                        end else begin
                                            init_done <= 1;
                                            state <= S_PASS;
                                        end
                                    end else state <= S_START;
                                end
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
                    end else if (memory_training) begin
                        if (!read_phase) begin
                            if (id_slot == 3) begin
                                id_slot <= 0;
                                read_phase <= 1;
                            end else id_slot <= id_slot + 1'b1;
                            state <= S_START;
                        end else if (id_slot == 0) begin
                            mr0_early <= sample_early;
                            mr0_mid <= sample_mid;
                            mr0_center <= sample_center;
                            mr0_late <= sample_late;
                            id_slot <= 2;
                            state <= S_START;
                        end else if (training_valid) begin
                            read_capture_tap <= trained_tap;
                            read_capture_tap_second <= trained_tap_second;
                            if (read_speed == 0) begin
                                reference_tap_first <= trained_tap;
                                reference_tap_second <= trained_tap_second;
                            end
                            memory_training <= 0;
                            init_done <= 1;
                            stage_code <= 8'h09;
                            state <= S_PASS;
                        end else begin
                            stage_code <= 8'hE9;
                            state <= S_FAIL;
                        end
                    end else if (RUNTIME_API != 0) begin
                        request_read_data <= read_word;
                        request_done <= 1;
                        runtime_pending <= 0;
                        state <= S_PASS;
                    end else if (read_phase && read_word != pattern) begin
                        stage_code <= 8'hE2;
                        failure_address <= address;
                        expected_data <= pattern;
                        actual_data <= read_word;
                        dqs_edge_pair1 <= dqs_edge_word;
                        if (read_speed != 0) begin
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
                    if (RUNTIME_API != 0) begin
                        if (request_valid && request_ready) begin
                            runtime_address <= request_address;
                            runtime_data <= request_write_data;
                            runtime_mask <= request_write_mask;
                            read_phase <= !request_write;
                            request_error <= 0;
                            runtime_pending <= 1;
                            if (request_address[0] || request_address[23] ||
                                (request_write && request_write_mask == 0)) begin
                                stage_code <= 8'hE8;
                                state <= S_FAIL;
                            end else state <= S_START;
                        end
                    end else begin
                        result_code <= 1;
                        stage_code <= 8'hFF;
                        diagnostic_leds <= 8'h40;
                    end
                end
                S_FAIL: begin
                    if (RUNTIME_API != 0) begin
                        if (!init_done) init_error <= 1;
                        if (runtime_pending) begin
                            request_done <= 1;
                            request_error <= 1;
                            runtime_pending <= 0;
                        end
                    end
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
