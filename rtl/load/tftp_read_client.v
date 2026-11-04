// C35 active RRQ receiver. One 512B block cache, storage-v2 success before ACK.
// Client TIDs40000..44999 are disjoint from server, SNTP and active LUS writer.
module tftp_read_client #(
 parameter [31:0] RTO_MIN=100000000,RTO_MAX=800000000,TID_HOLD_TICKS=1600000000,
 parameter [3:0] RETRY_LIMIT=5
)(
 input wire clk,rst_n,input wire [31:0] now,timeout_cycles,
 input wire start,output wire start_ready,input wire cancel,input wire network,
 input wire [47:0] mac,input wire [31:0] ip,input wire [15:0] port,
 input wire [255:0] filename,input wire [5:0] filename_length,input wire [2:0] object_id,
 input wire [31:0] crc_seed,
 output wire busy,result_valid,input wire result_ready,output reg [7:0] reason,
 output reg [15:0] result_length,result_crc16,output reg [31:0] result_crc32,
 output reg [31:0] retransmissions,blocks,ignored,
 input wire rx_context_valid,output wire rx_context_ready,input wire rx_network,
 input wire [47:0] rx_mac,input wire [31:0] rx_ip,input wire [15:0] rx_port,rx_destination,input wire [9:0] rx_length,
 input wire [7:0] rx_data,input wire rx_valid,rx_last,output wire rx_ready,output reg rx_release,
 output wire tx_cmd_valid,input wire tx_cmd_ready,output wire tx_network,
 output wire [47:0] tx_mac,output wire [31:0] tx_ip,output wire [15:0] tx_port,tx_source,
 output wire [9:0] tx_length,output wire [7:0] tx_data,output wire tx_valid,tx_last,input wire tx_ready,
 input wire tx_done,tx_error,tx_line_done,
 output wire store_req_valid,input wire store_req_ready,output wire [2:0] store_op,store_object,
 output wire [15:0] store_offset,output wire [9:0] store_length,output wire store_final,
 output wire [7:0] store_data,output wire store_valid,store_last,input wire store_ready,
 input wire store_result_valid,store_error,output wire store_result_ready,output reg store_cancel
);
 localparam IDLE=0,OPEN=1,OPEN_WAIT=2,TX_CMD=3,TX_BYTE=4,TX_WAIT=5,TX_LINE=6,WAIT_RX=7,RX=8,CHECK=9,
  WRITE_CMD=10,STORE_FETCH=11,STORE_DATA=12,STORE_WAIT=13,RESULT=14;
 reg [3:0] state;reg [47:0] peer_mac;reg [31:0] peer_ip;reg peer_net,bound;
 reg [15:0] peer_port,initial_port,source_tid,next_tid,expected_block,reply_block;
 reg [2:0] object;reg [255:0] name;reg [5:0] name_length;
 reg [15:0] total;reg [9:0] index,count,packet_length,chunk;reg [31:0] head;
 reg packet_peer,packet_bad;reg [15:0] packet_port;reg [1:0] tx_kind;reg final_ack,cancel_pending;
 reg [3:0] resume_state;reg closed_valid,packet_closed,aux_closed,closed_net;reg [47:0] closed_mac;reg [31:0] closed_ip,closed_tick;reg [15:0] closed_tid,closed_port,closed_block;reg [9:0] closed_length;
 reg [31:0] tick,epoch;reg epoch_valid,epoch_expired;
 reg [15:0] crc16;reg [31:0] crc32;
 reg restart,stop,sent,take;wire due,exhausted;wire [31:0] interval;wire [3:0] attempts;
 tftp_retry #(.INITIAL_TICKS(RTO_MIN),.MAX_TICKS(RTO_MAX),.MAX_RETRIES(RETRY_LIMIT)) retry(
 .clk(clk),.rst_n(rst_n),.now(now),.restart(restart),.stop(stop),.sent(sent),.take(take),.due(due),.exhausted(exhausted),.armed(),.interval(interval),.attempts(attempts));
 wire tid_guard=next_tid==44999 && epoch_valid && !epoch_expired && now-epoch<TID_HOLD_TICKS;
 assign start_ready=rst_n && state==IDLE && !tid_guard;
 assign busy=rst_n && state!=IDLE && state!=RESULT;
 assign result_valid=rst_n && state==RESULT;
 assign rx_context_ready=rst_n && ((state==WAIT_RX && !due) || state==IDLE) && !start && !cancel;
 assign rx_ready=rst_n && state==RX;
 wire [7:0] cache;
 payload_buffer #(.CAPACITY(512),.ADDR_WIDTH(9)) block_ram(.clk(clk),
 .write_enable(state==RX && rx_valid && rx_ready && count>=4 && count<516),.write_addr(count[8:0]-9'd4),.write_data(rx_data),
 .read_enable(state==STORE_FETCH),.read_addr(index[8:0]),.read_data(cache));
 assign store_req_valid=rst_n && (state==OPEN || state==WRITE_CMD);
 assign store_op=state==OPEN?3'd1:3'd2;assign store_object=object;
 assign store_offset=state==OPEN?16'd0:total;assign store_length=state==OPEN?10'd0:chunk;
 // Business data stays invalid pending package validation. Header may be committed.
 assign store_final=object!=0 && chunk<512;
 assign store_data=cache;assign store_valid=rst_n && state==STORE_DATA;assign store_last=index+1'b1==chunk;
 assign store_result_ready=rst_n && (state==OPEN_WAIT || state==STORE_WAIT);
 assign tx_cmd_valid=rst_n && state==TX_CMD;assign tx_valid=rst_n && state==TX_BYTE;assign tx_network=aux_closed?closed_net:peer_net;
 assign tx_mac=aux_closed?closed_mac:peer_mac;assign tx_ip=aux_closed?closed_ip:peer_ip;assign tx_source=aux_closed?closed_tid:source_tid;assign tx_port=aux_closed?closed_port:bound?peer_port:initial_port;
 assign tx_length=aux_closed?10'd4:tx_kind==0?{4'd0,name_length}+10'd9:tx_kind==1?10'd4:10'd8;
 function [7:0] rrq_byte;input [9:0] n;begin
  if(n==0)rrq_byte=0;else if(n==1)rrq_byte=1;else if(n<name_length+2)rrq_byte=name[255-(n-2)*8-:8];
  else case(n-name_length)2:rrq_byte=0;3:rrq_byte="o";4:rrq_byte="c";5:rrq_byte="t";6:rrq_byte="e";7:rrq_byte="t";default:rrq_byte=0;endcase
 end endfunction
 assign tx_data=aux_closed?(index==0?8'd0:index==1?8'd4:index==2?closed_block[15:8]:closed_block[7:0]):tx_kind==0?rrq_byte(index):index==0?8'd0:index==1?(tx_kind==1?8'd4:8'd5):index==2?reply_block[15:8]:index==3?reply_block[7:0]:index==7?8'd0:8'h45;
 assign tx_last=index+1'b1==tx_length;
 function [15:0] c16;input [15:0] a;input [7:0] b;integer j;reg [15:0] c;begin c=a^{b,8'd0};for(j=0;j<8;j=j+1)c=c[15]?(c<<1)^16'h1021:c<<1;c16=c;end endfunction
 function [31:0] c32;input [31:0] a;input [7:0] b;integer j;reg [31:0] c;begin c=a^{b,24'd0};for(j=0;j<8;j=j+1)c=c[31]?(c<<1)^32'h04c11db7:c<<1;c32=c;end endfunction
 task phase;input [3:0] s;begin state<=s;tick<=now;end endtask
 task finish;input [7:0] why;begin reason<=why;result_length<=total;result_crc16<=crc16;result_crc32<=crc32^32'hffffffff;phase(RESULT);stop<=1;
  if(why==0)begin closed_valid<=1;closed_net<=peer_net;closed_mac<=peer_mac;closed_ip<=peer_ip;closed_tick<=now;closed_tid<=source_tid;closed_port<=peer_port;closed_block<=reply_block;closed_length<=chunk+4;end store_cancel<=why!=0;end endtask
 always @(posedge clk)begin
  if(!rst_n)begin state<=IDLE;peer_mac<=0;peer_ip<=0;peer_net<=0;bound<=0;peer_port<=0;initial_port<=0;source_tid<=44999;next_tid<=44999;
   object<=0;name<=0;name_length<=0;expected_block<=1;reply_block<=0;total<=0;index<=0;count<=0;packet_length<=0;chunk<=0;head<=0;packet_peer<=0;packet_bad<=0;packet_port<=0;tx_kind<=0;final_ack<=0;cancel_pending<=0;
   resume_state<=IDLE;closed_valid<=0;packet_closed<=0;aux_closed<=0;closed_net<=0;closed_mac<=0;closed_ip<=0;closed_tick<=0;closed_tid<=0;closed_port<=0;closed_block<=0;closed_length<=0;tick<=0;epoch<=0;epoch_valid<=0;epoch_expired<=0;crc16<=16'hffff;crc32<=32'hffffffff;restart<=0;stop<=0;sent<=0;take<=0;
   reason<=0;result_length<=0;result_crc16<=0;result_crc32<=0;retransmissions<=0;blocks<=0;ignored<=0;rx_release<=0;store_cancel<=0;end
  else begin
   restart<=0;stop<=0;sent<=0;take<=0;rx_release<=0;store_cancel<=0;
   if(epoch_valid && now-epoch>=TID_HOLD_TICKS)epoch_expired<=1;
   if(closed_valid && now-closed_tick>=TID_HOLD_TICKS)closed_valid<=0;
   case(state)
    IDLE:if(start && start_ready)begin
     peer_mac<=mac;peer_ip<=ip;peer_net<=network;initial_port<=port;bound<=0;peer_port<=0;object<=object_id;name<=filename;name_length<=filename_length;
     source_tid<=next_tid;next_tid<=next_tid==40000?16'd44999:next_tid-1'b1;
     if(next_tid==44999)begin epoch<=now;epoch_valid<=1;epoch_expired<=0;end
     total<=0;expected_block<=1;aux_closed<=0;tx_kind<=0;final_ack<=0;cancel_pending<=0;crc16<=16'hffff;crc32<=crc_seed;reason<=0;restart<=1;
     if(filename_length==0 || filename_length>31 || port==0 || object_id>4)finish(1);else phase(OPEN);
    end
    else if(rx_context_valid && rx_context_ready)begin
     resume_state<=IDLE;packet_peer<=0;packet_closed<=closed_valid && rx_network==closed_net && rx_mac==closed_mac && rx_ip==closed_ip && rx_destination==closed_tid && rx_port==closed_port;
     packet_port<=rx_port;packet_length<=rx_length;packet_bad<=0;head<=0;count<=0;phase(RX);
    end
    OPEN:if(store_req_ready)phase(OPEN_WAIT);
    OPEN_WAIT:if(store_result_valid)begin if(store_error)finish(2);else phase(TX_CMD);end
    TX_CMD:if(tx_cmd_ready)begin index<=0;state<=TX_BYTE;end
    TX_BYTE:if(tx_ready)begin if(tx_last)state<=TX_WAIT;else index<=index+1'b1;end
    TX_WAIT:if(tx_done)begin if(tx_error)finish(3);else state<=TX_LINE;end
    TX_LINE:if(tx_line_done)begin
     if(cancel_pending || cancel)finish(4);
     else if(aux_closed)begin aux_closed<=0;phase(resume_state);end
     else if(final_ack)finish(0);
     else begin sent<=1;phase(WAIT_RX);end
    end
    WAIT_RX:if(due)begin take<=1;if(exhausted)finish(5);else begin retransmissions<=retransmissions+1'b1;phase(TX_CMD);end end
     else if(rx_context_valid && rx_context_ready)begin
      resume_state<=WAIT_RX;packet_closed<=closed_valid && rx_network==closed_net && rx_mac==closed_mac && rx_ip==closed_ip && rx_destination==closed_tid && rx_port==closed_port;packet_peer<=rx_network==peer_net && rx_mac==peer_mac && rx_ip==peer_ip && rx_destination==source_tid;
      packet_port<=rx_port;packet_length<=rx_length;packet_bad<=0;head<=0;count<=0;phase(RX);
     end
    RX:if(rx_valid && rx_ready)begin
     if(count<4)head<={head[23:0],rx_data};
     if(count>=516 || rx_last!=(count+1'b1==packet_length))packet_bad<=1;
     count<=count+1'b1;if(rx_last)begin rx_release<=1;state<=CHECK;end
    end
    CHECK:begin
     phase(resume_state);
     if(packet_closed && !packet_bad && count==packet_length && packet_length==closed_length && head[31:16]==3 && head[15:0]==closed_block)begin
      aux_closed<=1;phase(TX_CMD);ignored<=ignored+1'b1;
     end else if(packet_peer && !packet_bad && count==packet_length && (!bound || packet_port==peer_port))begin
      if(packet_length>=5 && head[31:16]==5)finish(6);
      else if(packet_length>=4 && packet_length<=516 && head[31:16]==3)begin
       if(head[15:0]==expected_block)begin
        if({1'b0,total}+{7'd0,packet_length}-4>(object==0?4096:512))finish(7);
        else begin peer_port<=packet_port;bound<=1;chunk<=packet_length-4;phase(WRITE_CMD);end
       end else if(head[15:0]==expected_block-1'b1 && expected_block!=1)begin
        // Re-ACK last successful block without another storage transaction.
        tx_kind<=1;reply_block<=head[15:0];phase(TX_CMD);ignored<=ignored+1'b1;
       end else ignored<=ignored+1'b1;
      end else ignored<=ignored+1'b1;
     end else ignored<=ignored+1'b1;
    end
    WRITE_CMD:if(store_req_ready)begin index<=0;phase(chunk==0?STORE_WAIT:STORE_FETCH);end
    STORE_FETCH:state<=STORE_DATA;
    STORE_DATA:if(store_ready)begin
     crc16<=c16(crc16,cache);crc32<=c32(crc32,cache);
     if(store_last)phase(STORE_WAIT);else begin index<=index+1'b1;state<=STORE_FETCH;end
    end
    STORE_WAIT:if(store_result_valid)begin
     if(store_error)finish(8);
     else begin total<=total+{6'd0,chunk};blocks<=blocks+1'b1;reply_block<=expected_block;expected_block<=expected_block+1'b1;
      tx_kind<=1;final_ack<=chunk<512;restart<=1;phase(TX_CMD);end
    end
    RESULT:if(result_ready)state<=IDLE;
    default:state<=IDLE;
   endcase
   if(cancel && busy)begin
    if(state>=TX_CMD && state<=TX_LINE)cancel_pending<=1;
    else begin if(state==RX)rx_release<=1;finish(4);end
   end
   if(busy && !(state>=TX_CMD && state<=TX_LINE) && now-tick>=timeout_cycles)begin if(state==RX)rx_release<=1;finish(9);end
  end
 end
endmodule
