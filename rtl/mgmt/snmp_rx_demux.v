// Six-byte lookahead. Only the exact agent unicast MAC is diverted; every
// other frame is replayed unchanged to the existing real-time receive chain.
module snmp_rx_demux #(
 parameter [47:0] AGENT_MAC=48'h020000001001
) (
 input wire clk,rst_n,input wire [7:0] s_data,input wire s_valid,s_sop,s_last,s_error,output wire s_ready,
 output wire [7:0] rt_data,output wire rt_valid,rt_sop,rt_last,rt_error,input wire rt_ready,
 output wire [7:0] mg_data,output wire mg_valid,mg_sop,mg_last,mg_error,input wire mg_ready
);
 localparam [1:0] PREFIX=0,REPLAY=1,STREAM=2;
 reg [1:0] state;reg [47:0] prefix_data;reg [2:0] count,read_index;
 reg selected,short_last,prefix_error,prefix_sop;
 wire target_ready=selected?mg_ready:rt_ready;
 wire replay=state==REPLAY;
 wire [7:0] data=replay?(prefix_data >> ((count-1'b1-read_index)*8)):s_data;
 wire valid=rst_n && (replay || (state==STREAM && s_valid));
 wire sop=replay && read_index==0 && prefix_sop;
 wire last=replay?(short_last && read_index+1'b1==count):s_last;
 wire error=replay?prefix_error:s_error;
 assign s_ready=rst_n && (state==PREFIX || (state==STREAM && target_ready));
 assign rt_data=data;assign mg_data=data;
 assign rt_valid=valid && !selected;assign mg_valid=valid && selected;
 assign rt_sop=sop || (state==STREAM && s_sop);assign mg_sop=rt_sop;
 assign rt_last=last;assign mg_last=last;assign rt_error=error;assign mg_error=error;
 always @(posedge clk)begin
  if(!rst_n)begin state<=PREFIX;prefix_data<=0;count<=0;read_index<=0;selected<=0;short_last<=0;prefix_error<=0;prefix_sop<=0;end
  else case(state)
   PREFIX:if(s_valid && s_ready)begin
    prefix_data<={prefix_data[39:0],s_data};count<=count+1'b1;
    prefix_error<=prefix_error || s_error;
    if(count==0)prefix_sop<=s_sop;
    if(count==5 || s_last)begin
     selected<=count==5 && {prefix_data[39:0],s_data}==AGENT_MAC;
     short_last<=s_last;read_index<=0;state<=REPLAY;
    end
   end
   REPLAY:if(target_ready)begin
    if(read_index+1'b1==count)begin
     if(short_last)begin state<=PREFIX;count<=0;prefix_error<=0;end else state<=STREAM;
    end else read_index<=read_index+1'b1;
   end
   STREAM:if(s_valid && s_ready && s_last)begin state<=PREFIX;count<=0;prefix_error<=0;end
   default:state<=PREFIX;
  endcase
 end
endmodule
