`timescale 1ns/1ps

module tb_aps6408_diag;
    reg clk=0;
    reg clk_phy=0;
    reg clk_sample=0;
    reg [1:0] clock_phase=0;
    always #1.84525 clk_sample=~clk_sample;
    always @(posedge clk_sample) begin
        clock_phase <= clock_phase + 1'b1;
        clk_phy = !clock_phase[0];
        if (clock_phase == 0) clk = 1;
        if (clock_phase == 2) clk = 0;
    end
    reg reset=1;
    reg [1:0] speed_select=0;
    reg [1:0] test_mode=0;
    reg [1:0] d1_mode=0;
    reg drive_half=0;
    wire [1:0] result_code;
    wire [7:0] stage_code;
    wire [23:0] failure_address;
    wire [15:0] id_word;
    wire [15:0] expected_data, actual_data;
    wire [15:0] sample_early, sample_mid, sample_late;
    wire [15:0] sample_center;
    wire [15:0] retry_read_data;
    wire retry_read_valid;
    wire [1:0] read_capture_tap;
    wire [1:0] read_capture_tap_second;
    wire [15:0] mr_pair0, mr_pair1, mr_pair2;
    wire [15:0] dqs_edge_pair1, clk_pair1;
    wire [7:0] diagnostic_leds;
    wire activity, psram_clk, psram_ce_n;
    tri [7:0] dq;
    tri dqs;
    reg [7:0] mem_dq=0;
    reg mem_dqs=0;
    reg mem_oe=0;
    assign dq = mem_oe ? mem_dq : 8'hzz;
    assign dqs = mem_oe ? mem_dqs : 1'bz;

    aps6408_diag_core #(.POWERUP_CYCLES(8)) dut (
        .clk(clk), .clk_phy(clk_phy), .reset(reset), .speed_select(speed_select), .test_mode(test_mode), .result_code(result_code),
        .d1_mode(d1_mode),
        .drive_half(drive_half),
        .stage_code(stage_code), .failure_address(failure_address),
        .id_word(id_word),
        .expected_data(expected_data), .actual_data(actual_data),
        .sample_early(sample_early), .sample_mid(sample_mid),
        .sample_late(sample_late),
        .sample_center(sample_center),
        .retry_read_data(retry_read_data),
        .retry_read_valid(retry_read_valid),
        .read_capture_tap(read_capture_tap),
        .read_capture_tap_second(read_capture_tap_second),
        .mr_pair0(mr_pair0), .mr_pair1(mr_pair1),
        .mr_pair2(mr_pair2),
        .dqs_edge_pair1(dqs_edge_pair1),
        .clk_pair1(clk_pair1),
        .diagnostic_leds(diagnostic_leds), .activity(activity),
        .PSRAM_CLK(psram_clk), .PSRAM_CE_N(psram_ce_n),
        .PSRAM_DQ(dq), .PSRAM_DQS(dqs)
    );

    reg [15:0] memory [0:255];
    reg [7:0] instruction;
    reg [31:0] address;
    integer edge_number=-1;
    integer cell_slot;
    integer writes=0, reads=0, id_reads=0;
    integer register_writes=0;
    reg [7:0] mode_register0=8'h09;
    wire [7:0] expected_mr0 = drive_half ? 8'h08 : 8'h09;
    integer drop_drive_write=0;
    integer reset_commands=0;
    reg device_ready=0;
    integer corrupt=0, no_dqs=0, missing_slot1=0, alias_bit12=0, bad_id=0, early_dqs=0;
    realtime last_psram_edge=-1.0e9;
    realtime last_fpga_data=-1.0e9;
    reg rx_was_done=0;
    reg [79:0] held_rx_payload;
    real dqs_delay_ns=10.0;
    real dq_skew_ns=0.0;
    integer dq_leads_dqs=0;
    integer dq_lags_dqs=0;
    integer late_memory_fall=0;
    integer high_write_fault=0, high_read_fault=0;
    integer burst_tail=0;
    integer expect_fault=0;
    reg [1:0] transaction_speed;
    realtime transaction_edge_time;
    real expected_half_period;

    task return_byte;
        input [7:0] value;
        input strobe;
        begin
            mem_dq <= #(dq_leads_dqs ? 1.0 : dqs_delay_ns+dq_skew_ns) value;
            mem_dqs <= #(dqs_delay_ns + ((late_memory_fall && instruction == 8'h20 && !strobe) ? 29.524 : 0.0)) strobe;
        end
    endtask

    always @(posedge psram_clk or negedge psram_clk)
        if (!psram_ce_n) last_psram_edge=$realtime;
    always @(dq)
        if (!psram_ce_n && dut.dq_oe) begin
            last_fpga_data=$realtime;
            if ($realtime-last_psram_edge < 3.0)
                $fatal(1,"FPGA DQ changed within 3 ns of PSRAM clock edge");
        end
    always @(posedge psram_clk or negedge psram_clk)
        if (!psram_ce_n && dut.dq_oe && $realtime-last_fpga_data < 3.0)
            $fatal(1,"FPGA DQ has less than 3 ns setup before PSRAM clock edge");
    always @(posedge clk_phy) begin
        if (rx_was_done && dut.rx.done && dut.rx.arm_sync && !reset &&
            {dut.rx.early_word,dut.rx.mid_word,dut.rx.center_word,dut.rx.late_word,dut.rx.edge_word} !== held_rx_payload)
            $fatal(1,"Receive payload changed before controller released arm");
        rx_was_done <= dut.rx.done;
        held_rx_payload <= {dut.rx.early_word,dut.rx.mid_word,dut.rx.center_word,dut.rx.late_word,dut.rx.edge_word};
    end

    function integer cell_for;
        input [31:0] a;
        reg [31:0] mapped;
        reg [31:0] candidate;
        reg [7:0] spread;
        integer bit_index;
        begin
            mapped = alias_bit12 ? (a & ~32'h00001000) : a;
            cell_for = -1;
            if (mapped == 0) cell_for = 0;
            for (bit_index=1; bit_index<=22; bit_index=bit_index+1)
                if (mapped == (32'h1 << bit_index)) cell_for = bit_index;
            if (mapped == (32'h003FFFFE & (alias_bit12 ? ~32'h00001000 : 32'hFFFFFFFF)))
                cell_for = 23;
            if (mapped == (32'h007FFFFE & (alias_bit12 ? ~32'h00001000 : 32'hFFFFFFFF)))
                cell_for = 24;
            for (bit_index=25; bit_index<256; bit_index=bit_index+1) begin
                spread = bit_index - 25;
                candidate = {8'h00, 1'b0, spread, spread ^ 8'h5A,
                             spread[5:0] ^ 6'h15, 1'b0};
                if (mapped == (alias_bit12 ? (candidate & ~32'h00001000) : candidate))
                    cell_for = bit_index;
            end
        end
    endfunction

    always @(negedge psram_ce_n) begin
        edge_number=-1;
        address=0;
        mem_oe=0;
    end
    always @(posedge psram_ce_n) begin
        mem_oe=0;
        if (instruction == 8'hFF) begin
            if (edge_number != 7) $fatal(1,"global reset requires four clock cycles");
            device_ready=1;
            mode_register0=8'h09;
            reset_commands=reset_commands+1;
        end
    end

    always @(posedge psram_clk or negedge psram_clk) begin
        if (!psram_ce_n) begin
            edge_number=edge_number+1;
            if (edge_number > 0) begin
                expected_half_period = transaction_speed == 0 ? 59.048 : transaction_speed == 1 ? 29.524 : 14.762;
                if (edge_number == 6 && transaction_speed == 2 && instruction != 8'hFF)
                    expected_half_period=29.524;
                if ($realtime-transaction_edge_time < expected_half_period-0.01 ||
                    $realtime-transaction_edge_time > expected_half_period+0.01)
                    $fatal(1,"PSRAM clock changed within a transaction");
                transaction_edge_time=$realtime;
            end
            case (edge_number)
                0: begin
                    instruction=dq;
                    transaction_speed=dut.active_speed;
                    transaction_edge_time=$realtime;
                    if (dq == 8'hA0 && transaction_speed != (test_mode == 1 ? 0 : speed_select))
                        $fatal(1,"wrong write speed");
                    if (dq == 8'h20 && transaction_speed != (dut.retry_slow || test_mode == 2 ? 0 : speed_select))
                        $fatal(1,"wrong read speed");
                    if (dq == 8'h40 && transaction_speed != (dut.reference_phase || test_mode == 2 ? 0 : speed_select))
                        $fatal(1,"wrong MR calibration speed");
                    if (dq == 8'hC0 && transaction_speed != 0)
                        $fatal(1,"MR write must use 8 MHz");
                    if (dq !== 8'hA0 && dq !== 8'h20 && dq !== 8'h40 && dq !== 8'hC0 && dq !== 8'hFF)
                        $fatal(1,"bad instruction %h",dq);
                    if (!device_ready && dq !== 8'hFF)
                        $fatal(1,"command before power-up global reset");
                end
                2: address[31:24]=dq;
                3: address[23:16]=dq;
                4: address[15:8]=dq;
                5: begin
                    address[7:0]=dq;
                    cell_slot=cell_for(address);
                    if (instruction==8'hFF) begin
                        if (dq !== 8'hzz)
                            $fatal(1,"global reset must release address bus");
                    end else if (instruction==8'h40 || instruction==8'hC0) begin
                        if (address > 32'h00000002) $fatal(1,"bad MR address %h",address);
                    end else if (cell_slot<0) $fatal(1,"bad address %h",address);
                    if ((instruction==8'h40 || instruction==8'h20) && !no_dqs && !(missing_slot1 && address==1)) begin
                        #10 mem_oe=1;
                        mem_dqs=0; // read preamble
                    end
                end
                6: if (instruction==8'hC0) begin
                    if (address != 0 || dq !== expected_mr0)
                        $fatal(1,"MR write changed reserved/latency bits or wrong drive: addr=%h data=%h expected=%h",address,dq,expected_mr0);
                    register_writes=register_writes+1;
                    if (!drop_drive_write) mode_register0=dq;
                end
                10: if (early_dqs && instruction==8'h40 && address==1) begin
                    mem_dq=8'hAA;
                    mem_dqs=1;
                end
                11: if (early_dqs && instruction==8'h40 && address==1)
                    mem_dqs=0;
                14: begin
                    if (instruction==8'hA0) begin
                        if (dqs !== 1'b0) $fatal(1,"DM not enabled");
                        memory[cell_slot][15:8]=dq;
                        writes=writes+1;
                    end else begin
                        if (!no_dqs && !(missing_slot1 && address==1)) begin
                            return_byte((instruction==8'h40) ?
                                ((address==0) ? mode_register0 :
                                 (address==1) ? (bad_id ? 8'h16 : 8'h0D) : 8'h93) :
                                (memory[cell_slot][15:8] ^ (corrupt ? 8'h01 : 8'h00)),1'b1);
                        end
                        if (instruction==8'h40) id_reads=id_reads+1;
                        else reads=reads+1;
                    end
                end
                15: begin
                    if (instruction==8'hA0) memory[cell_slot][7:0]=dq ^ ((high_write_fault && transaction_speed != 0) ? 8'h80 : 8'h00);
                    else begin
                        if (!no_dqs && !(missing_slot1 && address==1)) begin
                            return_byte((instruction==8'h40) ?
                                ((address==0) ? (bad_id ? 8'h16 : 8'h0D) :
                                 (address==1) ? 8'h93 : 8'h00) :
                                (memory[cell_slot][7:0] ^ ((high_read_fault && transaction_speed != 0) ? 8'h80 : 8'h00)),1'b0);
                        end
                    end
                end
                default: if (burst_tail && edge_number >= 16 &&
                             (instruction == 8'h40 || instruction == 8'h20) &&
                             !no_dqs && !(missing_slot1 && address==1)) begin
                    if (late_memory_fall && instruction == 8'h20)
                        mem_dq <= #(dqs_delay_ns+dq_skew_ns) edge_number[0] ? 8'h3C : 8'hC3;
                    else return_byte(instruction == 8'h40 ?
                        (edge_number[0] ? ((address==0) ? (bad_id ? 8'h16 : 8'h0D) : (address==1) ? 8'h93 : 8'h00) :
                         ((address==0) ? mode_register0 : (address==1) ? (bad_id ? 8'h16 : 8'h0D) : 8'h93)) :
                        (edge_number[0] ? 8'h3C : 8'hC3), !edge_number[0]);
                end
            endcase
        end
    end

    initial begin
        corrupt=$test$plusargs("corrupt");
        no_dqs=$test$plusargs("no_dqs");
        missing_slot1=$test$plusargs("missing_slot1");
        alias_bit12=$test$plusargs("alias_bit12");
        bad_id=$test$plusargs("bad_id");
        early_dqs=$test$plusargs("early_dqs");
        dq_leads_dqs=$test$plusargs("dq_leads_dqs");
        late_memory_fall=$test$plusargs("late_memory_fall");
        if (dq_leads_dqs) dqs_delay_ns=15.5;
        dq_lags_dqs=$test$plusargs("dq_lags_dqs");
        if (dq_lags_dqs) begin dqs_delay_ns=2.0; dq_skew_ns=6.5; end
        if ($value$plusargs("dqs_delay_ns=%f",dqs_delay_ns)) begin end
        if ($value$plusargs("dq_skew_ns=%f",dq_skew_ns)) begin end
        if ($test$plusargs("speed16")) speed_select=1;
        if ($test$plusargs("speed33")) speed_select=2;
        if ($test$plusargs("low_write")) test_mode=1;
        if ($test$plusargs("low_read")) test_mode=2;
        if ($test$plusargs("d1early")) d1_mode=1;
        if ($test$plusargs("d1late")) d1_mode=2;
        if ($test$plusargs("d1fall")) d1_mode=3;
        burst_tail=$test$plusargs("burst_tail");
        drive_half=$test$plusargs("drive_half");
        drop_drive_write=$test$plusargs("drop_drive_write");
        high_write_fault=$test$plusargs("high_write_fault");
        high_read_fault=$test$plusargs("high_read_fault");
        expect_fault=corrupt || alias_bit12 ||
                     (high_write_fault && speed_select != 0 && test_mode != 1) ||
                     (high_read_fault && speed_select != 0 && test_mode != 2) ||
                     (late_memory_fall && d1_mode == 3 && burst_tail && speed_select != 0 && test_mode != 2);
        repeat (4) @(posedge clk);
        reset=0;
        wait(result_code != 0);
        if (reset_commands != 1 ||
            (no_dqs && (result_code !== 2'd2 || stage_code !== 8'hE1 ||
                        failure_address !== 24'h000000 || dqs_edge_pair1 !== 0)) ||
            (missing_slot1 && (result_code !== 2'd2 || stage_code !== 8'hE1 ||
                              failure_address !== 24'h000001 ||
                              mr_pair0 !== 16'h090D || dqs_edge_pair1 !== 0)) ||
            (bad_id && (result_code !== 2'd2 || stage_code !== 8'hE6 ||
                        (!dq_lags_dqs && (mr_pair0 !== 16'h0916 || mr_pair1 !== 16'h1693)) ||
                        (dq_lags_dqs && sample_late !== 16'h1693) ||
                        mr_pair2 !== 16'h0000 ||
                        ((speed_select == 0) && clk_pair1 !== 16'h1693) ||
                        dqs_edge_pair1[15:8] < 8'd9 || dqs_edge_pair1[15:8] > 8'd11 || writes != 0)) ||
            (early_dqs && (result_code !== 2'd2 || stage_code !== 8'hE6 ||
                           mr_pair1 === clk_pair1 ||
                           clk_pair1 !== 16'h0D93 ||
                           dqs_edge_pair1[15:8] >= 8'd9 || writes != 0)) ||
            (expect_fault && (result_code !== 2'd2 || stage_code !== 8'hE2)) ||
            (drop_drive_write && drive_half && (result_code !== 2'd2 || stage_code !== 8'hE7 || writes != 0 || register_writes != 1)) ||
            (corrupt && dut.read_speed != 0 &&
             (!retry_read_valid || retry_read_data === expected_data)) ||
            (!no_dqs && !missing_slot1 && !bad_id && !early_dqs && !expect_fault && !(drop_drive_write && drive_half) &&
             (result_code !== 2'd1 || id_word !== 16'h0D93 ||
              mr_pair0 !== {expected_mr0,8'h0D} || mr_pair1 !== 16'h0D93 ||
              mr_pair2 !== 16'h0000 ||
              ((speed_select == 0) && clk_pair1 !== 16'h0D93) ||
              (dq_leads_dqs && read_capture_tap !== 2'd0) ||
              (dq_lags_dqs && read_capture_tap !== 2'd2) ||
              ((dqs_delay_ns == 10.0) &&
               (dqs_edge_pair1[15:8] < 8'd9 || dqs_edge_pair1[15:8] > 8'd11 ||
                (!late_memory_fall && dqs_edge_pair1[7:0] != dqs_edge_pair1[15:8]+1'b1 &&
                 !(dut.read_speed != 0 && (d1_mode == 1 || d1_mode == 2) && dqs_edge_pair1[7:0] == 0)))) ||
              dut.reference_mr0 !== {expected_mr0,8'h0D} || dut.reference_mr1 !== 16'h0D93 ||
              register_writes != 1 || id_reads != (dut.read_speed == 0 ? 4 : 6) || writes != 1024 || reads != 1024)))
            $fatal(1,"diagnostic failed: result=%d stage=%h addr=%h exp=%h got=%h clk=%h dqs=%h writes=%d reads=%d",
                   result_code,stage_code,failure_address,expected_data,actual_data,clk_pair1,dqs_edge_pair1,writes,reads);
        if (high_read_fault && !high_write_fault && !corrupt && test_mode != 2 && speed_select != 0 &&
            (!retry_read_valid || retry_read_data !== expected_data))
            $fatal(1,"high-speed read fault must disappear with calibrated 8 MHz reread");
        if (high_write_fault && !corrupt && test_mode != 1 && speed_select != 0 && dut.read_speed != 0 &&
            (!retry_read_valid || retry_read_data === expected_data))
            $fatal(1,"stored write fault must survive calibrated 8 MHz reread");
        if (late_memory_fall && d1_mode == 3 && burst_tail && test_mode != 2 && speed_select != 0 &&
            (!retry_read_valid || retry_read_data !== expected_data))
            $fatal(1,"delayed DQS fall must not corrupt the independent 8 MHz reread");
        $display("APS6408 diagnostic scenario PASS: result=%0d stage=%h writes=%0d reads=%0d DQS=%0.2fns skew=%0.2fns tap=%0d/%0d mode=%0d W=%0d R=%0d D1=%0d tail=%0d",
                 result_code,stage_code,writes,reads,dqs_delay_ns,dq_skew_ns,read_capture_tap,read_capture_tap_second,test_mode,dut.write_speed,dut.read_speed,d1_mode,burst_tail);
        if (!no_dqs && !missing_slot1 && !bad_id && !early_dqs && !expect_fault && !(drop_drive_write && drive_half)) begin
            reset=1;
            repeat (4) @(posedge clk);
            reset=0;
            wait(result_code != 0);
            if (result_code !== 2'd1 || reset_commands != 1 || register_writes != 2)
                $fatal(1,"soft restart must not issue another power-up global reset");
        end
        $finish;
    end
    initial begin
        #100000000;
        $fatal(1,"diagnostic timeout");
    end
endmodule
