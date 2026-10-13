`timescale 1ns/1ps
module tb_plan_a_uart_paged;
    parameter integer DIVIDER = 8;
    localparam integer BIT_NS = DIVIDER * 20;
    reg clk=0, ram_clk=0, engine_clk=0, sys_clk=0, reset=1, sys_running=1;
    always #10 clk=!clk;
    always #7 ram_clk=!ram_clk;
    always #13 engine_clk=!engine_clk;
    always #17 if (sys_running) sys_clk=!sys_clk;
    wire tx, sys_sample_taken;
    wire [2:0] sys_page_select;
    reg [2:0] page_meta=0, page_sync=0;
    always @(posedge sys_clk) begin
        page_meta<=sys_page_select;
        page_sync<=page_meta;
    end
    wire [2:0] page = {page_sync[2],page_sync[2]^page_sync[1],page_sync[2]^page_sync[1]^page_sync[0]};
    wire [7:0] input_byte={page[1:0],2'b11,page[2],1'b1,2'b00};
    wire [23:0] sys_data={input_byte,13'h1420,page};
    wire [15:0] ram_data=16'h1357;
    wire [7:0] engine_data=8'hc6;
    plan_a_uart_trace #(.DIVIDER(DIVIDER),.PAGED_CPU(1)) dut(.*);
    reg [7:0] frame[0:10];
    integer valid_frames=0, invalid_sys_frames=0, last_page=-1;
    reg [7:0] previous_sequence;
    reg [2:0] stopped_gray;
    task automatic receive;
        reg [7:0] value, checksum;
        integer decoded_page;
        checksum=0;
        for (integer index=0; index<11; index=index+1) begin
            @(negedge tx);
            #(BIT_NS/2);
            if (tx!==0) $fatal(1,"Paged start bit");
            for(integer b=0;b<8;b=b+1) begin #(BIT_NS); value[b]=tx; end
            #(BIT_NS);
            if(tx!==1) $fatal(1,"Paged stop bit");
            frame[index]=value;
            checksum=checksum^value;
        end
        if(frame[0]!==8'ha6 || frame[1]!==8'h5a || checksum!==0) $fatal(1,"Paged header/checksum");
        if(frame[3][2]) begin
            decoded_page={frame[9][3],frame[9][7:6]};
            if ({frame[8],frame[7]} !== (16'ha100 | decoded_page))
                $fatal(1,"Page tag and payload disagree");
            if (last_page>=0 && decoded_page!==((last_page+1)&7))
                $fatal(1,"Valid pages out of order previous=%0d current=%0d",last_page,decoded_page);
            last_page=decoded_page;
            valid_frames=valid_frames+1;
        end else invalid_sys_frames=invalid_sys_frames+1;
    endtask
    initial begin
        #45 reset=0;
        for(integer n=0;n<18;n=n+1) receive;
        sys_running=0;
        receive;
        stopped_gray=sys_page_select;
        for(integer n=0;n<4;n=n+1) begin
            receive;
            if(frame[3][2]) $fatal(1,"Stopped SYS domain incorrectly fresh");
            if(sys_page_select!==stopped_gray) $fatal(1,"Page advanced while source pending");
        end
        sys_running=1;
        for(integer n=0;n<10;n=n+1) receive;
        if(valid_frames<24 || invalid_sys_frames<4) $fatal(1,"Insufficient page/source-stop coverage");
        $display("PASS PAGED UART divider=%0d valid=%0d invalid_sys=%0d",DIVIDER,valid_frames,invalid_sys_frames);
        $finish;
    end
    initial begin #(BIT_NS*110*50); $fatal(1,"Paged timeout"); end
endmodule
