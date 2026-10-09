`timescale 1ns/1ps
module tb_aps6408_ramh_statistics;
    parameter integer WORDS=128;
    reg clk=0, reset=1, init_done=0, init_error=0, adapter_error=0, busy=0;
    reg [1:0] seed_select=0;
    reg [31:0] dout=0;
    reg [7:0] adapter_stage=8'hE6;
    reg [15:0] device_id=16'h0D5D;
    wire [19:2] addr;
    wire [31:0] din;
    wire [3:0] wr;
    wire rd, ready, failed;
    wire [703:0] report;
    aps6408_ramh_statistics #(.WORDS(WORDS),.TIMEOUT_CYCLES(64)) dut (.*);
    always #5 clk=~clk;
    reg [31:0] memory[0:WORDS-1];
    reg [31:0] expected[0:21];
    reg [31:0] seed, value, mask, checksum;
    reg inject, all_faults, stall_read, stall_write, no_init, bad_init, bad_adapter;
    integer selection, writes=0, reads=0, phase=0, delay_cycles=0, pending_address;
    reg pending_read;
    integer i, j, cycles=0;
    function [31:0] reference_pattern;
        input integer index;
        reference_pattern=seed + index*32'h01010101;
    endfunction
    function [31:0] fault_mask;
        input integer index;
        begin
            fault_mask=0;
            if (all_faults) fault_mask=32'hFFFFFFFF;
            else if (inject) begin
                if (index==0) fault_mask=fault_mask | 32'h80000001;
                if (index==WORDS-1) fault_mask=fault_mask | 32'h00808000;
                if (index%7==3) fault_mask=fault_mask | 32'h00000280;
            end
        end
    endfunction
    always @(negedge clk) begin
        if (!reset) begin
            cycles=cycles+1;
            if (cycles>WORDS*24+1000) $fatal(1,"statistics completion timeout");
            case (phase)
                0: if ((wr!=0 || rd) && !ready && !failed) begin
                    if (wr!=0 && rd) $fatal(1,"simultaneous read/write");
                    if (addr>=WORDS) $fatal(1,"out-of-window request");
                    pending_address=addr;
                    pending_read=rd;
                    busy=1;
                    delay_cycles=3+(addr%3);
                    phase=1;
                    if (wr!=0) begin
                        if (wr!=15 || writes!=addr || din!==reference_pattern(addr))
                            $fatal(1,"write address/mask/data mismatch");
                        memory[addr]=din;
                        writes=writes+1;
                    end else begin
                        if (writes!=WORDS || reads!=addr) $fatal(1,"read coverage/order mismatch");
                        reads=reads+1;
                    end
                end
                1: if (!(pending_read ? stall_read : stall_write)) begin
                    delay_cycles=delay_cycles-1;
                    if (delay_cycles==0) begin
                        if (pending_read) dout=memory[pending_address]^fault_mask(pending_address);
                        busy=0;
                        phase=2;
                    end
                end
                2: if (wr==0 && !rd) phase=0;
            endcase
        end
    end
    initial begin
        selection=0;
        if ($value$plusargs("seed=%d",selection)) begin end
        seed_select=selection;
        case (selection)
            0: seed=32'hA55A8041;
            1: seed=32'h5AA57FBE;
            2: seed=32'hFFFFFFFF;
            3: seed=0;
            default: $fatal(1,"invalid seed");
        endcase
        inject=$test$plusargs("inject"); all_faults=$test$plusargs("all_faults");
        stall_read=$test$plusargs("stall_read"); stall_write=$test$plusargs("stall_write");
        no_init=$test$plusargs("no_init"); bad_init=$test$plusargs("bad_init");
        bad_adapter=$test$plusargs("bad_adapter");
        for (i=0;i<22;i=i+1) expected[i]=0;
        expected[0]=32'h53544154; expected[1]=1; expected[2]=32'h501;
        expected[3]=seed; expected[4]=WORDS;
        for (i=0;i<WORDS;i=i+1) begin
            value=reference_pattern(i); mask=fault_mask(i);
            if (mask!=0) begin
                if (expected[5]==0) begin
                    expected[6]=32'h26000000+i*4;
                    expected[8]=value; expected[9]=value^mask;
                end
                expected[5]=expected[5]+1;
                expected[7]=32'h26000000+i*4;
                expected[10]=expected[10]|mask;
                expected[11]=expected[11]|(mask&(value^mask));
                expected[12]=expected[12]|(mask&value);
                for (j=0;j<8;j=j+1)
                    if ((mask&(32'h01010101<<j))!=0) expected[13+j]=expected[13+j]+1;
            end
        end
        checksum=0;
        for (i=0;i<21;i=i+1) checksum=checksum^expected[i];
        expected[21]=checksum;
        repeat(4) @(negedge clk);
        reset=0;
        seed_select=~selection;
        repeat(4) @(negedge clk);
        init_done=!no_init; init_error=bad_init; adapter_error=bad_adapter;
        wait(ready || failed);
        @(negedge clk);
        if (no_init || bad_init || bad_adapter || stall_read || stall_write) begin
            if (!failed || ready) $fatal(1,"fault did not fail closed");
            if (report[0+:32]!==32'h46414C54 || report[32+:32]!==1 ||
                report[64+:32]!== (bad_init ? 1 : bad_adapter ? 2 : 3))
                $fatal(1,"incorrect fault reason");
            if (report[288+:32]!==32'hE6 || report[640+:32]!==32'h0D5D)
                $fatal(1,"fault stage/device not captured");
            checksum=0;
            for (i=0;i<21;i=i+1) checksum=checksum^report[i*32+:32];
            if (checksum!==report[672+:32]) $fatal(1,"fault checksum mismatch");
            if (report[576+:32]!== (stall_write ? 0 : writes) || report[608+:32]!== (stall_read ? 0 : reads))
                $fatal(1,"fault completed transaction counts incorrect");
        end else begin
            if (!ready || failed || writes!=WORDS || reads!=WORDS)
                $fatal(1,"incomplete scan reason=%0d state=%0d writes=%0d reads=%0d",dut.fault_reason,dut.fault_state,writes,reads);
            for (i=0;i<22;i=i+1)
                if (report[i*32+:32]!==expected[i])
                    $fatal(1,"field %0d expected %08x actual %08x",i,expected[i],report[i*32+:32]);
            for (i=0;i<WORDS;i=i+1)
                if (memory[i]!==reference_pattern(i)) $fatal(1,"read scan altered memory");
            if (dut.completed_reads!=WORDS || dut.completed_writes!=WORDS)
                $fatal(1,"completed transaction counters incorrect");
        end
        repeat(8) begin
            @(negedge clk);
            if (wr!=0 || rd) $fatal(1,"activity after terminal state");
        end
        $display("RAMH statistics PASS words=%0d seed=%08x errors=%0d failed=%0d writes=%0d reads=%0d",WORDS,seed,expected[5],failed,writes,reads);
        $finish;
    end
endmodule
