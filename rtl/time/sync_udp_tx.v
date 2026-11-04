// Build a real ordinary Ethernet/IPv4/UDP response, then feed the EXISTING
// whole-frame management queue. Both checksums are calculated by C09 RTL.
module sync_udp_tx #(
 parameter [47:0] AGENT_MAC=48'h020000001001,
 parameter [31:0] AGENT_IP=32'hc000020a
) (
 input wire clk,rst_n,
 input wire cmd_valid,output wire cmd_ready,input wire cmd_network,
 input wire [47:0] cmd_mac,input wire [31:0] cmd_ip,input wire [15:0] cmd_port,input wire [9:0] cmd_length,
 input wire [7:0] s_data,input wire s_valid,s_last,output wire s_ready,
 output wire done_valid,input wire done_ready,output reg done_error,
 input wire [15:0] configured_max,
 output wire mgmt_cmd_valid,input wire mgmt_cmd_ready,output wire [15:0] mgmt_cmd_length,
 output wire [1:0] mgmt_network,
 output wire [7:0] mgmt_data,output wire mgmt_valid,mgmt_last,input wire mgmt_ready,
 output wire mgmt_commit_valid,input wire mgmt_commit_ready,output wire mgmt_abort,
 input wire mgmt_error_valid,output wire mgmt_error_ready
);
 localparam [3:0] IDLE=0,COLLECT=1,IP_CMD=2,IP_DATA=3,IP_WAIT=4,UDP_CMD=5,UDP_DATA=6,UDP_WAIT=7,
 QUEUE_CMD=8,FRAME=9,COMMIT=10,DONE=11;
 reg [3:0] state;reg [9:0] length,index;reg [15:0] frame_index,identification;
 reg [47:0] destination_mac;reg [31:0] destination_ip;reg [15:0] destination_port;
 reg network,owned;reg [15:0] ip_sum,udp_sum;
 reg [7:0] message[0:47];
 wire [15:0] udp_length={6'd0,length}+16'd8,ip_length={6'd0,length}+16'd28;
 wire [15:0] client_length={6'd0,length}+16'd42;
 wire [9:0] ram_address=state==UDP_DATA?index-10'd8:frame_index[9:0]-10'd42;
 wire [7:0] ram_data=message[ram_address[5:0]];
 // Header is an explicit function argument, including newly latched fields.
 // This gives simulation and synthesis the same full combinational dependency.
 wire [335:0] header={destination_mac,AGENT_MAC,16'h0800,8'h45,8'd0,
  ip_length,identification,16'h4000,8'd64,8'd17,ip_sum,AGENT_IP,destination_ip,
  16'd45000,destination_port,udp_length,udp_sum};
 function [7:0] header_byte;input [335:0] h;input [5:0] p;begin header_byte=h[335-p*8-:8];end endfunction
 wire ip_cmd_ready,ip_s_ready,ip_result_valid,ip_error;wire [15:0] ip_checksum;
 wire udp_cmd_ready,udp_s_ready,udp_result_valid,udp_error;wire [15:0] udp_checksum;
 checksum_ipv4 ip_generate(.clk(clk),.rst_n(rst_n),.cmd_valid(state==IP_CMD),.cmd_ready(ip_cmd_ready),.cmd_verify(1'b0),
  .s_data(header_byte(header,6'd14+index[5:0])),.s_valid(state==IP_DATA),.s_ready(ip_s_ready),.s_last(index==19),
  .m_checksum(ip_checksum),.m_valid(ip_result_valid),.m_ready(state==IP_WAIT),.m_error(ip_error),.m_verify(),.m_check_ok());
 checksum_udp #(.MAX_UDP_BYTES(56)) udp_generate(.clk(clk),.rst_n(rst_n),.cmd_valid(state==UDP_CMD),.cmd_ready(udp_cmd_ready),.cmd_verify(1'b0),
  .cmd_src_ip(AGENT_IP),.cmd_dst_ip(destination_ip),.cmd_udp_length(udp_length),
  .s_data(index<8?header_byte(header,6'd34+index[5:0]):ram_data),.s_valid(state==UDP_DATA),.s_ready(udp_s_ready),.s_last(index+1'b1==udp_length),
  .m_checksum(udp_checksum),.m_valid(udp_result_valid),.m_ready(state==UDP_WAIT),.m_error(udp_error),.m_verify(),.m_check_ok(),.m_udp_zero());
 assign cmd_ready=rst_n && state==IDLE;assign s_ready=rst_n && state==COLLECT;
 assign done_valid=rst_n && state==DONE;
 // Once offered, a command remains valid through backpressure. The real
 // management buffer revalidates active configured_max on acceptance.
 assign mgmt_cmd_valid=rst_n && state==QUEUE_CMD;
 assign mgmt_cmd_length=client_length;assign mgmt_network=network?2'd2:2'd1;
 assign mgmt_data=frame_index<42?header_byte(header,frame_index[5:0]):ram_data;
 assign mgmt_valid=rst_n && state==FRAME;assign mgmt_last=frame_index+1'b1==client_length;
 assign mgmt_commit_valid=rst_n && state==COMMIT;
 assign mgmt_abort=rst_n && state==DONE && done_error && owned;
 assign mgmt_error_ready=rst_n;
 always @(posedge clk)if(s_valid && s_ready && index<48)message[index[5:0]]<=s_data;
 task fail;begin done_error<=1;state<=DONE;end endtask
 always @(posedge clk)begin
  if(!rst_n)begin state<=IDLE;length<=0;index<=0;frame_index<=0;identification<=0;destination_mac<=0;destination_ip<=0;destination_port<=0;network<=0;owned<=0;ip_sum<=0;udp_sum<=0;done_error<=0;end
  else if(mgmt_error_valid && owned && state!=DONE)fail;
  else case(state)
   IDLE:if(cmd_valid && cmd_ready)begin
    length<=cmd_length;destination_mac<=cmd_mac;destination_ip<=cmd_ip;destination_port<=cmd_port;network<=cmd_network;
    index<=0;owned<=0;done_error<=0;ip_sum<=0;udp_sum<=0;
    if(cmd_length!=48)fail;else state<=COLLECT;
   end
   COLLECT:if(s_valid && s_ready)begin
    if(s_last!=(index+1'b1==length))fail;
    else if(s_last)begin index<=0;state<=IP_CMD;end else index<=index+1'b1;
   end
   IP_CMD:if(ip_cmd_ready)begin index<=0;state<=IP_DATA;end
   IP_DATA:if(ip_s_ready)begin if(index==19)state<=IP_WAIT;else index<=index+1'b1;end
   IP_WAIT:if(ip_result_valid)begin if(ip_error)fail;else begin ip_sum<=ip_checksum;state<=UDP_CMD;end end
   UDP_CMD:if(udp_cmd_ready)begin index<=0;state<=UDP_DATA;end
   UDP_DATA:if(udp_s_ready)begin if(index+1'b1==udp_length)state<=UDP_WAIT;else index<=index+1'b1;end
   UDP_WAIT:if(udp_result_valid)begin if(udp_error || client_length>configured_max)fail;else begin udp_sum<=udp_checksum;state<=QUEUE_CMD;end end
   QUEUE_CMD:if(mgmt_cmd_valid && mgmt_cmd_ready)begin owned<=1;frame_index<=0;state<=FRAME;end
   FRAME:if(mgmt_valid && mgmt_ready)begin if(mgmt_last)state<=COMMIT;else frame_index<=frame_index+1'b1;end
   COMMIT:if(mgmt_commit_ready)begin owned<=0;identification<=identification+1'b1;state<=DONE;end
   DONE:if(done_ready)begin state<=IDLE;owned<=0;end
   default:fail;
  endcase
 end
endmodule
