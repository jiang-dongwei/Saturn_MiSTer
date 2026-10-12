module plan_a_trace_snapshot #(parameter integer WIDTH = 8) (
    input src_clk, dst_clk, reset, request,
    input [WIDTH-1:0] data,
    output reg [WIDTH-1:0] snapshot = 0,
    output reg valid = 0,
    output ready
);
    (* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *)
    reg req_meta = 0, req_sync = 0, ack_meta = 0, ack_sync = 0;
    reg ack = 0, seen = 0, pending = 0, complete = 0;
    reg [WIDTH-1:0] held = 0;
    assign ready = !pending && seen == request && ack_sync == request;
    always @(posedge src_clk) begin
        req_meta <= request;
        req_sync <= req_meta;
        if (req_sync != ack) begin
            held <= data;
            ack <= req_sync;
        end
    end
    always @(posedge dst_clk) begin
        ack_meta <= ack;
        ack_sync <= ack_meta;
        if (reset) begin
            seen <= request;
            pending <= 0;
            complete <= 0;
            valid <= 0;
            snapshot <= 0;
        end else if (seen != request) begin
            seen <= request;
            pending <= 1;
            complete <= 0;
            valid <= 0;
        end else if (pending && ack_sync == request) begin
            if (!complete) complete <= 1;
            else begin
                snapshot <= held;
                pending <= 0;
                complete <= 0;
                valid <= 1;
            end
        end
    end
endmodule

module plan_a_uart_trace #(parameter integer DIVIDER = 434) (
    input clk, reset, ram_clk, engine_clk, sys_clk,
    input [15:0] ram_data,
    input [7:0] engine_data,
    input [23:0] sys_data,
    output tx
);
    reg ram_request = 0, engine_request = 0, sys_request = 0;
    wire [15:0] ram_snapshot;
    wire [7:0] engine_snapshot;
    wire [23:0] sys_snapshot;
    wire ram_valid, engine_valid, sys_valid;
    wire ram_ready, engine_ready, sys_ready;
    plan_a_trace_snapshot #(16) ram_sample(ram_clk, clk, reset, ram_request, ram_data, ram_snapshot, ram_valid, ram_ready);
    plan_a_trace_snapshot #(8) engine_sample(engine_clk, clk, reset, engine_request, engine_data, engine_snapshot, engine_valid, engine_ready);
    plan_a_trace_snapshot #(24) sys_sample(sys_clk, clk, reset, sys_request, sys_data, sys_snapshot, sys_valid, sys_ready);
    reg [$clog2(DIVIDER)-1:0] baud = 0;
    reg [9:0] shift = 10'h3ff;
    reg [3:0] bits_left = 0, index = 0;
    reg [7:0] sequence_number = 0, checksum = 0;
    reg [63:0] payload = 0;
    wire [63:0] next_payload = {sys_snapshot, engine_snapshot, ram_snapshot,
                               5'b00000, sys_valid, engine_valid, ram_valid, sequence_number};
    reg [7:0] next_byte;
    always @* begin
        case (index)
            0: next_byte = 8'ha5;
            1: next_byte = 8'h5a;
            2: next_byte = payload[7:0];
            3: next_byte = payload[15:8];
            4: next_byte = payload[23:16];
            5: next_byte = payload[31:24];
            6: next_byte = payload[39:32];
            7: next_byte = payload[47:40];
            8: next_byte = payload[55:48];
            9: next_byte = payload[63:56];
            default: next_byte = checksum;
        endcase
    end
    assign tx = shift[0];
    always @(posedge clk) begin
        if (reset) begin
            baud <= 0;
            shift <= 10'h3ff;
            bits_left <= 0;
            index <= 0;
            sequence_number <= 0;
            checksum <= 0;
            payload <= 0;
        end else if (bits_left == 0) begin
            if (index == 0) begin
                payload <= next_payload;
                checksum <= next_payload[7:0] ^ next_payload[15:8] ^ next_payload[23:16] ^
                            next_payload[31:24] ^ next_payload[39:32] ^ next_payload[47:40] ^
                            next_payload[55:48] ^ next_payload[63:56] ^ 8'hff;
                sequence_number <= sequence_number + 1'b1;
                if (ram_ready) ram_request <= !ram_request;
                if (engine_ready) engine_request <= !engine_request;
                if (sys_ready) sys_request <= !sys_request;
            end
            shift <= {1'b1, next_byte, 1'b0};
            bits_left <= 10;
            baud <= DIVIDER - 1;
            index <= index == 10 ? 4'd0 : index + 1'b1;
        end else if (baud == 0) begin
            shift <= {1'b1, shift[9:1]};
            bits_left <= bits_left - 1'b1;
            baud <= DIVIDER - 1;
        end else baud <= baud - 1'b1;
    end
endmodule
