`timescale 1ns/1ps
module tb_sh7604_slow_burst;
  parameter bit SLOW = 1;
  reg CLK=0, RST_N=0, CE_R=0, CE_F=0, FAST=0;
  reg [31:0] ca=0, ci=0, da=0;
  reg cr=0, cw=0, cb=0, dr=0, db=0;
  wire [31:0] co, dout;
  wire cbusy, dbusy;
  wire [26:0] a;
  wire cs3, rdwr;
  reg [31:0] di=0;
  reg wait_n=1;
  integer phase=0, age=0, delay_cycles=12;
  integer count=0, errors=0, cases=0, failures=0;
  integer offset=0, dram=0, port_sel=0, burst=0, fast_mode=0, latency=0;
  reg monitor=0, memory_valid=0;
  reg [26:0] memory_address=0;
  reg [31:0] start_address=0, expected=0;
  reg busy_before;
  reg [31:0] observed;

  SH7604_BSC #(.AREA_TIMIMG(SLOW ? 4'b1111 : 4'b0111)) dut (
    .CLK(CLK), .RST_N(RST_N), .CE_R(CE_R), .CE_F(CE_F), .EN(1'b1), .RES_N(1'b1),
    .CLK4_CE(1'b0), .CLK16_CE(1'b0), .CLK64_CE(1'b0), .CLK256_CE(1'b0),
    .CLK1024_CE(1'b0), .CLK2048_CE(1'b0), .CLK4096_CE(1'b0),
    .A(a), .DI(di), .DO(), .BS_N(), .CS0_N(), .CS1_N(), .CS2_N(), .CS3_N(cs3),
    .RD_WR_N(rdwr), .CE_N(), .OE_N(), .WE_N(), .RD_N(), .WAIT_N(wait_n),
    .BRLS_N(1'b1), .BGR_N(), .IVECF_N(), .RFS(), .MD(6'b001000),
    .CBUS_A(ca), .CBUS_DI(ci), .CBUS_DO(co), .CBUS_BA(4'hf), .CBUS_WE(cw),
    .CBUS_REQ(cr), .CBUS_PREREQ(cr), .CBUS_BURST(cb), .CBUS_LOCK(1'b0),
    .CBUS_BUSY(cbusy), .CBUS_ACT(),
    .DBUS_A(da), .DBUS_DI(32'd0), .DBUS_DO(dout), .DBUS_BA(4'hf),
    .DBUS_WE(1'b0), .DBUS_REQ(dr), .DBUS_BURST(db), .DBUS_LOCK(1'b0), .DBUS_BUSY(dbusy),
    .VBUS_A(4'd0), .VBUS_DO(), .VBUS_REQ(1'b0), .VBUS_BUSY(), .IRQ(), .CACK(), .BUS_RLS(), .FAST(FAST)
  );

  function automatic [31:0] word_at(input [31:0] addr);
    case (addr[3:2])
      0: word_at=32'h12345678;
      1: word_at=32'h89abcdef;
      2: word_at=32'ha55a0ff0;
      3: word_at=32'hc3695aa5;
    endcase
  endfunction

  task automatic tick;
    begin
      CE_R=(phase==0); CE_F=(phase==1);
      if (!cs3 && rdwr) begin
        if (!memory_valid || memory_address != a) begin
          memory_address=a; memory_valid=1; age=0;
        end else age=age+1;
        wait_n=(age >= 2*delay_cycles);
        di=wait_n ? word_at({5'd0,a}) : 32'd0;
      end else begin
        memory_valid=0; wait_n=1; di=0;
      end
      busy_before=port_sel ? dbusy : cbusy;
      #5; CLK=1; #1;
      if (monitor && CE_F && !busy_before) begin
        observed=port_sel ? dout : co;
        expected=word_at({start_address[31:4],start_address[3:2]+2'(count),2'b00});
        if (observed !== expected) begin
          errors=errors+1;
          $display("BAD_WORD port=%0d dram=%0d burst=%0d fast=%0d delay=%0d offset=%0d beat=%0d A=%h WAIT=%b got=%h expected=%h", port_sel,dram,burst,fast_mode,delay_cycles,offset,count,a,wait_n,observed,expected);
        end
        if (burst && !wait_n) begin
          errors=errors+1;
          $display("CONSUMED_WHILE_WAIT beat=%0d A=%h",count,a);
        end
        if (burst && a !== {start_address[26:4],start_address[3:2]+2'(count),2'b00}) begin
          errors=errors+1;
          $display("BAD_PHYSICAL_ADDRESS beat=%0d A=%h",count,a);
        end
        count=count+1;
        if (port_sel) da={da[31:4],da[3:2]+2'd1,2'b00};
        else ca={ca[31:4],ca[3:2]+2'd1,2'b00};
        if (count==(burst ? 4 : 1)) begin
          cr=0; dr=0; monitor=0;
        end
      end
      #4; CLK=0; phase=1-phase;
    end
  endtask

  task automatic reg_write(input [31:0] addr, input [31:0] value);
    begin
      while(phase!=0) tick();
      ca=addr; ci=value; cw=1; cr=1;
      tick();
      cr=0; cw=0;
      repeat(4) tick();
    end
  endtask

  task automatic run_case;
    integer loops;
    begin
      RST_N=0; cr=0; dr=0; monitor=0; ca=0; da=0;
      count=0; errors=0; memory_valid=0;
      repeat(4) tick();
      RST_N=1; FAST=fast_mode;
      repeat(8) tick();
      reg_write(32'hffffffec,32'ha55a0040);
      reg_write(32'hffffffe0,dram ? 32'ha55a03f1 : 32'ha55a03f0);
      if (dut.BCR1.DRAM != 3'(dram) || !dut.MCR.SZ) $fatal(1,"Register setup failed");
      start_address=32'h06000000+32'(offset);
      ca=start_address; da=start_address; cb=burst; db=burst;
      while(phase!=0) tick();
      if(port_sel) dr=1; else cr=1;
      // Match CACHE: only consume after the request has been registered and busy observed.
      tick();
      if (!(port_sel ? dbusy : cbusy)) $fatal(1,"Request did not register busy");
      monitor=1;
      loops=0;
      while (monitor && loops<2000) begin tick(); loops=loops+1; end
      if (monitor) begin errors=errors+1; cr=0; dr=0; monitor=0; $display("TIMEOUT count=%0d",count); end
      repeat(200) tick();
      if (dut.BUS_STATE != 0 || cbusy || dbusy) begin
        errors=errors+1; $display("DID_NOT_DRAIN state=%0d cbusy=%0d dbusy=%0d",dut.BUS_STATE,cbusy,dbusy);
      end
      cases=cases+1;
      if (errors) failures=failures+1;
      $display("CASE slow=%0d dram=%0d port=%0d burst=%0d fast=%0d delay=%0d offset=%0d words=%0d errors=%0d",SLOW,dram,port_sel,burst,fast_mode,delay_cycles,offset,count,errors);
    end
  endtask

  initial begin
    for(dram=0; dram<2; dram=dram+1)
      for(port_sel=0; port_sel<2; port_sel=port_sel+1)
        for(burst=0; burst<2; burst=burst+1)
          for(fast_mode=0; fast_mode<2; fast_mode=fast_mode+1)
            for(latency=0; latency<(SLOW ? 3 : 1); latency=latency+1)
              for(offset=0; offset<16; offset=offset+4) begin
                delay_cycles=latency==0 ? 0 : (latency==1 ? 1 : 12);
                run_case();
              end
    $display("SUMMARY slow=%0d cases=%0d failed=%0d",SLOW,cases,failures);
    if(failures) $fatal(1,"Slow-memory burst contract violated");
    $finish;
  end
endmodule
