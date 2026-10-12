`timescale 1ns/1ps
module tb_sh7604_cache_slow_burst;
  parameter bit SLOW=1;
  reg CLK=0,RST_N=0,CE_R=0,CE_F=0,FAST=0;
  reg [31:0] cpu_a=0,cpu_di=0,reg_a=0,reg_di=0;
  reg cpu_req=0,cpu_wr=0,reg_req=0,config_mode=1;
  wire [31:0] cpu_do,ia,idi,idout;
  wire [3:0] iba;
  wire iwe,ireq,ipre,iburst,ilock,iwait,cpu_busy;
  wire [26:0] a;
  wire cs3,rdwr;
  reg [31:0] di=0;
  reg wait_n=1;
  integer phase=0,age=0,delay_cycles=0,offset=0,fast_mode=0,dram=0,latency=0;
  integer errors=0,failures=0,cases=0,writes=0;
  reg memory_valid=0,monitor=0;
  reg [26:0] memory_address=0;
  reg [31:0] line_address=0;
  reg [3:0] seen=0;

  SH7604_CACHE cache(.CLK(CLK),.RST_N(RST_N),.CE_R(CE_R),.CE_F(CE_F),.EN(1'b1),.RES_N(1'b1),
    .CBUS_A(cpu_a),.CBUS_DI(cpu_di),.CBUS_DO(cpu_do),.CBUS_WR(cpu_wr),.CBUS_BA(4'hf),
    .CBUS_REQ(cpu_req),.CBUS_ID(1'b0),.CBUS_TAS(1'b0),.CBUS_BUSY(cpu_busy),
    .IBUS_A(ia),.IBUS_DI(idi),.IBUS_DO(idout),.IBUS_BA(iba),.IBUS_WE(iwe),
    .IBUS_REQ(ireq),.IBUS_PREREQ(ipre),.IBUS_BURST(iburst),.IBUS_LOCK(ilock),.IBUS_WAIT(iwait));

  SH7604_BSC #(.AREA_TIMIMG(SLOW?4'b1111:4'b0111)) bsc(
    .CLK(CLK),.RST_N(RST_N),.CE_R(CE_R),.CE_F(CE_F),.EN(1'b1),.RES_N(1'b1),
    .CLK4_CE(1'b0),.CLK16_CE(1'b0),.CLK64_CE(1'b0),.CLK256_CE(1'b0),.CLK1024_CE(1'b0),.CLK2048_CE(1'b0),.CLK4096_CE(1'b0),
    .A(a),.DI(di),.DO(),.BS_N(),.CS0_N(),.CS1_N(),.CS2_N(),.CS3_N(cs3),.RD_WR_N(rdwr),
    .CE_N(),.OE_N(),.WE_N(),.RD_N(),.WAIT_N(wait_n),.BRLS_N(1'b1),.BGR_N(),.IVECF_N(),.RFS(),.MD(6'b001000),
    .CBUS_A(config_mode?reg_a:ia),.CBUS_DI(config_mode?reg_di:idout),.CBUS_DO(idi),.CBUS_BA(config_mode?4'hf:iba),
    .CBUS_WE(config_mode?reg_req:iwe),.CBUS_REQ(config_mode?reg_req:ireq),.CBUS_PREREQ(config_mode?reg_req:ipre),
    .CBUS_BURST(config_mode?1'b0:iburst),.CBUS_LOCK(config_mode?1'b0:ilock),.CBUS_BUSY(iwait),.CBUS_ACT(),
    .DBUS_A(32'd0),.DBUS_DI(32'd0),.DBUS_DO(),.DBUS_BA(4'd0),.DBUS_WE(1'b0),.DBUS_REQ(1'b0),.DBUS_BURST(1'b0),.DBUS_LOCK(1'b0),.DBUS_BUSY(),
    .VBUS_A(4'd0),.VBUS_DO(),.VBUS_REQ(1'b0),.VBUS_BUSY(),.IRQ(),.CACK(),.BUS_RLS(),.FAST(FAST));

  function automatic [31:0] word_at(input [31:0] addr);
    word_at=32'ha55a1357 ^ addr ^ (32'h01020304 * (32'(addr[3:2])+1));
  endfunction

  task automatic tick;
    reg [31:0] write_address;
    begin
      CE_R=(phase==0); CE_F=(phase==1);
      if(!cs3 && rdwr) begin
        if(!memory_valid || memory_address!=a) begin memory_address=a; memory_valid=1; age=0; end
        else age=age+1;
        wait_n=age>=2*(delay_cycles+(latency==3 ? 3*integer'(a[3:2]) : 0));
        di=wait_n?word_at({5'd0,a}):32'd0;
      end else begin memory_valid=0; wait_n=1; di=0; end
      if(monitor && CE_R && cache.CACHE_UPDATE) begin
        write_address={3'd0,cache.CACHE_WR_ADDR,2'b00};
        if(write_address[31:4]!=line_address[31:4] || seen[write_address[3:2]] || idi!==word_at(write_address)) begin
          errors=errors+1;
          $display("CACHE_BAD_WRITE addr=%h got=%h expected=%h seen=%h",write_address,idi,word_at(write_address),seen);
        end
        seen[write_address[3:2]]=1; writes=writes+1;
      end
      #5; CLK=1; #1;
      #4; CLK=0; phase=1-phase;
    end
  endtask

  task automatic reg_write(input [31:0] addr,value);
    begin
      while(phase!=0) tick();
      reg_a=addr; reg_di=value; reg_req=1; tick(); reg_req=0; repeat(4) tick();
    end
  endtask

  task automatic read_cpu(input [31:0] addr,input bit expect_hit);
    integer loops;
    begin
      cpu_a=addr; repeat(4) tick();
      if(expect_hit && !cache.HIT) begin errors=errors+1; $display("CACHE_NOT_HIT addr=%h",addr); end
      if(!expect_hit && cache.HIT) begin errors=errors+1; $display("CACHE_UNEXPECTED_HIT addr=%h",addr); end
      while(phase!=1) tick();
      cpu_req=1; cpu_wr=0; tick();
      loops=0;
      while(cpu_busy && loops<3000) begin tick(); loops=loops+1; end
      if(cpu_busy || cpu_do!==word_at(addr)) begin
        errors=errors+1; $display("CPU_BAD_READ addr=%h got=%h expected=%h busy=%b",addr,cpu_do,word_at(addr),cpu_busy);
      end
      if(expect_hit && ireq) begin errors=errors+1; $display("CACHE_HIT_EXTERNAL_REQUEST"); end
      cpu_req=0; repeat(12) tick();
    end
  endtask

  task automatic run_case;
    begin
      RST_N=0; cpu_req=0; reg_req=0; monitor=0; config_mode=1;
      errors=0; writes=0; seen=0; memory_valid=0;
      repeat(4) tick(); RST_N=1; FAST=fast_mode; repeat(8) tick();
      reg_write(32'hffffffec,32'ha55a0040);
      reg_write(32'hffffffe0,dram?32'ha55a03f1:32'ha55a03f0);
      config_mode=0;
      while(phase!=0) tick();
      cpu_a=32'hfffffe92; cpu_di=1; cpu_wr=1; cpu_req=1; tick(); cpu_wr=0; cpu_req=0; repeat(6) tick();
      if(!cache.CCR.CE) $fatal(1,"Cache did not enable");
      line_address=32'h06000120; monitor=1;
      read_cpu(line_address+32'(offset),0);
      if(writes!=4 || seen!=4'hf) begin errors=errors+1; $display("CACHE_FILL_COUNT writes=%0d seen=%h",writes,seen); end
      for(integer i=0;i<4;i=i+1) read_cpu(line_address+32'(i*4),1);
      if(writes!=4) begin errors=errors+1; $display("CACHE_REFILLED_HIT writes=%0d",writes); end
      line_address=32'h06004120; writes=0; seen=0;
      read_cpu(line_address+32'(offset),0);
      if(writes!=4 || seen!=4'hf) begin errors=errors+1; $display("CACHE_NEW_TAG_FILL_COUNT"); end
      for(integer i=0;i<4;i=i+1) read_cpu(line_address+32'(i*4),1);
      if(writes!=4) begin errors=errors+1; $display("CACHE_NEW_TAG_REFILLED_HIT"); end
      monitor=0;
      if(bsc.BUS_STATE!=0 || ireq || iwait) begin errors=errors+1; $display("CACHE_NOT_IDLE"); end
      cases=cases+1; if(errors) failures=failures+1;
      $display("CACHE_CASE dram=%0d fast=%0d delay=%0d offset=%0d writes=%0d errors=%0d",dram,fast_mode,delay_cycles,offset,writes,errors);
    end
  endtask

  initial begin
    for(dram=0;dram<2;dram=dram+1)
      for(fast_mode=0;fast_mode<2;fast_mode=fast_mode+1)
        for(latency=0;latency<(SLOW?4:1);latency=latency+1)
          for(offset=0;offset<16;offset=offset+4) begin
            delay_cycles=latency==0?0:(latency==1?1:12); run_case();
          end
    $display("CACHE_SUMMARY slow=%0d cases=%0d failed=%0d",SLOW,cases,failures);
    if(failures) $fatal(1,"Cache slow burst integration failed");
    $finish;
  end
endmodule
