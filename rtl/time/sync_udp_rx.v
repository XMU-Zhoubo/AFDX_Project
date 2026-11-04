// Ordinary, non-AFDX IPv4/UDP management endpoint. MAC already checked FCS.
// One whole datagram context; while owned, drain/drop other management frames.
module sync_udp_rx #(
 parameter [47:0] AGENT_MAC=48'h020000001001,
 parameter [31:0] AGENT_IP=32'hc000020a
) (
 input wire clk,rst_n,
 input wire [7:0] s_data,input wire s_valid,s_sop,s_last,s_error,s_network,output wire s_ready,
 output wire context_valid,input wire context_ready,output wire context_network,
 output wire [47:0] context_mac,output wire [31:0] context_ip,output wire [15:0] context_port,
 output wire [9:0] context_length,
 input wire [63:0] stamp_seconds,input wire [31:0] stamp_nanoseconds,stamp_tick,stamp_generation,
 output reg [63:0] context_seconds,output reg [31:0] context_nanoseconds,context_tick,context_generation,
 output wire [7:0] m_data,output wire m_valid,m_last,input wire m_ready,input wire release_valid,
 output reg [31:0] count_good,count_bad,count_busy,output reg [3:0] last_reason,output wire idle
);
 localparam [3:0] IDLE=0,COLLECT=1,CHECK=2,IP_CMD=3,IP_DATA=4,IP_WAIT=5,
 UDP_CMD=6,UDP_DATA=7,UDP_WAIT=8,CONTEXT=9,PAYLOAD=10,HELD=11;
 reg [3:0] state;reg [335:0] header;reg [10:0] frame_count;
 reg frame_error,network,discarding;reg [9:0] out_index,check_index;
 reg [7:0] payload[0:47];
 wire [15:0] ip_length=header[207:192],udp_length=header[31:16];
 wire [31:0] source_ip=header[127:96];
 wire [15:0] expected_frame=ip_length+16'd14;
 wire [9:0] payload_length=udp_length[9:0]-10'd8;
 wire [9:0] ram_address=state==UDP_DATA?check_index-10'd8:out_index;
 wire [7:0] ram_data=payload[ram_address[5:0]];
 function [7:0] header_byte;input [335:0] h;input [5:0] index;begin header_byte=h[335-index*8-:8];end endfunction
 wire ip_cmd_ready,ip_s_ready,ip_m_valid,ip_m_error,ip_ok;
 wire udp_cmd_ready,udp_s_ready,udp_m_valid,udp_m_error,udp_ok,udp_zero;
 checksum_ipv4 ip_check(.clk(clk),.rst_n(rst_n),.cmd_valid(state==IP_CMD),.cmd_ready(ip_cmd_ready),.cmd_verify(1'b1),
  .s_data(header_byte(header,6'd14+check_index[5:0])),.s_valid(state==IP_DATA),.s_ready(ip_s_ready),.s_last(check_index==19),
  .m_checksum(),.m_valid(ip_m_valid),.m_ready(state==IP_WAIT),.m_error(ip_m_error),.m_verify(),.m_check_ok(ip_ok));
 checksum_udp #(.MAX_UDP_BYTES(56)) udp_check(.clk(clk),.rst_n(rst_n),.cmd_valid(state==UDP_CMD),.cmd_ready(udp_cmd_ready),.cmd_verify(1'b1),
  .cmd_src_ip(source_ip),.cmd_dst_ip(AGENT_IP),.cmd_udp_length(udp_length),
  .s_data(check_index<8?header_byte(header,6'd34+check_index[5:0]):ram_data),.s_valid(state==UDP_DATA),.s_ready(udp_s_ready),.s_last(check_index+1'b1==udp_length),
  .m_checksum(),.m_valid(udp_m_valid),.m_ready(state==UDP_WAIT),.m_error(udp_m_error),.m_verify(),.m_check_ok(udp_ok),.m_udp_zero(udp_zero));
 assign s_ready=rst_n;
 assign context_valid=rst_n && state==CONTEXT;
 assign context_network=network;assign context_mac=header[287:240];
 assign context_ip=source_ip;assign context_port=header[63:48];assign context_length=payload_length;
 assign m_data=ram_data;assign m_valid=rst_n && state==PAYLOAD;assign m_last=out_index+1'b1==payload_length;
 assign idle=rst_n && state==IDLE && !discarding;
 always @(posedge clk)if(rst_n && state==COLLECT && s_valid && s_ready && frame_count>=42 && frame_count<90)
  payload[frame_count-11'd42]<=s_data;
 task reject;input [3:0] reason;begin count_bad<=count_bad+1'b1;last_reason<=reason;state<=IDLE;end endtask
 always @(posedge clk)begin
  if(!rst_n)begin state<=IDLE;header<=0;frame_count<=0;frame_error<=0;network<=0;discarding<=0;out_index<=0;check_index<=0;
   context_seconds<=0;context_nanoseconds<=0;context_tick<=0;context_generation<=0;count_good<=0;count_bad<=0;count_busy<=0;last_reason<=0;end
  else begin
   // This independent drain cannot overwrite the occupied datagram or context.
   if(s_valid && s_ready && state!=COLLECT && (state!=IDLE || discarding))begin
    if(s_last)begin count_busy<=count_busy+1'b1;discarding<=0;end else discarding<=1;
   end
   case(state)
    IDLE:if(s_valid && s_ready && !discarding)begin
     context_seconds<=stamp_seconds;context_nanoseconds<=stamp_nanoseconds;context_tick<=stamp_tick;context_generation<=stamp_generation;
     header<={328'd0,s_data};frame_count<=1;frame_error<=s_error || !s_sop;network<=s_network;
     state<=s_last?CHECK:COLLECT;
    end
    COLLECT:if(s_valid && s_ready)begin
     if(frame_count<42)header<={header[327:0],s_data};
     if(frame_count<1024)frame_count<=frame_count+1'b1;
     frame_error<=frame_error || s_error || s_sop || frame_count>=1024;
     if(s_last)state<=CHECK;
    end
    CHECK:begin
     if(frame_error || frame_count<60 || header[335:288]!=AGENT_MAC || header[239:224]!=16'h0800 ||
       header[223:216]!=8'h45 || header[175] || header[173:160]!=0 || header[159:152]==0 || header[151:144]!=17 ||
       header[95:64]!=AGENT_IP || source_ip==0 || source_ip==32'hffffffff || source_ip[31:28]>=14 ||
       header[287:240]==0 || header[287:240]==48'hffffffffffff || header[280] || header[63:48]==0 || header[47:32]!=45000)
       reject(1);
     else if(udp_length!=56 || ip_length!={1'b0,udp_length}+17'd20 ||
       frame_count!=(expected_frame<60?16'd60:expected_frame))reject(2);
     else begin check_index<=0;state<=IP_CMD;end
    end
    IP_CMD:if(ip_cmd_ready)begin check_index<=0;state<=IP_DATA;end
    IP_DATA:if(ip_s_ready)begin if(check_index==19)state<=IP_WAIT;else check_index<=check_index+1'b1;end
    IP_WAIT:if(ip_m_valid)begin if(ip_m_error || !ip_ok)reject(3);else state<=UDP_CMD;end
    UDP_CMD:if(udp_cmd_ready)begin check_index<=0;state<=UDP_DATA;end
    UDP_DATA:if(udp_s_ready)begin if(check_index+1'b1==udp_length)state<=UDP_WAIT;else check_index<=check_index+1'b1;end
    UDP_WAIT:if(udp_m_valid)begin if(udp_m_error || (!udp_ok && !udp_zero))reject(4);else state<=CONTEXT;end
    CONTEXT:if(context_ready)begin count_good<=count_good+1'b1;out_index<=0;state<=PAYLOAD;end
    PAYLOAD:if(m_ready)begin if(m_last)state<=HELD;else out_index<=out_index+1'b1;end
    HELD:if(release_valid)state<=IDLE;
    default:state<=IDLE;
   endcase
  end
 end
endmodule
