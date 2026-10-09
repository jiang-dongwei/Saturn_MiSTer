module aps6408_ramh_statistics #(
    parameter integer WORDS = 262144,
    parameter integer TIMEOUT_CYCLES = 16777216
) (
    input clk, reset,
    input [1:0] seed_select,
    input init_done, init_error, adapter_error, busy,
    input [31:0] dout,
    output [19:2] addr,
    output [31:0] din,
    output reg [3:0] wr,
    output reg rd,
    output ready,
    output failed,
    output [703:0] report
);
    localparam BOOT=0, WRITE_START=1, WRITE_BUSY=2, WRITE_WAIT=3,
               READ_START=4, READ_BUSY=5, READ_WAIT=6, EVALUATE=7,
               FINISH=8, DONE=9, FAULT=10;
    localparam [31:0] WORD_COUNT = WORDS;
    reg [3:0] state;
    reg [17:0] index;
    reg [31:0] seed, pattern, received, error_words;
    reg [31:0] first_address, last_address, first_expected, first_actual;
    reg [31:0] xor_or, rising_or, falling_or, checksum;
    reg [31:0] dq_counts[0:7];
    reg [31:0] wait_cycles;
    wire [31:0] difference = pattern ^ received;
    integer bit_index;
    reg [31:0] checksum_value;

    assign addr = index;
    assign din = pattern;
    assign ready = state == DONE;
    assign failed = state == FAULT;
    assign report = {checksum, dq_counts[7], dq_counts[6], dq_counts[5], dq_counts[4],
                     dq_counts[3], dq_counts[2], dq_counts[1], dq_counts[0],
                     falling_or, rising_or, xor_or, first_actual, first_expected,
                     last_address, first_address, error_words, WORD_COUNT, seed,
                     32'h00000501, 32'd1, 32'h53544154};
    always @* begin
        checksum_value = 0;
        for (integer field_index=0; field_index<21; field_index=field_index+1)
            checksum_value = checksum_value ^ report[field_index*32 +: 32];
    end
    function [31:0] selected_seed;
        input [1:0] selection;
        begin
            case (selection)
                0: selected_seed=32'hA55A8041;
                1: selected_seed=32'h5AA57FBE;
                2: selected_seed=32'hFFFFFFFF;
                default: selected_seed=0;
            endcase
        end
    endfunction

    always @(posedge clk) begin
        if (reset) begin
            state <= BOOT;
            index <= 0;
            seed <= selected_seed(seed_select);
            pattern <= selected_seed(seed_select);
            received <= 0;
            wr <= 0;
            rd <= 0;
            error_words <= 0;
            first_address <= 0;
            last_address <= 0;
            first_expected <= 0;
            first_actual <= 0;
            xor_or <= 0;
            rising_or <= 0;
            falling_or <= 0;
            checksum <= 0;
            wait_cycles <= 0;
            for (bit_index=0; bit_index<8; bit_index=bit_index+1)
                dq_counts[bit_index] <= 0;
        end else if (init_error || adapter_error || wait_cycles == TIMEOUT_CYCLES-1) begin
            state <= FAULT;
            wr <= 0;
            rd <= 0;
        end else begin
            if (state == BOOT || state == WRITE_BUSY || state == WRITE_WAIT ||
                state == READ_BUSY || state == READ_WAIT)
                wait_cycles <= wait_cycles + 1'b1;
            else wait_cycles <= 0;
            case (state)
                BOOT: if (init_done && !busy) state <= WRITE_START;
                WRITE_START: if (!busy) begin
                    wr <= 4'hF;
                    state <= WRITE_BUSY;
                end
                WRITE_BUSY: if (busy) begin
                    wr <= 0;
                    state <= WRITE_WAIT;
                end
                WRITE_WAIT: if (!busy) begin
                    if (index == WORDS-1) begin
                        index <= 0;
                        pattern <= seed;
                        state <= READ_START;
                    end else begin
                        index <= index + 1'b1;
                        pattern <= pattern + 32'h01010101;
                        state <= WRITE_START;
                    end
                end
                READ_START: if (!busy) begin
                    rd <= 1;
                    state <= READ_BUSY;
                end
                READ_BUSY: if (busy) state <= READ_WAIT;
                READ_WAIT: if (!busy) begin
                    received <= dout;
                    rd <= 0;
                    state <= EVALUATE;
                end
                EVALUATE: begin
                    if (difference != 0) begin
                        error_words <= error_words + 1'b1;
                        if (error_words == 0) begin
                            first_address <= 32'h26000000 + {12'd0,index,2'b00};
                            first_expected <= pattern;
                            first_actual <= received;
                        end
                        last_address <= 32'h26000000 + {12'd0,index,2'b00};
                        xor_or <= xor_or | difference;
                        rising_or <= rising_or | (difference & received);
                        falling_or <= falling_or | (difference & pattern);
                        for (bit_index=0; bit_index<8; bit_index=bit_index+1)
                            if ((difference & (32'h01010101 << bit_index)) != 0)
                                dq_counts[bit_index] <= dq_counts[bit_index] + 1'b1;
                    end
                    if (index == WORDS-1) state <= FINISH;
                    else begin
                        index <= index + 1'b1;
                        pattern <= pattern + 32'h01010101;
                        state <= READ_START;
                    end
                end
                FINISH: begin
                    checksum <= checksum_value;
                    state <= DONE;
                end
                DONE: begin wr <= 0; rd <= 0; end
                FAULT: begin wr <= 0; rd <= 0; end
                default: state <= FAULT;
            endcase
        end
    end
endmodule
