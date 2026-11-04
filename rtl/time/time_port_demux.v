// 42-byte bounded lookahead: preserve the original SNMP endpoint; divert only
// UDP45000. Timestamp is the first MAC-client destination byte ACCEPTED at
// this block, before lookahead/replay. All RTC/tag data stay in clk domain.
module time_port_demux (
 input wire clk,rst_n,input wire [7:0] s_data,input wire s_valid,s_sop,s_last,s_error,s_network,
 output wire s_ready,input wire [63:0] rtc_seconds,input wire [31:0] rtc_nanoseconds,now,generation,
 output wire [7:0] m_data,output wire m_sop,m_last,m_error,m_network,
 output wire snmp_valid,input wire snmp_ready,output wire time_valid,input wire time_ready,
 output reg [63:0] stamp_seconds,output reg [31:0] stamp_nanoseconds,stamp_tick,stamp_generation
);
 reg [1:0] state;reg [335:0] prefix;reg [5:0] count,index;
 reg selected,network,short_last,prefix_error,prefix_sop;
 wire ready=selected?time_ready:snmp_ready;
 wire valid=rst_n && (state==1 || (state==2 && s_valid));
 assign s_ready=rst_n && (state==0 || (state==2 && ready));
 assign m_data=state==1?prefix[335-index*8-:8]:s_data;
 assign m_sop=state==1?(index==0 && prefix_sop):s_sop;
 assign m_last=state==1?(short_last && index+1'b1==count):s_last;
 assign m_error=state==1?prefix_error:s_error;assign m_network=network;
 assign snmp_valid=valid && !selected;assign time_valid=valid && selected;
 always @(posedge clk)begin
  if(!rst_n)begin state<=0;prefix<=0;count<=0;index<=0;selected<=0;network<=0;short_last<=0;prefix_error<=0;prefix_sop<=0;
   stamp_seconds<=0;stamp_nanoseconds<=0;stamp_tick<=0;stamp_generation<=0;end
  else case(state)
   0:if(s_valid && s_ready)begin
    prefix[335-count*8-:8]<=s_data;count<=count+1'b1;prefix_error<=prefix_error || s_error;
    if(count==0)begin network<=s_network;prefix_sop<=s_sop;stamp_seconds<=rtc_seconds;stamp_nanoseconds<=rtc_nanoseconds;stamp_tick<=now;stamp_generation<=generation;end
    if(count==41 || s_last)begin
     selected<=count==41 && prefix[223:216]==8'h45 && prefix[151:144]==17 && prefix[47:32]==16'd45000;
     short_last<=s_last;index<=0;state<=1;
    end
   end
   1:if(ready)begin if(index+1'b1==count)begin
     if(short_last)begin state<=0;count<=0;prefix_error<=0;end else state<=2;
    end else index<=index+1'b1;end
   2:if(s_valid && s_ready && s_last)begin state<=0;count<=0;prefix_error<=0;end
   default:state<=0;
  endcase
 end
endmodule
