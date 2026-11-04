`timescale 1ns/1ps
// Delivery configuration is a separate module using ONLY public transactions.
module c42s_configuration(
 input wire clk,rst_n,init_done,output reg configured=0,
 output reg cfg_valid=0,cfg_write=0,output reg [1:0] cfg_kind=0,
 output reg cfg_bank=0,cfg_shadow=0,output reg [12:0] cfg_index=0,
 output reg [3:0] cfg_word=0,output reg [31:0] cfg_data=0,
 input wire cfg_ready,cfg_resp_valid,cfg_resp_error,input wire [31:0] cfg_resp_data,
 output reg cfg_resp_ready=0,cfg_commit_valid=0,cfg_result_ready=0,
 input wire cfg_commit_ready,cfg_result_valid,cfg_result_ok,input wire [2:0] cfg_result_code,
 output reg failed=0
);
 reg [31:0] words[0:39];integer p,k,index,fd;
 reg [31:0] readback;
 task write_word;input [1:0] kind;input bank,shadow;input integer idx,w;input [31:0] value;
 begin
  @(negedge clk);cfg_valid=1;cfg_write=1;cfg_kind=kind;cfg_bank=bank;cfg_shadow=shadow;cfg_index=idx;cfg_word=w;cfg_data=value;
  @(posedge clk);while(!cfg_ready)@(posedge clk);@(negedge clk);cfg_valid=0;cfg_resp_ready=1;
  @(posedge clk);while(!cfg_resp_valid)@(posedge clk);
  if(cfg_resp_error)begin failed=1;$display("C42S_CONFIGURATION_ERROR idx=%0d w=%0d",idx,w);end
  $fdisplay(fd,"WRITE kind=%0d bank=%0d index=%0d word=%0d value=%08x error=%0d time_ns=%0d",kind,bank,idx,w,value,cfg_resp_error,$time);
  @(negedge clk);cfg_resp_ready=0;
 end endtask
 task read_entry;input bank;input integer idx,w;output [31:0] value;
 begin
  @(negedge clk);cfg_valid=1;cfg_write=0;cfg_kind=0;cfg_bank=bank;cfg_shadow=0;cfg_index=idx;cfg_word=w;cfg_data=0;
  @(posedge clk);while(!cfg_ready)@(posedge clk);@(negedge clk);cfg_valid=0;cfg_resp_ready=1;
  @(posedge clk);while(!cfg_resp_valid)@(posedge clk);
  if(cfg_resp_error)failed=1;
  value=cfg_resp_data;$fdisplay(fd,"READ_CONFIG bank=%0d index=%0d word=%0d value=%08x error=%0d time_ns=%0d",bank,idx,w,value,cfg_resp_error,$time);
  @(negedge clk);cfg_resp_ready=0;
 end endtask
 task read_word;input [1:0] kind;input integer idx,w;output [31:0] value;
 begin
  @(negedge clk);cfg_valid=1;cfg_write=0;cfg_kind=kind;cfg_bank=0;cfg_shadow=0;cfg_index=idx;cfg_word=w;cfg_data=0;
  @(posedge clk);while(!cfg_ready)@(posedge clk);@(negedge clk);cfg_valid=0;cfg_resp_ready=1;
  @(posedge clk);while(!cfg_resp_valid)@(posedge clk);
  if(cfg_resp_error)begin failed=1;$display("C42S_CONFIGURATION_READ_ERROR idx=%0d w=%0d",idx,w);end
  value=cfg_resp_data;$fdisplay(fd,"READ kind=%0d index=%0d word=%0d value=%08x time_ns=%0d",kind,idx,w,value,$time);
  @(negedge clk);cfg_resp_ready=0;
 end endtask
 initial begin
  fd=$fopen("configuration.log","w");$readmemh("vectors/system/c42/config.hex",words);
  wait(rst_n);wait(init_done);
  // tag32-v3 epoch1; no storage function is emulated by this module.
  write_word(3,0,0,20,3,1);
  for(p=0;p<5;p=p+1)begin
   index=p==0?0:p==1?127:p==2?0:p==3?4095:2048;
   for(k=0;k<8;k=k+1)write_word(0,p>=2,1,index,k,words[p*8+k]);
  end
  @(negedge clk);cfg_commit_valid=1;
  @(posedge clk);while(!cfg_commit_ready)@(posedge clk);@(negedge clk);cfg_commit_valid=0;cfg_result_ready=1;
  @(posedge clk);while(!cfg_result_valid)@(posedge clk);
  if(!cfg_result_ok || cfg_result_code!=0)begin failed=1;$display("C42S_CONFIGURATION_COMMIT_ERROR code=%0d",cfg_result_code);end
  $fdisplay(fd,"COMMIT code=%0d time_ns=%0d",cfg_result_code,$time);
  @(negedge clk);cfg_result_ready=0;
  write_word(3,0,0,15,6,16'h1000);
  read_entry(0,0,7,readback);if(readback[15:0]!=1)failed=1;
  read_entry(0,127,7,readback);if(readback[15:0]!=16'h8001)failed=1;
  read_entry(1,0,7,readback);if(readback[15:0]!=1)failed=1;
  read_entry(1,2048,7,readback);if(readback[15:0]!=16'h42)failed=1;
  read_entry(1,4095,7,readback);if(readback[15:0]!=16'h8001)failed=1;
  configured=!failed;
 end
endmodule
