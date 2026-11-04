module download_port_demux (
 input wire clk,rst_n,input wire [7:0] s_data,input wire s_valid,s_sop,s_last,s_error,s_network,
 output wire s_ready,
 output wire [7:0] m_data,output wire m_sop,m_last,m_error,m_network,
 output wire snmp_valid,input wire snmp_ready,output wire time_valid,input wire time_ready,
 output wire unused_stamp
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
 assign unused_stamp=1'b0;
 assign snmp_valid=valid && !selected;assign time_valid=valid && selected;
 always @(posedge clk)begin
  if(!rst_n)begin state<=0;prefix<=0;count<=0;index<=0;selected<=0;network<=0;short_last<=0;prefix_error<=0;prefix_sop<=0;
   end
  else case(state)
   0:if(s_valid && s_ready)begin
    prefix[335-count*8-:8]<=s_data;count<=count+1'b1;prefix_error<=prefix_error || s_error;
    if(count==0)begin network<=s_network;prefix_sop<=s_sop;end
    if(count==41 || s_last)begin
     selected<=count==41 && prefix[223:216]==8'h45 && prefix[151:144]==17 && (prefix[47:32]==16'd69 || prefix[47:32]==16'd59 || (prefix[47:32]>=16'd35000 && prefix[47:32]<=16'd49151) || prefix[47:46]==2'b11);
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
