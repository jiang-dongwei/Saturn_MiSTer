`timescale 1ns/1ps
module tb_aps6408_training;
    reg fast, phase;
    reg memory_phase=0;
    reg [15:0] previous_reference, current_reference, clock_previous, clock_current;
    reg [15:0] pe, pm, pl, pc, ce, cm, cl, cc;
    wire [7:0] dq;
    wire dqs;
    aps6408_diag_core #(.RUNTIME_API(1)) dut (
        .clk(1'b0), .clk_phy(1'b0), .reset(1'b1), .speed_select(2'd2),
        .test_mode(2'd0), .d1_mode(2'd0), .drive_half(1'b1), .control_fast(fast),
        .request_valid(1'b0), .request_write(1'b0), .request_address(24'd0),
        .request_write_data(16'd0), .request_write_mask(2'd0), .PSRAM_DQ(dq), .PSRAM_DQS(dqs));
    reg [15:0] previous [0:3], current [0:3];
    reg [15:0] ref_previous, ref_current, pair_previous, pair_current;
    reg [15:0] old_valid;
    reg [3:0] old_pair;
    integer fmask, smask, flags, t, f, s, ft, st, i, cases;
    function integer first_order(input integer index);
        case(index) 0:first_order=1; 1:first_order=2; 2:first_order=3; 3:first_order=0; endcase
    endfunction
    function integer second_order(input integer index, input fast_mode);
        case(index) 0:second_order=fast_mode?3:2; 1:second_order=fast_mode?1:3;
                    2:second_order=fast_mode?2:1; 3:second_order=0; endcase
    endfunction
    initial begin
        force dut.reference_phase = phase;
        force dut.memory_training = memory_phase;
        force dut.reference_mr0 = previous_reference;
        force dut.reference_mr1 = current_reference;
        force dut.clk_previous_pair = clock_previous;
        force dut.clk_read_word = clock_current;
        force dut.mr0_early = pe;
        force dut.mr0_mid = pm;
        force dut.mr0_late = pl;
        force dut.mr0_center = pc;
        force dut.sample_early = ce;
        force dut.sample_mid = cm;
        force dut.sample_late = cl;
        force dut.sample_center = cc;
        cases=0;
        for (flags=0; flags<32; flags=flags+1)
        for (fmask=0; fmask<16; fmask=fmask+1)
        for (smask=0; smask<16; smask=smask+1) begin
            fast=(flags & 16)!=0;
            phase=(flags & 8)!=0;
            current_reference={(flags & 2)?8'h0C:8'h0D, (flags & 4)?8'h92:8'h93};
            previous_reference={8'h08, (flags & 1)?8'h2D:current_reference[15:8]};
            clock_previous={8'h09, previous_reference[7:0]};
            clock_current=current_reference;
            ref_previous=phase?clock_previous:previous_reference;
            ref_current=phase?clock_current:current_reference;
            for (t=0; t<4; t=t+1) begin
                previous[t]={ref_previous[15:8], ref_previous[7:0] ^ ((smask & (1<<t))?8'h00:8'h01)};
                current[t]={ref_current[15:8] ^ ((fmask & (1<<t))?8'h00:8'h01), ref_current[7:0]};
            end
            pe=previous[0];pm=previous[1];pl=previous[2];pc=previous[3];
            ce=current[0];cm=current[1];cl=current[2];cc=current[3];
            old_valid=0;old_pair=0;
            for (f=0; f<4; f=f+1)
            for (s=0; s<4; s=s+1) begin
                ft=first_order(f);st=second_order(s,fast);
                pair_previous={previous[ft][15:8],previous[st][7:0]};
                pair_current={current[ft][15:8],current[st][7:0]};
                old_valid[f*4+s]=(pair_previous[7:0]==pair_current[15:8]) &&
                    ((pair_current[15:8]&8'h1F)==8'h0D) && ((pair_current[7:0]&8'h1F)==8'h13) &&
                    pair_previous==ref_previous && pair_current==ref_current;
            end
            for (i=15; i>=0; i=i-1) if(old_valid[i]) old_pair=i;
            #1;
            if(dut.training_valid !== (|old_valid) || dut.trained_pair !== old_pair)
                $fatal(1,"Training equivalence flags=%0d masks=%0d/%0d old=%h/%h new=%h/%h",
                    flags,fmask,smask,|old_valid,old_pair,dut.training_valid,dut.trained_pair);
            if(dut.training_valid && (dut.trained_first !== ref_previous || dut.trained_second !== ref_current))
                $fatal(1,"Training must match both full reference words");
            cases=cases+1;
        end
        $display("PASS training equivalence: %0d cases",cases);
        memory_phase=1;
        cases=0;
        for (flags=0; flags<2; flags=flags+1)
        for (fmask=0; fmask<16; fmask=fmask+1)
        for (smask=0; smask<16; smask=smask+1) begin
            fast=flags!=0;
            phase=0;
            previous_reference=16'hFFFF;
            current_reference=0;
            ref_previous=16'hA55A;
            ref_current=16'h5AA5;
            for (t=0; t<4; t=t+1) begin
                previous[t]={8'hA5,8'h5A ^ ((smask & (1<<t))?8'h00:8'h01)};
                current[t]={8'h5A ^ ((fmask & (1<<t))?8'h00:8'h01),8'hA5};
            end
            pe=previous[0];pm=previous[1];pl=previous[2];pc=previous[3];
            ce=current[0];cm=current[1];cl=current[2];cc=current[3];
            old_valid=0;old_pair=0;
            for (f=0; f<4; f=f+1)
            for (s=0; s<4; s=s+1) begin
                ft=first_order(f);st=second_order(s,fast);
                old_valid[f*4+s]=({previous[ft][15:8],previous[st][7:0]}==ref_previous) &&
                               ({current[ft][15:8],current[st][7:0]}==ref_current);
            end
            for (i=15; i>=0; i=i-1) if(old_valid[i]) old_pair=i;
            #1;
            if(dut.training_valid !== (|old_valid))
                $fatal(1,"Memory training masks=%0d/%0d fast=%0d",fmask,smask,fast);
            if(dut.training_valid && (dut.trained_tap !== first_order(old_pair[3:2]) ||
                                     dut.trained_tap_second !== second_order(old_pair[1:0],fast)))
                $fatal(1,"Memory training legacy priority masks=%0d/%0d fast=%0d",fmask,smask,fast);
            if(!dut.training_valid && dut.trained_pair !== 0)
                $fatal(1,"Invalid memory training must not select a candidate");
            if(dut.training_valid && (dut.trained_first !== ref_previous || dut.trained_second !== ref_current))
                $fatal(1,"Memory training must match both complete patterns");
            cases=cases+1;
        end
        $display("PASS memory training legacy priority: %0d cases",cases);
        $finish;
    end
endmodule
