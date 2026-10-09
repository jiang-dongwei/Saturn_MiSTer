`timescale 1ns/1ps
module tb_aps6408_dq7_taps;
    reg clk=0;
    always #5 clk=~clk;
    reg [1:0] speed=2;
    reg [2:0] first_mode=0, second_mode=0;
    reg id=0, training=0, retry=0, reference_mode=0;
    reg [15:0] early_value, mid_value, center_value, late_value;
    reg [15:0] samples [0:3];
    reg [15:0] original_word, expected_word;
    wire [7:0] dq_enabled, dq_disabled, dq_adapter;
    wire dqs_enabled, dqs_disabled, dqs_adapter;
    reg adapter_reset=1;
    integer s, flags, f, l, pattern_index, checks=0;
    aps6408_diag_core #(.RUNTIME_API(1),.DQ7_DIAGNOSTIC_ENABLE(1)) enabled (
        .clk(clk),.clk_phy(1'b0),.reset(1'b0),.speed_select(speed),
        .test_mode(2'd0),.d1_mode(2'd0),.drive_half(1'b1),.control_fast(1'b0),
        .dq7_tap_first(first_mode),.dq7_tap_second(second_mode),
        .request_valid(1'b0),.request_write(1'b0),.request_address(24'd0),
        .request_write_data(16'd0),.request_write_mask(2'd0),
        .PSRAM_DQ(dq_enabled),.PSRAM_DQS(dqs_enabled));
    aps6408_diag_core #(.RUNTIME_API(1)) disabled (
        .clk(clk),.clk_phy(1'b0),.reset(1'b0),.speed_select(speed),
        .test_mode(2'd0),.d1_mode(2'd0),.drive_half(1'b1),.control_fast(1'b0),
        .dq7_tap_first(first_mode),.dq7_tap_second(second_mode),
        .request_valid(1'b0),.request_write(1'b0),.request_address(24'd0),
        .request_write_data(16'd0),.request_write_mask(2'd0),
        .PSRAM_DQ(dq_disabled),.PSRAM_DQS(dqs_disabled));
    ramh_aps6408_adapter #(.DQ7_DIAGNOSTIC_ENABLE(1)) adapter (
        .clk(clk),.reset(adapter_reset),.engine_clk(clk),.engine_reset(adapter_reset),
        .clk_phy(1'b0),.speed_select(speed),
        .dq7_tap_first(first_mode),.dq7_tap_second(second_mode),
        .addr(18'd0),.din(32'd0),.wr(4'd0),.rd(1'b0),.burst(1'b0),.rfs(1'b0),
        .PSRAM_DQ(dq_adapter),.PSRAM_DQS(dqs_adapter));
    initial begin
        force enabled.state=4'd5;
        force disabled.state=4'd5;
        force enabled.tick=1'b0;
        force disabled.tick=1'b0;
        force enabled.rx_done_sync=1'b1;
        force disabled.rx_done_sync=1'b1;
        force enabled.rx_clock_done_sync=1'b1;
        force disabled.rx_clock_done_sync=1'b1;
        force enabled.id_phase=id;
        force disabled.id_phase=id;
        force enabled.memory_training=training;
        force disabled.memory_training=training;
        force enabled.retry_slow=retry;
        force disabled.retry_slow=retry;
        force enabled.use_reference_taps=reference_mode;
        force disabled.use_reference_taps=reference_mode;
        force enabled.read_capture_tap=2'd3;
        force disabled.read_capture_tap=2'd3;
        force enabled.read_capture_tap_second=2'd1;
        force disabled.read_capture_tap_second=2'd1;
        force enabled.reference_tap_first=2'd0;
        force disabled.reference_tap_first=2'd0;
        force enabled.reference_tap_second=2'd2;
        force disabled.reference_tap_second=2'd2;
        force enabled.rx_early_hold=early_value;
        force disabled.rx_early_hold=early_value;
        force enabled.rx_mid_hold=mid_value;
        force disabled.rx_mid_hold=mid_value;
        force enabled.rx_center_hold=center_value;
        force disabled.rx_center_hold=center_value;
        force enabled.rx_late_hold=late_value;
        force disabled.rx_late_hold=late_value;
        repeat(3) @(negedge clk);
        adapter_reset=0;
        for (s=0;s<4;s=s+1)
        for (flags=0;flags<8;flags=flags+1)
        for (f=0;f<8;f=f+1)
        for (l=0;l<8;l=l+1)
        for (pattern_index=0;pattern_index<8;pattern_index=pattern_index+1) begin
            @(negedge clk);
            speed=s; id=flags[0]; training=flags[1]; retry=flags[2];
            reference_mode=s==0 || retry;
            first_mode=f; second_mode=l;
            early_value=$random;mid_value=$random;center_value=$random;late_value=$random;
            samples[0]=early_value;samples[1]=mid_value;samples[2]=center_value;samples[3]=late_value;
            original_word=reference_mode ? {early_value[15:8],late_value[7:0]} :
                                          {center_value[15:8],mid_value[7:0]};
            expected_word=original_word;
            if (s!=0 && flags==0) begin
                if (f>=1 && f<=4) expected_word[15]=samples[f-1][15];
                if (l>=1 && l<=4) expected_word[7]=samples[l-1][7];
            end
            @(posedge clk);#0.001;
            if (enabled.read_word !== expected_word || disabled.read_word !== original_word)
                $fatal(1,"DQ7 selection/capture mismatch speed=%0d flags=%0d first=%0d second=%0d",s,flags,f,l);
            if (((enabled.read_word ^ original_word) & 16'h7F7F) !== 0)
                $fatal(1,"DQ7 control changed another data line");
            if ({adapter.engine_dq7_tap_first,adapter.engine_dq7_tap_second} !== 6'd0)
                $fatal(1,"DQ7 mode changed without engine reset");
            checks=checks+1;
        end
        @(negedge clk);first_mode=4;second_mode=2;adapter_reset=1;
        repeat(2) @(negedge clk);
        if ({adapter.engine_dq7_tap_first,adapter.engine_dq7_tap_second} !== {3'd4,3'd2})
            $fatal(1,"DQ7 mode was not captured during reset");
        adapter_reset=0;first_mode=0;second_mode=0;
        repeat(2) @(negedge clk);
        if ({adapter.engine_dq7_tap_first,adapter.engine_dq7_tap_second} !== {3'd4,3'd2})
            $fatal(1,"Captured DQ7 mode did not remain held");
        $display("DQ7 SELECTOR PASS: %0d captures; only bits15/7 may change; 8MHz/ID/training/retry/disabled preserved; reset-held controls PASS",checks);
        $finish;
    end
endmodule
