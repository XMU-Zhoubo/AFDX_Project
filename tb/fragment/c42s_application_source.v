`timescale 1ns/1ps
// Pure app stimulus: VLID, length, payload and framing. No configuration/network bytes.
module c42s_application_source(
 input wire clk,rst_n,configured,
 output reg cmd=0,output reg [15:0] vlid=0,length=0,
 input wire cmd_ready,output reg [7:0] data=0,output reg valid=0,sop=0,last=0,
 input wire ready,output reg commit=0,abort=0,input wire commit_ready,error_valid,
 output reg [31:0] accepted=0
);
 integer fd;initial fd=$fopen("input.log","w");
 function [7:0] pattern;input integer pos,seed;begin pattern=(pos*73+(pos>>8)*19+seed)&255;end endfunction
 task send;input integer vl,n,seed;integer j;
 begin
  wait(configured);@(negedge clk);cmd=1;vlid=vl;length=n;
  @(posedge clk);while(!cmd_ready)@(posedge clk);@(negedge clk);cmd=0;
  for(j=0;j<n;j=j+1)begin
   if(j%17==0)repeat(2)@(negedge clk);
   data=pattern(j,seed);valid=1;sop=j==0;last=j==n-1;
   if(j==0)$fdisplay(fd,"OFFER id=%0d vl=%0d length=%0d seed=%0d time_ns=%0d",accepted,vl,n,seed,$time);
   @(posedge clk);while(!ready)@(posedge clk);
   $fdisplay(fd,"ACCEPT id=%0d offset=%0d data=%02x time_ns=%0d",accepted,j,data,$time);
   @(negedge clk);valid=0;
  end
  sop=0;last=0;commit=1;
  @(posedge clk);while(!commit_ready)@(posedge clk);@(negedge clk);commit=0;accepted=accepted+1;
 end endtask
 task reject_command;input integer vl,n;
 begin
  wait(configured);@(negedge clk);cmd=1;vlid=vl;length=n;
  @(posedge clk);while(!cmd_ready)@(posedge clk);@(negedge clk);cmd=0;
  wait(error_valid);repeat(3)@(negedge clk);
 end endtask
endmodule
