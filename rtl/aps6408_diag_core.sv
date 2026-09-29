// Low-speed, standalone APS6408L-3OBM-BA DDR OPI board diagnostic.
// The FPGA clock oversamples the source-synchronous DQS input. This is a
// bring-up implementation at 4.23 MHz, not a high-speed Saturn RAMH backend.
module aps6408_diag_core #(
    parameter integer POWERUP_CYCLES = 135476, // 2 ms at 67.738 MHz
    parameter integer HALF_PERIOD = 8,          // 4.234 MHz PSRAM clock
    parameter integer RESET_RECOVERY_CYCLES = 136 // at least 2 us at 67.738 MHz
) (
    input clk,
    input reset,
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
    reg [7:0] div_count;
    reg [7:0] gap_count;
    reg [6:0] timeout_edges;
    reg [4:0] edge_index;
    reg [3:0] data_index;
    reg [4:0] cell_index;
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

    assign PSRAM_DQ = dq_oe ? dq_out : 8'hzz;
    assign PSRAM_DQS = dm_oe ? 1'b0 : 1'bz; // DM=0 enables both write bytes
    assign activity = (state != S_PASS) && (state != S_FAIL);

    function [23:0] address_for;
        input [4:0] index;
        begin
            if (index == 0) address_for = 24'h000000;
            else if (index <= 22) address_for = 24'h000001 << index;
            else if (index == 23) address_for = 24'h3FFFFE;
            else address_for = 24'h7FFFFE;
        end
    endfunction

    function [15:0] pattern_for;
        input [4:0] index;
        begin
            case (index)
                0: pattern_for=16'h0000;
                1: pattern_for=16'hFFFF;
                2: pattern_for=16'h00FF;
                3: pattern_for=16'hFF00;
                4: pattern_for=16'hA55A;
                5: pattern_for=16'h5AA5;
                default: pattern_for=16'h1200 | {11'd0,index};
            endcase
        end
    endfunction

    wire [23:0] address = id_phase ? {22'd0,id_slot} : address_for(cell_index);
    wire [15:0] pattern = pattern_for(cell_index);
    wire tick = (div_count == HALF_PERIOD-1);

    // At this slow diagnostic clock, detect DQS in the 67 MHz fabric clock
    // domain, then sample DQ two fabric cycles later. There is no CDC into a
    // second domain. Higher-speed use needs a dedicated DDIO capture path.
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
            diagnostic_leds <= 0;
        end else begin
            if (tick) div_count <= 0;
            else div_count <= div_count + 1'b1;

            if (sample_pending) begin
                if (sample_delay == 4) begin
                    if (data_index == 0) sample_early[15:8] <= PSRAM_DQ;
                    else sample_early[7:0] <= PSRAM_DQ;
                end
                if (sample_delay == 2) begin
                    if (data_index == 0) begin
                        sample_mid[15:8] <= PSRAM_DQ;
                        read_word[15:8] <= PSRAM_DQ;
                    end else begin
                        sample_mid[7:0] <= PSRAM_DQ;
                        read_word[7:0] <= PSRAM_DQ;
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
                    // INST on first rising edge; A3..A0 on edges 3..6.
                    case (edge_index)
                        0: dq_out <= 8'h00;
                        1: dq_out <= 8'h00; // A3, high address byte reserved
                        2: dq_out <= address[23:16]; // A2
                        3: dq_out <= address[15:8]; // A1
                        4: dq_out <= address[7:0]; // A0
                        5: begin
                            // A0 was latched at this edge.
                            state <= S_TURN;
                            edge_index <= 0;
                        end
                    endcase
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
                        dq_oe <= 1;
                        dm_oe <= 1;
                        dq_out <= pattern[15:8];
                        data_index <= 0;
                    end
                end

                S_WRITE: if (tick) begin
                    PSRAM_CLK <= ~PSRAM_CLK;
                    if (data_index == 0) begin
                        dq_out <= pattern[7:0];
                        data_index <= 1;
                    end else begin
                        state <= S_END;
                    end
                end

                S_READ: begin
                    if (tick) begin
                        PSRAM_CLK <= ~PSRAM_CLK;
                        timeout_edges <= timeout_edges + 1'b1;
                        if (timeout_edges == 7'd100) begin
                            stage_code <= 8'hE1; // no two DQS data edges
                            failure_address <= address;
                            state <= S_FAIL;
                        end
                    end
                    // The initial DQS transition into the low preamble is
                    // not data. D0 starts at the first rising strobe edge.
                    if ((((data_index == 0) && dqs_pipe[1] && !dqs_prev) ||
                         ((data_index == 1) && !dqs_pipe[1] && dqs_prev)) &&
                        !sample_pending) begin
                        sample_pending <= 1;
                        sample_delay <= 4;
                    end
                    if (data_index == 2 && !sample_pending) state <= S_END;
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
                            id_slot <= 2;
                            state <= S_START;
                        end else begin
                            mr_pair2 <= read_word;
                            // MR1[4:0] is APM vendor 0Dh; MR2[4:0]
                            // identifies generation 3 and 64 Mbit density.
                            if (((mr_pair1[15:8] & 8'h1F) != 8'h0D) ||
                                ((mr_pair1[7:0] & 8'h1F) != 8'h13)) begin
                                stage_code <= 8'hE5;
                                failure_address <= 24'h000001;
                                expected_data <= 16'h0D13;
                                actual_data <= mr_pair1;
                                state <= S_FAIL;
                            end else begin
                                id_phase <= 0;
                                state <= S_START;
                            end
                        end
                    end else if (read_phase && read_word != pattern) begin
                        stage_code <= 8'hE2;
                        failure_address <= address;
                        expected_data <= pattern;
                        actual_data <= read_word;
                        state <= S_FAIL;
                    end else if (cell_index == 24) begin
                        if (read_phase) state <= S_PASS;
                        else begin
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
