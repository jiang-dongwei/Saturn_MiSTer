`timescale 1ns/1ps
module tb_ramh_aps6408;
    reg clk=0, clk_phy=0, clk_sample=0, src_clk=0;
    reg clk_fast=0;
    initial begin #1.84525;clk_fast=1;forever #4.920666667 clk_fast=~clk_fast;end
    wire engine_clk=speed_select==3 ? clk_fast : clk;
    reg [1:0] phase=0;
    real src_half=4.365;
    always #1.84525 clk_sample=~clk_sample;
    always @(posedge clk_sample) begin
        phase <= phase+1'b1;
        clk_phy = !phase[0];
        if (phase==0) clk=1;
        if (phase==2) clk=0;
    end
    always #(src_half) src_clk=~src_clk;
    reg reset=1;
    reg [1:0] speed_select=2;
    reg [19:2] addr=0;
    reg [31:0] din=0;
    reg [3:0] wr=0;
    reg rd=0;
    wire [31:0] dout;
    wire busy, init_done, init_error, adapter_error;
    wire [15:0] device_id;
    wire [7:0] stage_code;
    wire psram_clk, ce_n;
    tri [7:0] dq;
    tri dqs;
    reg mem_oe=0, mem_dqs=0;
    reg [7:0] mem_dq=0;
    assign dq=mem_oe ? mem_dq : 8'hzz;
    assign dqs=mem_oe ? mem_dqs : 1'bz;
`ifdef APS_COUNTER_EQUIV
    localparam MEMORY_TRAINING=0;
`else
    localparam MEMORY_TRAINING=1;
`endif
    ramh_aps6408_adapter #(.POWERUP_CYCLES(8),.RESET_RECOVERY_CYCLES(8),
                         .MEMORY_TRAINING_ENABLE(MEMORY_TRAINING)) dut (
        .clk(src_clk),.reset(reset),.engine_clk(engine_clk),.engine_reset(reset),.clk_phy(clk_phy),
        .speed_select(speed_select),
        .addr(addr),.din(din),.wr(wr),.rd(rd),.burst(1'b1),.rfs(1'b0),
        .dout(dout),.busy(busy),.init_done(init_done),.init_error(init_error),
        .adapter_error(adapter_error),.device_id(device_id),.stage_code(stage_code),
        .PSRAM_CLK(psram_clk),.PSRAM_CE_N(ce_n),.PSRAM_DQ(dq),.PSRAM_DQS(dqs)
    );
    realtime receive_changed_at = -1e9, reference_changed_at = -1e9;
    real control_period;
    integer receive_handoffs = 0;
    always @(dut.engine.rx_early or dut.engine.rx_mid or
             dut.engine.rx_center or dut.engine.rx_late)
        receive_changed_at = $realtime;
    always @(dut.engine.rx_clock) reference_changed_at = $realtime;
    always @(posedge engine_clk) begin
        if (!reset && dut.engine.state == 5 && dut.engine.rx_done_sync &&
            (!dut.engine.id_phase || dut.engine.rx_clock_done_sync)) begin
            control_period = dut.engine.fast_control ? 9.841333334 : 14.762;
            if ($realtime - receive_changed_at < 2 * control_period - 0.01)
                $fatal(1,"Receive payload was not held for two control periods");
            if ({dut.engine.rx_early_hold, dut.engine.rx_mid_hold,
                 dut.engine.rx_center_hold, dut.engine.rx_late_hold} !==
                {dut.engine.rx_early, dut.engine.rx_mid,
                 dut.engine.rx_center, dut.engine.rx_late})
                $fatal(1,"Completed receive snapshots differ from held PHY data");
            if (dut.engine.id_phase) begin
                if ($realtime - reference_changed_at < 2 * control_period - 0.01)
                    $fatal(1,"Reference payload was not held for two control periods");
                if (dut.engine.rx_clock_hold !== dut.engine.rx_clock)
                    $fatal(1,"Completed reference snapshot differs from PHY data");
            end
            receive_handoffs = receive_handoffs + 1;
        end
    end
    final $display("RECEIVE HANDOFF CHECKS: %0d completed reads", receive_handoffs);
`ifdef APS_COUNTER_EQUIV
    tri [7:0] reference_dq;
    tri reference_dqs;
    assign reference_dq = dut.engine.dq_oe ? 8'hzz : dq;
    assign reference_dqs = dut.engine.dm_oe ? 1'bz : dqs;
    wire reference_clk, reference_ce, reference_ready, reference_done, reference_error;
    wire reference_init, reference_init_error;
    wire [15:0] reference_data, reference_id;
    wire [7:0] reference_stage;
    aps6408_diag_core_counter_reference #(
        .POWERUP_CYCLES(8), .RESET_RECOVERY_CYCLES(8), .RUNTIME_API(1)
    ) counter_reference (
        .clk(engine_clk), .clk_phy(clk_phy), .reset(reset), .speed_select(speed_select),
        .test_mode(2'd0), .d1_mode(2'd0), .drive_half(1'b1), .control_fast(speed_select==3),
        .request_valid(dut.runtime_valid), .request_write(dut.source_write),
        .request_address(dut.half_address), .request_write_data(dut.half_data),
        .request_write_mask(dut.half_mask), .request_ready(reference_ready),
        .request_done(reference_done), .request_error(reference_error), .request_read_data(reference_data),
        .init_done(reference_init), .init_error(reference_init_error),
        .id_word(reference_id), .stage_code(reference_stage),
        .PSRAM_CLK(reference_clk), .PSRAM_CE_N(reference_ce),
        .PSRAM_DQ(reference_dq), .PSRAM_DQS(reference_dqs)
    );
    always @(posedge engine_clk or negedge engine_clk) begin
        #0.001;
        if (!reset && {
            reference_clk, reference_ce, reference_ready, reference_done, reference_error,
            reference_data, reference_init, reference_init_error, reference_id, reference_stage,
            counter_reference.dq_oe, counter_reference.dq_out, counter_reference.dm_oe, counter_reference.dm_out
        } !== {
            psram_clk, ce_n, dut.runtime_ready, dut.runtime_done, dut.runtime_error,
            dut.runtime_read, dut.engine_init_done, dut.engine_init_error, device_id, stage_code,
            dut.engine.dq_oe, dut.engine.dq_out, dut.engine.dm_oe, dut.engine.dm_out
        }) $fatal(1,"Counter optimization changed an observable engine waveform");
    end
    initial $display("Counter baseline waveform equivalence enabled");
`endif
    reg [7:0] memory[0:1048607];
    reg [7:0] instruction=0, mr0=8'h09;
    reg [31:0] byte_address;
    integer edge_number=-1, writes=0, reads=0, reset_count=0, register_writes=0;
    integer byte_number, first_data_edge, refresh_extra=0;
    integer drop_config=0, missing_memory_dqs=0, bad_training=0, drop_training_dqs=0;
    integer shift_training_word=0;
    integer held_mode=0;
    reg [1:0] held_speed;
    wire memory_read_blocked = missing_memory_dqs || (drop_training_dqs && dut.engine.memory_training);
    real dq_delay=10.0;
    reg device_ready=0;
    realtime edge_time=-1e9, dq_time=-1e9, dm_time=-1e9;
    reg [1:0] transaction_speed;
    real expected_half;
    always @(dq) if (!ce_n && dut.engine.dq_oe) begin
        if ($realtime-edge_time<3.0) $fatal(1,"DQ hold violation");
        dq_time=$realtime;
    end
    always @(dqs) if (!ce_n && dut.engine.dm_oe) begin
        if ($realtime-edge_time<3.0) $fatal(1,"DM hold violation");
        dm_time=$realtime;
    end
    always @(negedge ce_n) edge_number=-1;
    always @(posedge ce_n) begin
        if (instruction==8'hFF) begin
            if (edge_number!=7) $fatal(1,"bad global reset");
            device_ready=1; mr0=8'h09; reset_count=reset_count+1;
        end
        mem_oe <= #1 0;
    end
    always @(posedge psram_clk or negedge psram_clk) if (!ce_n) begin
        if (dut.engine.dq_oe && $realtime-dq_time<3.0) $fatal(1,"DQ setup violation");
        if (dut.engine.dm_oe && $realtime-dm_time<3.0) $fatal(1,"DM setup violation");
        edge_number=edge_number+1;
        if (edge_number>0) begin
            expected_half=transaction_speed==0 ? 59.048 : transaction_speed==1 ? 29.524 : transaction_speed==3 ? 9.841333334 : 14.762;
            if (speed_select==3 && transaction_speed==0) expected_half=59.048;
            if (edge_number==6 && transaction_speed==2 && instruction!=8'hFF) expected_half=29.524;
            if (edge_number==6 && transaction_speed==3 && instruction!=8'hFF) expected_half=19.682666668;
            if ($realtime-edge_time<expected_half-0.01 || $realtime-edge_time>expected_half+0.01)
                $fatal(1,"unexpected clock width");
        end
        edge_time=$realtime;
        case (edge_number)
            0: begin
                instruction=dq; transaction_speed=dut.engine.active_speed;
                if (!device_ready && dq!=8'hFF) $fatal(1,"missing global reset");
                if (dq!=8'hFF && dq!=8'h40 && dq!=8'hC0 && dq!=8'hA0 && dq!=8'h20)
                    $fatal(1,"bad command %h",dq);
                if ((dq==8'hC0 || dq==8'h40 && dut.engine.reference_phase) && transaction_speed!=0)
                    $fatal(1,"reference/config must run at 8MHz");
                if ((dq==8'hA0 || dq==8'h20) && transaction_speed!=(held_mode ? held_speed : speed_select))
                    $fatal(1,"RAMH used wrong selected speed");
            end
            2: byte_address[31:24]=dq;
            3: byte_address[23:16]=dq;
            4: byte_address[15:8]=dq;
            5: begin
                byte_address[7:0]=dq;
                first_data_edge=14+((instruction==8'h20) ? refresh_extra : 0);
                if (instruction==8'h40 || instruction==8'h20 && !memory_read_blocked) begin
                    mem_oe <= #10 1; mem_dqs=0;
                end
                if ((instruction==8'h20 || instruction==8'hA0) &&
                    ((byte_address>=1048576 && !(dut.engine.memory_training && byte_address<=1048582)) || byte_address[0]))
                    $fatal(1,"invalid RAMH address %h",byte_address);
            end
            6: if (instruction==8'hC0) begin
                if (byte_address!=0 || dq!==8'h08) $fatal(1,"wrong driver register write %h",dq);
                if (!drop_config) mr0=dq;
                register_writes=register_writes+1;
            end
        endcase
        if (instruction==8'hA0 && edge_number>=14 && edge_number<=15) begin
            if (dqs!==1'b0 && dqs!==1'b1) $fatal(1,"unknown write mask");
            if (!dqs) memory[byte_address+edge_number-14]=dq;
            if (edge_number==14) writes=writes+1;
        end
        if ((instruction==8'h40 || instruction==8'h20 && !memory_read_blocked) && edge_number>=first_data_edge) begin
            byte_number=edge_number-first_data_edge;
            if (instruction==8'h40) begin
                case (byte_address+byte_number%2)
                    0: mem_dq <= #(dq_delay) mr0;
                    1: mem_dq <= #(dq_delay) 8'h0D;
                    default: mem_dq <= #(dq_delay) 8'h93;
                endcase
            end else begin
                mem_dq <= #(dq_delay) memory[byte_address+byte_number+
                              ((shift_training_word && dut.engine.memory_training) ? 2 : 0)] ^
                                    ((bad_training && dut.engine.memory_training) ? 8'h80 : 8'h00);
                if (byte_number==0) reads=reads+1;
            end
            mem_dqs <= #(dq_delay) !byte_number[0];
        end
    end
    task wait_idle;
        integer timeout;
        begin
            timeout=0;
            while (busy && !adapter_error && timeout<20000) begin @(negedge src_clk); timeout=timeout+1; end
            if (busy || adapter_error) $fatal(1,"adapter stuck/error stage=%h",stage_code);
        end
    endtask
    task write_word;
        input [19:2] a;
        input [31:0] value;
        input [3:0] mask;
        begin
            @(negedge src_clk);addr=a;din=value;wr=mask;rd=0;
            @(negedge src_clk);
            wait_idle;
            repeat(3) @(negedge src_clk);
            wr=0;
            @(negedge src_clk);
        end
    endtask
    task read_word;
        input [19:2] a;
        input [31:0] expected;
        begin
            @(negedge src_clk);addr=a;rd=1;
            @(negedge src_clk);wait_idle;
            if (dout!==expected) $fatal(1,"RAMH read a=%h got=%h expected=%h",a,dout,expected);
            repeat(3) @(negedge src_clk);
        end
    endtask
    integer mask, lane, i, old_reads, old_writes;
    reg [31:0] expected, value;
    initial begin
        if ($test$plusargs("src_fast")) src_half=3.125;
        if ($test$plusargs("src_slow")) src_half=7.1;
        if ($test$plusargs("speed8")) speed_select=0;
        if ($test$plusargs("speed16")) speed_select=1;
        if ($test$plusargs("speed50")) speed_select=3;
        if ($test$plusargs("refresh")) refresh_extra=10;
        drop_config=$test$plusargs("drop_config");
        bad_training=$test$plusargs("bad_training");
        drop_training_dqs=$test$plusargs("drop_training_dqs");
        shift_training_word=$test$plusargs("shift_training_word");
        held_mode=$test$plusargs("held_mode");
        held_speed=speed_select;
        if ($value$plusargs("dq_delay=%f",dq_delay)) begin end
        repeat(6) @(negedge src_clk);reset=0;
        wait(init_done || init_error);
        if (drop_config) begin
            repeat(5) @(negedge src_clk);
            if (!init_error || init_done || stage_code!==8'hE7 || writes!=0 || reads!=0 || !busy)
                $fatal(1,"unverified configuration escaped init gate");
            $display("RAMH APS6408 PASS: rejected bad MR0 before memory access");$finish;
        end
        if (bad_training || drop_training_dqs || shift_training_word) begin
            repeat(5) @(negedge src_clk);
            if (!MEMORY_TRAINING || !init_error || init_done || stage_code!==(drop_training_dqs ? 8'hE1 : 8'hE9) ||
                writes!=4 || reads!=(drop_training_dqs ? 0 : 2) || !busy)
                $fatal(1,"bad training data escaped init gate");
            $display("RAMH APS6408 PASS: rejected bad data training before CPU memory access");$finish;
        end
        if (init_error || device_id!==16'h0D93 || mr0!==8'h08) $fatal(1,"init failed stage=%h",stage_code);
        if (MEMORY_TRAINING) begin
            if (writes!=4 || reads!=2 || {memory[1048576],memory[1048577],memory[1048578],memory[1048579],
                memory[1048580],memory[1048581],memory[1048582],memory[1048583]} !== 64'hA55A3C965AA5C369)
                $fatal(1,"training did not use the reserved guard words");
            $display("MEMORY TRAINING INIT PASS: four scratch writes and two calibrated reads");
        end
        if (held_mode) begin
            if (!MEMORY_TRAINING || held_speed==3) $fatal(1,"held mode test requires a normal runtime clock");
            speed_select=(held_speed==2) ? 0 : 2;
            write_word(18'h11111,32'hA55A8041,4'hF);
            read_word(18'h11111,32'hA55A8041);rd=0;
            speed_select=1;
            write_word(18'h11111,32'h5AA57FBE,4'hF);
            read_word(18'h11111,32'h5AA57FBE);rd=0;
            speed_select=held_speed;
            $display("HELD MODE PASS: input changes preserve initialized memory clock and transfers");
        end
        for (mask=1;mask<16;mask=mask+1) begin
            write_word(18'h12345,32'hA55A8041,4'hF);
            value=32'h369C7FE2 ^ (mask*32'h01010101);expected=32'hA55A8041;
            for(lane=0;lane<4;lane=lane+1) if(mask[lane]) expected[lane*8+:8]=value[lane*8+:8];
            old_writes=writes;write_word(18'h12345,value,mask);
            if(writes-old_writes!=((|mask[3:2])+ (|mask[1:0]))) $fatal(1,"duplicate or missing half-word write");
            read_word(18'h12345,expected);rd=0;
        end
        for(i=0;i<8;i=i+1) write_word(i,32'hA5010000+i,4'hF);
        write_word(18'h3FFFF,32'h12345678,4'hF);
        for(i=0;i<8;i=i+1) read_word(i,32'hA5010000+i);
        old_reads=reads;repeat(25) @(negedge src_clk);
        if(reads!=old_reads || busy) $fatal(1,"held cache hit retriggered or stalled");
        read_word(18'h3FFFF,32'h12345678);rd=0;
        @(negedge src_clk);reset=1;repeat(6) @(negedge src_clk);reset=0;
        wait(init_done || init_error);
        read_word(18'h3FFFF,32'h12345678);rd=0;
        if(reset_count!=1 || register_writes!=2) $fatal(1,"bad soft restart init");
        @(negedge src_clk);reset=1;speed_select=(speed_select==2) ? 0 : 2;
        held_speed=speed_select;
        repeat(6) @(negedge src_clk);reset=0;
        wait(init_done || init_error);
        read_word(18'h3FFFF,32'h12345678);rd=0;
        if(reset_count!=1 || register_writes!=3) $fatal(1,"speed change failed to retrain/preserve RAM");
        missing_memory_dqs=1;
        @(negedge src_clk);addr=18'h23456;rd=1;
        wait(adapter_error);repeat(4) @(negedge src_clk);
        if(!busy || stage_code!==8'hE1) $fatal(1,"timeout must fail closed");
        $display("RAMH APS6408 PASS: masks, held bursts, address ends, cache, CDC, reset, speed change and timeout reads=%0d writes=%0d",reads,writes);
        $finish;
    end
    initial begin #20000000; $fatal(1,"global timeout"); end
endmodule
