`timescale 1ns/1ps
module CACHE_RAM(input wrclock, rdclock, input [9:0] wraddress,rdaddress,
                 input [7:0] data, input wren, output [7:0] q);
  reg [7:0] mem[0:1023]; reg [9:0] r=0;
  initial for(integer i=0;i<1024;i=i+1) mem[i]=0;
  always @(posedge wrclock) if(wren) mem[wraddress]<=data;
  always @(posedge rdclock) r<=rdaddress;
  assign q=mem[r];
endmodule
module CACHE_TAG(input clock, input [5:0] wraddress,rdaddress,
                 input [18:0] data, input wren, output [18:0] q);
  reg [18:0] mem[0:63]; reg [5:0] r=0;
  initial for(integer i=0;i<64;i=i+1) mem[i]=0;
  always @(posedge clock) if(wren) mem[wraddress]<=data;
  always @(negedge clock) r<=rdaddress;
  assign q=mem[r];
endmodule
module CACHE_VALID(input clock, input [5:0] wraddress,rdaddress,
                   input data,wren, output q);
  reg mem[0:63]; reg [5:0] r=0;
  initial for(integer i=0;i<64;i=i+1) mem[i]=0;
  always @(posedge clock) if(wren) mem[wraddress]<=data;
  always @(negedge clock) r<=rdaddress;
  assign q=mem[r];
endmodule
module CACHE_LRU(input clock, input [5:0] wraddress,rdaddress,
                 input [5:0] data, input wren, output [5:0] q);
  reg [5:0] mem[0:63]; reg [5:0] r=0;
  initial for(integer i=0;i<64;i=i+1) mem[i]=0;
  always @(posedge clock) if(wren) mem[wraddress]<=data;
  always @(negedge clock) r<=rdaddress;
  assign q=mem[r];
endmodule
