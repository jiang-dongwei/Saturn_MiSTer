`timescale 1ns/1ps

module tb_aps6408_diag;
    reg clk=0;
    always #7.381 clk=~clk; // approximately 67.7376 MHz
    reg reset=1;
    wire [1:0] result_code;
    wire [7:0] stage_code;
    wire [23:0] failure_address;
    wire [15:0] id_word;
    wire [15:0] expected_data, actual_data;
    wire [7:0] diagnostic_leds;
    wire activity, psram_clk, psram_ce_n;
    tri [7:0] dq;
    tri dqs;
    reg [7:0] mem_dq=0;
    reg mem_dqs=0;
    reg mem_oe=0;
    assign dq = mem_oe ? mem_dq : 8'hzz;
    assign dqs = mem_oe ? mem_dqs : 1'bz;

    aps6408_diag_core #(.POWERUP_CYCLES(8), .HALF_PERIOD(8)) dut (
        .clk(clk), .reset(reset), .result_code(result_code),
        .stage_code(stage_code), .failure_address(failure_address),
        .id_word(id_word),
        .expected_data(expected_data), .actual_data(actual_data),
        .diagnostic_leds(diagnostic_leds), .activity(activity),
        .PSRAM_CLK(psram_clk), .PSRAM_CE_N(psram_ce_n),
        .PSRAM_DQ(dq), .PSRAM_DQS(dqs)
    );

    reg [15:0] memory [0:24];
    reg [7:0] instruction;
    reg [31:0] address;
    integer edge_number=-1;
    integer cell_slot;
    integer writes=0, reads=0, id_reads=0;
    integer corrupt=0, no_dqs=0, alias_bit12=0, bad_id=0;

    function integer cell_for;
        input [31:0] a;
        reg [31:0] mapped;
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
        end
    endfunction

    always @(negedge psram_ce_n) begin
        edge_number=-1;
        address=0;
        mem_oe=0;
    end
    always @(posedge psram_ce_n) mem_oe=0;

    always @(posedge psram_clk or negedge psram_clk) begin
        if (!psram_ce_n) begin
            edge_number=edge_number+1;
            case (edge_number)
                0: begin
                    instruction=dq;
                    if (dq !== 8'hA0 && dq !== 8'h20 && dq !== 8'h40)
                        $fatal(1,"bad instruction %h",dq);
                end
                2: address[31:24]=dq;
                3: address[23:16]=dq;
                4: address[15:8]=dq;
                5: begin
                    address[7:0]=dq;
                    cell_slot=cell_for(address);
                    if (instruction==8'h40) begin
                        if (address !== 32'h00000001) $fatal(1,"bad MR address %h",address);
                    end else if (cell_slot<0) $fatal(1,"bad address %h",address);
                    if (instruction!=8'hA0 && !no_dqs) begin
                        #10 mem_oe=1;
                        mem_dqs=0; // read preamble
                    end
                end
                14: begin
                    if (instruction==8'hA0) begin
                        if (dqs !== 1'b0) $fatal(1,"DM not enabled");
                        memory[cell_slot][15:8]=dq;
                        writes=writes+1;
                    end else begin
                        if (!no_dqs) begin
                            #10 mem_dq=(instruction==8'h40) ?
                                (bad_id ? 8'h16 : 8'h0D) :
                                (memory[cell_slot][15:8] ^ (corrupt ? 8'h01 : 8'h00));
                            mem_dqs=1;
                        end
                        if (instruction==8'h40) id_reads=id_reads+1;
                        else reads=reads+1;
                    end
                end
                15: begin
                    if (instruction==8'hA0) memory[cell_slot][7:0]=dq;
                    else begin
                        if (!no_dqs) begin
                            #10 mem_dq=(instruction==8'h40) ? 8'h93 : memory[cell_slot][7:0];
                            mem_dqs=0;
                        end
                    end
                end
            endcase
        end
    end

    initial begin
        corrupt=$test$plusargs("corrupt");
        no_dqs=$test$plusargs("no_dqs");
        alias_bit12=$test$plusargs("alias_bit12");
        bad_id=$test$plusargs("bad_id");
        repeat (4) @(posedge clk);
        reset=0;
        wait(result_code != 0);
        if ((no_dqs && (result_code !== 2'd2 || stage_code !== 8'hE1)) ||
            (bad_id && (result_code !== 2'd2 || stage_code !== 8'hE3 || writes != 0)) ||
            ((corrupt || alias_bit12) && (result_code !== 2'd2 || stage_code !== 8'hE2)) ||
            (!no_dqs && !bad_id && !corrupt && !alias_bit12 &&
             (result_code !== 2'd1 || id_word !== 16'h0D93 ||
              id_reads != 1 || writes != 25 || reads != 25)))
            $fatal(1,"diagnostic failed: result=%d stage=%h addr=%h exp=%h got=%h writes=%d reads=%d",
                   result_code,stage_code,failure_address,expected_data,actual_data,writes,reads);
        $display("APS6408 diagnostic scenario PASS: result=%0d stage=%h writes=%0d reads=%0d",
                 result_code,stage_code,writes,reads);
        $finish;
    end
    initial begin
        #6000000;
        $fatal(1,"diagnostic timeout");
    end
endmodule
