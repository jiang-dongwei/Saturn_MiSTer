// Low-speed, standalone APS6408L-3OBM-BA DDR OPI board diagnostic.
// The FPGA clock oversamples the source-synchronous DQS input. This is a
// switchable bring-up diagnostic, not a Saturn RAMH backend.
module aps6408_diag_core #(
    parameter integer POWERUP_CYCLES = 270952, // 2 ms at 135.475 MHz
    parameter integer RESET_RECOVERY_CYCLES = 271 // at least 2 us
) (
    input clk,
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
    output reg [15:0] sample_late,
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
    reg [18:0] power_count;
    reg [7:0] div_count;
    reg [7:0] gap_count;
    reg [6:0] timeout_edges;
    reg [4:0] edge_index;
    reg [3:0] data_index;
    reg [7:0] cell_index;
    reg [1:0] pattern_pass;
    reg id_phase;
    reg [1:0] id_slot;
    reg read_phase;
    reg [7:0] dq_out;
    reg dq_oe;
    reg dm_oe;
    reg [15:0] read_word;
    reg [1:0] dqs_pipe;
    reg dqs_prev;
    reg [2:0] sample_delay;
    reg sample_pending;
    reg [15:0] dqs_edge_word;
    reg [15:0] clk_read_word;
    reg [1:0] clk_sample_delay;
    reg clk_sample_pending;
    reg clk_sample_byte;

    assign PSRAM_DQ = dq_oe ? dq_out : 8'hzz;
    assign PSRAM_DQS = dm_oe ? 1'b0 : 1'bz; // DM=0 enables both write bytes
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

    wire [23:0] address = id_phase ? {22'd0,id_slot} : address_for(cell_index);
    wire [15:0] pattern = pattern_for(cell_index, pattern_pass);
    // 135.4752 MHz / (2 * half_period): 8.4672, 16.9344, 33.8688 MHz.
    wire [3:0] half_period = speed_select == 2'd0 ? 4'd8 :
                             speed_select == 2'd1 ? 4'd4 : 4'd2;
    wire tick = (div_count == half_period-1'b1);
    wire fast_sample = (speed_select != 2'd0);
    wire fastest_sample = (speed_select >= 2'd2);
    wire dqs_rise = fast_sample ? (dqs_pipe[0] && !dqs_pipe[1]) :
                                  (dqs_pipe[1] && !dqs_prev);
    wire dqs_fall = fast_sample ? (!dqs_pipe[0] && dqs_pipe[1]) :
                                  (!dqs_pipe[1] && dqs_prev);

    // The 33.87 MHz setting samples in the middle of the two-cycle data eye.
    // This fabric-clock sampler remains experimental until hardware tested.
    always @(posedge clk) begin
        dqs_pipe <= {dqs_pipe[0], PSRAM_DQS};
        dqs_prev <= dqs_pipe[1];

        if (reset) begin
            state <= S_POWER;
            power_count <= 0;
            div_count <= 0;
            gap_count <= 0;
            timeout_edges <= 0;
            edge_index <= 0;
            data_index <= 0;
            cell_index <= 0;
            pattern_pass <= 0;
            id_phase <= 1;
            id_slot <= 0;
            read_phase <= 0;
            dq_out <= 0;
            dq_oe <= 0;
            dm_oe <= 0;
            PSRAM_CLK <= 0;
            PSRAM_CE_N <= 1;
            read_word <= 0;
            sample_delay <= 0;
            sample_pending <= 0;
            dqs_edge_word <= 0;
            clk_read_word <= 0;
            clk_sample_delay <= 0;
            clk_sample_pending <= 0;
            clk_sample_byte <= 0;
            result_code <= 0;
            stage_code <= 8'h01;
            failure_address <= 0;
            id_word <= 0;
            expected_data <= 0;
            actual_data <= 0;
            sample_early <= 0;
            sample_mid <= 0;
            sample_late <= 0;
            mr_pair0 <= 0;
            mr_pair1 <= 0;
            mr_pair2 <= 0;
            dqs_edge_pair1 <= 0;
            clk_pair1 <= 0;
            diagnostic_leds <= 0;
        end else begin
            if (tick) div_count <= 0;
            else div_count <= div_count + 1'b1;

            if (sample_pending) begin
                if (sample_delay == 4) begin
                    if (data_index == 0) sample_early[15:8] <= PSRAM_DQ;
                    else sample_early[7:0] <= PSRAM_DQ;
                end
                if (!fastest_sample && sample_delay == (fast_sample ? 1 : 2)) begin
                    if (data_index == 0) begin
                        sample_mid[15:8] <= PSRAM_DQ;
                        if (!fast_sample) read_word[15:8] <= PSRAM_DQ;
                    end else begin
                        sample_mid[7:0] <= PSRAM_DQ;
                        if (!fast_sample) read_word[7:0] <= PSRAM_DQ;
                    end
                end
                if (sample_delay != 0) sample_delay <= sample_delay - 1'b1;
                else begin
                    sample_pending <= 0;
                    if (data_index == 0) begin
                        sample_late[15:8] <= PSRAM_DQ;
                        data_index <= 1;
                    end else begin
                        sample_late[7:0] <= PSRAM_DQ;
                        data_index <= 2;
                    end
                end
            end

            if (clk_sample_pending) begin
                if (clk_sample_delay != 0)
                    clk_sample_delay <= clk_sample_delay - 1'b1;
                else begin
                    if (clk_sample_byte) clk_read_word[7:0] <= PSRAM_DQ;
                    else clk_read_word[15:8] <= PSRAM_DQ;
                    clk_sample_pending <= 0;
                end
            end

            // Keep command/address and write data stable across each PSRAM
            // clock edge. Prepare the next byte one fabric cycle afterward.
            if (div_count == 0) begin
                if (state == S_CMD) begin
                    case (edge_index)
                        2: dq_out <= 8'h00;             // A3
                        3: dq_out <= address[23:16];   // A2
                        4: dq_out <= address[15:8];    // A1
                        5: dq_out <= address[7:0];     // A0
                    endcase
                end else if (state == S_WRITE) begin
                    if (data_index == 0) begin
                        dq_oe <= 1;
                        dm_oe <= 1;
                        dq_out <= pattern[15:8];
                    end else if (data_index == 1) begin
                        dq_out <= pattern[7:0];
                    end
                end
            end

            case (state)
                S_POWER: begin
                    PSRAM_CE_N <= 1;
                    PSRAM_CLK <= 0;
                    if (power_count == POWERUP_CYCLES-1)
                        state <= did_global_reset ? S_START : S_RESET_START;
                    else power_count <= power_count + 1'b1;
                end

                S_RESET_START: begin
                    PSRAM_CE_N <= 0;
                    PSRAM_CLK <= 0;
                    dq_oe <= 1;
                    dq_out <= 8'hFF;
                    dm_oe <= 0;
                    div_count <= 0;
                    edge_index <= 0;
                    stage_code <= 8'h02;
                    state <= S_RESET_CMD;
                end

                S_RESET_CMD: if (tick) begin
                    PSRAM_CLK <= ~PSRAM_CLK;
                    edge_index <= edge_index + 1'b1;
                    if (edge_index == 1) dq_oe <= 0;
                    if (edge_index == 7) state <= S_RESET_END;
                end

                S_RESET_END: if (tick) begin
                    PSRAM_CE_N <= 1;
                    PSRAM_CLK <= 0;
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
                    dq_oe <= 1;
                    dq_out <= id_phase ? 8'h40 : (read_phase ? 8'h20 : 8'hA0);
                    dm_oe <= 0;
                    div_count <= 0;
                    edge_index <= 0;
                    data_index <= 0;
                    timeout_edges <= 0;
                    sample_pending <= 0;
                    dqs_edge_word <= 0;
                    clk_read_word <= 0;
                    clk_sample_pending <= 0;
                    read_word <= 0;
                    sample_early <= 0;
                    sample_mid <= 0;
                    sample_late <= 0;
                    stage_code <= id_phase ? 8'h08 : (read_phase ? 8'h20 : 8'h10);
                    state <= S_CMD;
                end

                S_CMD: if (tick) begin
                    PSRAM_CLK <= ~PSRAM_CLK;
                    edge_index <= edge_index + 1'b1;
                    if (edge_index == 5) begin
                        state <= S_TURN;
                        edge_index <= 0;
                    end
                end

                // Preserve address hold time after the final falling edge.
                S_TURN: begin
                    dq_oe <= 0;
                    state <= (id_phase || read_phase) ? S_READ : S_LATENCY;
                end

                S_LATENCY: if (tick) begin
                    PSRAM_CLK <= ~PSRAM_CLK;
                    edge_index <= edge_index + 1'b1;
                    // LC=5 includes the final address cycle. Four more
                    // full clocks (eight DDR edges) precede the first data.
                    if (edge_index == 7) begin
                        state <= S_WRITE;
                        data_index <= 0;
                    end
                end

                S_WRITE: if (tick) begin
                    PSRAM_CLK <= ~PSRAM_CLK;
                    if (data_index == 0) begin
                        data_index <= 1;
                    end else begin
                        state <= S_END;
                    end
                end

                S_READ: begin
                    if (tick) begin
                        PSRAM_CLK <= ~PSRAM_CLK;
                        timeout_edges <= timeout_edges + 1'b1;
                        if (id_phase && (timeout_edges == 8 || timeout_edges == 9)) begin
                            clk_sample_pending <= 1;
                            clk_sample_delay <= speed_select == 2'd0 ? 2'd3 : 2'd1;
                            clk_sample_byte <= (timeout_edges == 9);
                        end
                        // Bound a missing-DQS transaction. Register reads use
                        // fixed LC=5; memory reads may incur refresh pushout.
                        if (timeout_edges == (id_phase ? 7'd17 : 7'd50)) begin
                            stage_code <= 8'hE1; // no two DQS data edges
                            failure_address <= address;
                            dqs_edge_pair1 <= dqs_edge_word;
                            mr_pair1 <= read_word;
                            clk_pair1 <= clk_read_word;
                            state <= S_FAIL;
                        end
                    end
                    // The initial DQS transition into the low preamble is
                    // not data. D0 starts at the first rising strobe edge.
                    if ((((data_index == 0) && dqs_rise) ||
                         ((data_index == 1) && dqs_fall)) &&
                        !sample_pending) begin
                        sample_pending <= 1;
                        sample_delay <= fastest_sample ? 3'd0 : (fast_sample ? 3'd1 : 3'd4);
                        if (fast_sample) begin
                            if (data_index == 0) begin
                                sample_early[15:8] <= PSRAM_DQ;
                                if (!fastest_sample) read_word[15:8] <= PSRAM_DQ;
                            end else begin
                                sample_early[7:0] <= PSRAM_DQ;
                                if (!fastest_sample) read_word[7:0] <= PSRAM_DQ;
                            end
                        end
                        if (fastest_sample) begin
                            if (data_index == 0) begin
                                sample_mid[15:8] <= PSRAM_DQ;
                                read_word[15:8] <= PSRAM_DQ;
                            end else begin
                                sample_mid[7:0] <= PSRAM_DQ;
                                read_word[7:0] <= PSRAM_DQ;
                            end
                        end
                        if (data_index == 0) dqs_edge_word[15:8] <= {1'b0, timeout_edges};
                        else dqs_edge_word[7:0] <= {1'b0, timeout_edges};
                    end
                    if (data_index == 2 && !sample_pending &&
                        (!id_phase || (timeout_edges >= 10 && !clk_sample_pending)))
                        state <= S_END;
                end

                S_END: if (tick) begin
                    PSRAM_CE_N <= 1;
                    PSRAM_CLK <= 0;
                    dq_oe <= 0;
                    dm_oe <= 0;
                    gap_count <= 0;
                    state <= S_GAP;
                end

                S_GAP: if (tick) begin
                    gap_count <= gap_count + 1'b1;
                    if (gap_count == 8'd31) state <= S_ADVANCE;
                end

                S_ADVANCE: begin
                    if (id_phase) begin
                        if (id_slot == 0) begin
                            mr_pair0 <= read_word;
                            id_slot <= 1;
                            state <= S_START;
                        end else if (id_slot == 1) begin
                            mr_pair1 <= read_word;
                            id_word <= read_word;
                            dqs_edge_pair1 <= dqs_edge_word;
                            clk_pair1 <= clk_read_word;
                            // MR1[4:0] is APM vendor 0Dh; MR2[4:0]
                            // identifies generation 3 and 64 Mbit density.
                            // The CLK-domain reference capture was calibrated
                            // only for 8.47 MHz. At faster settings, DQS is
                            // the read timing reference; the memory tests
                            // still check every returned data word.
                            if (((read_word[15:8] & 8'h1F) != 8'h0D) ||
                                ((read_word[7:0] & 8'h1F) != 8'h13) ||
                                ((speed_select == 2'd0) && (read_word != clk_read_word))) begin
                                stage_code <= 8'hE6;
                                failure_address <= 24'h000001;
                                expected_data <= 16'h0D13;
                                actual_data <= read_word;
                                state <= S_FAIL;
                            end else begin
                                id_phase <= 0;
                                state <= S_START;
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
                        state <= S_FAIL;
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
                    dq_oe <= 0;
                    dm_oe <= 0;
                end
                default: state <= S_FAIL;
            endcase
        end
    end
endmodule
