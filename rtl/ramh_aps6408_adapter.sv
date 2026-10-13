module ramh_aps6408_adapter #(
    parameter integer POWERUP_CYCLES = 135476,
    parameter integer RESET_RECOVERY_CYCLES = 204,
    parameter integer MEMORY_TRAINING_ENABLE = 1
) (
    input clk, reset,
    input engine_clk, engine_reset, clk_phy,
    input [1:0] speed_select,
    input [19:2] addr,
    input [31:0] din,
    input [3:0] wr,
    input rd, burst, rfs,
    output [31:0] dout,
    output busy,
    output init_done, init_error,
    output reg adapter_error,
    output [15:0] device_id,
    output [7:0] stage_code,
    output PSRAM_CLK, PSRAM_CE_N,
    inout [7:0] PSRAM_DQ,
    inout PSRAM_DQS
);
    reg request_toggle, source_pending, write_armed;
    reg [19:2] source_addr;
    reg [31:0] source_data;
    reg [3:0] source_mask;
    reg source_write;
    reg cache_valid;
    reg [19:2] cache_addr;
    reg [31:0] cache_data;
    (* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *)
    reg ack_meta, ack_sync, init_meta, init_sync, error_meta, error_sync;
    reg ack_seen;
    reg ack_toggle, response_error;
    reg [31:0] response_data;
    wire cache_hit = cache_valid && cache_addr == addr;
    assign dout = cache_hit ? cache_data : 32'd0;
    assign init_done = init_sync;
    assign init_error = error_sync;
    assign busy = reset || !init_sync || error_sync || adapter_error || source_pending ||
                  (rd && !cache_hit) || ((|wr) && write_armed);

    always @(posedge clk) begin
        if (reset) begin
            request_toggle <= 0;
            source_pending <= 0;
            source_addr <= 0;
            source_data <= 0;
            source_mask <= 0;
            source_write <= 0;
            write_armed <= 1;
            cache_valid <= 0;
            cache_addr <= 0;
            cache_data <= 0;
            adapter_error <= 0;
            ack_meta <= 0;
            ack_sync <= 0;
            ack_seen <= 0;
            init_meta <= 0;
            init_sync <= 0;
            error_meta <= 0;
            error_sync <= 0;
        end else begin
            ack_meta <= ack_toggle;
            ack_sync <= ack_meta;
            init_meta <= engine_init_done;
            init_sync <= init_meta;
            error_meta <= engine_init_error;
            error_sync <= error_meta;
            if (!(|wr)) write_armed <= 1;
            if (error_sync) adapter_error <= 1;
            if (source_pending && ack_sync != ack_seen) begin
                ack_seen <= ack_sync;
                source_pending <= 0;
                if (response_error) adapter_error <= 1;
                else if (!source_write) begin
                    cache_addr <= source_addr;
                    cache_data <= response_data;
                    cache_valid <= 1;
                end
            end
            if (!source_pending && init_sync && !error_sync && !adapter_error) begin
                if ((|wr) && write_armed || rd && !cache_hit) begin
                    source_addr <= addr;
                    source_data <= din;
                    source_mask <= wr;
                    source_write <= (|wr) && write_armed;
                    request_toggle <= !request_toggle;
                    source_pending <= 1;
                    if ((|wr) && write_armed) begin
                        write_armed <= 0;
                        if (cache_addr == addr) cache_valid <= 0;
                    end
                end
            end
        end
    end

    (* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *)
    reg req_meta, req_sync;
    reg req_seen, half_select;
    (* preserve *) reg [3:0] engine_request_mask;
    (* preserve *) reg engine_request_write;
    reg [1:0] engine_state;
    reg runtime_valid;
    wire runtime_ready, runtime_done, runtime_error;
    wire [15:0] runtime_read;
    wire engine_init_done, engine_init_error;
    localparam E_IDLE=0, E_ISSUE=1, E_WAIT=2, E_ACK=3;
    wire [1:0] half_mask = half_select ? engine_request_mask[1:0] : engine_request_mask[3:2];
    wire [15:0] half_data = half_select ? source_data[15:0] : source_data[31:16];
    wire [23:0] half_address = {4'd0,source_addr,half_select,1'b0};
    always @(posedge engine_clk) begin
        runtime_valid <= 0;
        if (engine_reset) begin
            req_meta <= 0;
            req_sync <= 0;
            req_seen <= 0;
            ack_toggle <= 0;
            response_error <= 0;
            response_data <= 0;
            half_select <= 0;
            engine_request_mask <= 0;
            engine_request_write <= 0;
            engine_state <= E_IDLE;
        end else begin
            req_meta <= request_toggle;
            req_sync <= req_meta;
            case (engine_state)
                E_IDLE: if (req_sync != req_seen) begin
                    req_seen <= req_sync;
                    engine_request_mask <= source_mask;
                    engine_request_write <= source_write;
                    half_select <= 0;
                    response_error <= 0;
                    engine_state <= E_ISSUE;
                end
                E_ISSUE: begin
                    if (engine_request_write && half_mask == 0) begin
                        if (half_select) engine_state <= E_ACK;
                        else half_select <= 1;
                    end else if (runtime_ready) begin
                        runtime_valid <= 1;
                        engine_state <= E_WAIT;
                    end
                end
                E_WAIT: if (runtime_done) begin
                    if (runtime_error) begin
                        response_error <= 1;
                        engine_state <= E_ACK;
                    end else begin
                        if (half_select) response_data[15:0] <= runtime_read;
                        else response_data[31:16] <= runtime_read;
                        if (half_select) engine_state <= E_ACK;
                        else begin
                            half_select <= 1;
                            engine_state <= E_ISSUE;
                        end
                    end
                end
                E_ACK: begin
                    ack_toggle <= req_seen;
                    engine_state <= E_IDLE;
                end
            endcase
        end
    end

    aps6408_diag_core #(
        .POWERUP_CYCLES(POWERUP_CYCLES),
        .RESET_RECOVERY_CYCLES(RESET_RECOVERY_CYCLES), .RUNTIME_API(1),
        .MEMORY_TRAINING_ENABLE(MEMORY_TRAINING_ENABLE)
    ) engine (
        .clk(engine_clk), .clk_phy(clk_phy), .reset(engine_reset),
        .speed_select(speed_select), .test_mode(2'd0), .d1_mode(2'd0), .drive_half(1'b1),
        .control_fast(speed_select==3),
        .request_valid(runtime_valid), .request_ready(runtime_ready),
        .request_write(engine_request_write), .request_address(half_address),
        .request_write_data(half_data), .request_write_mask(half_mask),
        .request_done(runtime_done), .request_error(runtime_error),
        .request_read_data(runtime_read), .init_done(engine_init_done), .init_error(engine_init_error),
        .id_word(device_id), .stage_code(stage_code),
        .PSRAM_CLK(PSRAM_CLK), .PSRAM_CE_N(PSRAM_CE_N), .PSRAM_DQ(PSRAM_DQ), .PSRAM_DQS(PSRAM_DQS)
    );
endmodule
