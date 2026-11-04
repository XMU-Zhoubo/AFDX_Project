// C34 independent transparent TFTP WRQ client. Not a LUS serializer or a
// completed 615A operation. The file is STAT/READ through storage-v2.
// Client TIDs45001..49151 are disjoint from SNTP45000/server49152..65535.
module tftp_write_client #(
 parameter [31:0] RTO_MIN=32'd100000000,RTO_MAX=32'd800000000,
 parameter [3:0] RETRY_LIMIT=4'd5,
 parameter [15:0] TID_LOW=16'd45001,TID_HIGH=16'd49151,
 parameter [31:0] TID_HOLD_TICKS=32'd1600000000
) (
 input wire clk,rst_n,input wire [31:0] now,timeout_cycles,input wire start_blocked,
 input wire h_valid,h_write,input wire [9:0] h_address,input wire [31:0] h_data,
 output wire h_ready,output reg h_result_valid,input wire h_result_ready,
 output reg h_error,output reg [31:0] h_result,output wire busy,
 input wire rx_context_valid,output wire rx_context_ready,input wire rx_network,
 input wire [47:0] rx_mac,input wire [31:0] rx_ip,input wire [15:0] rx_port,rx_destination,input wire [9:0] rx_length,
 input wire [7:0] rx_data,input wire rx_valid,rx_last,output wire rx_ready,output reg rx_release,
 output wire tx_cmd_valid,input wire tx_cmd_ready,output wire tx_network,
 output wire [47:0] tx_mac,output wire [31:0] tx_ip,output wire [15:0] tx_port,tx_source,
 output wire [9:0] tx_length,output wire [7:0] tx_data,output wire tx_valid,tx_last,input wire tx_ready,
 input wire tx_done,tx_error,tx_line_done,
 output wire store_req_valid,input wire store_req_ready,output wire [2:0] store_op,
 output wire store_object,output wire [15:0] store_offset,output wire [9:0] store_length,
 input wire [15:0] store_size,input wire [7:0] store_flags,store_data,input wire store_valid,store_last,
 output wire store_ready,input wire store_result_valid,store_error,output wire store_result_ready,
 output reg store_cancel
);
 localparam [4:0] IDLE=0,STAT=1,STAT_WAIT=2,READ_CMD=3,READ_DATA=4,READ_WAIT=5,
  TX_CMD=6,TX_BYTE=7,TX_READ=8,TX_WAIT=9,TX_LINE=10,WAIT_ACK=11,RX=12,RX_CHECK=13,RESULT=14;
 reg [4:0] state;reg [7:0] reason;reg cancelled,done;
 reg [31:0] cfg_ip;reg [47:0] cfg_mac;reg [15:0] cfg_port;
 reg cfg_network,cfg_object;reg [5:0] cfg_name_length;reg [255:0] cfg_name;
 reg [31:0] peer_ip;reg [47:0] peer_mac;reg [15:0] peer_port,initial_port;
 reg network,object_id,bound;reg [5:0] name_length;reg [255:0] name;
 reg [15:0] file_size,offset,block;reg [9:0] chunk,index,received;
 reg [15:0] source_tid,next_tid;reg [31:0] tid_epoch;reg tid_epoch_valid,tid_expired;
 wire tid_guard=next_tid==TID_HIGH && tid_epoch_valid && !tid_expired && now-tid_epoch<TID_HOLD_TICKS;
 reg kind,auxiliary;reg [15:0] auxiliary_port;
 reg [31:0] phase_tick,rx_head;reg [9:0] rx_count,packet_length;
 reg packet_peer,packet_session;reg [15:0] packet_port;reg packet_bad;
 reg [31:0] completed,failed,retransmitted,confirmed_bytes,confirmed_blocks,ignored,starts;
 reg retry_restart,retry_stop,retry_sent,retry_take;
 wire retry_due,retry_exhausted,retry_armed;wire [31:0] retry_interval;wire [3:0] retry_attempts;
 tftp_retry #(.INITIAL_TICKS(RTO_MIN),.MAX_TICKS(RTO_MAX),.MAX_RETRIES(RETRY_LIMIT)) retry(
  .clk(clk),.rst_n(rst_n),.now(now),.restart(retry_restart),.stop(retry_stop),.sent(retry_sent),.take(retry_take),
  .due(retry_due),.exhausted(retry_exhausted),.armed(retry_armed),.interval(retry_interval),.attempts(retry_attempts));
 wire [7:0] cached;
 payload_buffer #(.CAPACITY(512),.ADDR_WIDTH(9)) cache(.clk(clk),
  .write_enable(rst_n && state==READ_DATA && store_valid && store_ready && received<chunk),
  .write_addr(received[8:0]),.write_data(store_data),.read_enable(state==TX_READ),
  .read_addr(index[8:0]-9'd4),.read_data(cached));
 wire tx_phase=state>=TX_CMD && state<=TX_LINE;
 assign busy=rst_n && state!=IDLE && state!=RESULT;
 assign h_ready=rst_n && !h_result_valid;
 wire host_cancel=h_valid && h_ready && h_write && h_address==0 && h_data==2;
 wire host_start=h_valid && h_ready && h_write && h_address==0 && h_data==1;
 assign rx_context_ready=rst_n && ((state==WAIT_ACK && !retry_due) || state==IDLE || state==RESULT) && !host_start && !host_cancel;
 assign rx_ready=rst_n && state==RX;
 assign store_req_valid=rst_n && (state==STAT || state==READ_CMD);
 assign store_op=state==STAT?3'd4:3'd3;
 assign store_object=object_id;assign store_offset=offset;assign store_length=state==STAT?10'd0:chunk;
 assign store_ready=rst_n && state==READ_DATA;
 assign store_result_ready=rst_n && (state==STAT_WAIT || state==READ_WAIT || state==READ_DATA);
 assign tx_cmd_valid=rst_n && state==TX_CMD;assign tx_network=network;assign tx_mac=peer_mac;assign tx_ip=peer_ip;
 assign tx_port=auxiliary?auxiliary_port:(bound?peer_port:initial_port);assign tx_source=source_tid;
 assign tx_length=auxiliary?10'd16:kind?chunk+10'd4:{4'd0,name_length}+10'd9;
 function [7:0] request_byte;input [9:0] n;input [255:0] text;input [5:0] size;begin
  if(n==0)request_byte=0;else if(n==1)request_byte=2;
  else if(n<size+2)request_byte=text[255-(n-2)*8-:8];
  else case(n-size)2:request_byte=0;3:request_byte="o";4:request_byte="c";5:request_byte="t";6:request_byte="e";7:request_byte="t";default:request_byte=0;endcase
 end endfunction
 function [7:0] error_byte;input [9:0] n;begin
  case(n)1:error_byte=5;3:error_byte=5;4:error_byte="U";5:error_byte="n";6:error_byte="k";7:error_byte="n";8:error_byte="o";9:error_byte="w";10:error_byte="n";11:error_byte=" ";12:error_byte="T";13:error_byte="I";14:error_byte="D";default:error_byte=0;endcase
 end endfunction
 assign tx_data=auxiliary?error_byte(index):!kind?request_byte(index,name,name_length):
  index==0?8'd0:index==1?8'd3:index==2?block[15:8]:index==3?block[7:0]:cached;
 assign tx_valid=rst_n && state==TX_BYTE;assign tx_last=index+1'b1==tx_length;
 integer n;reg config_ok;
 always @* begin
  config_ok=cfg_port!=0 && cfg_ip!=0 && cfg_ip!=32'hffffffff && cfg_ip[31:28]<14 && cfg_mac!=0 && !cfg_mac[40] && cfg_name_length>0 && cfg_name_length<=31;
  for(n=0;n<32;n=n+1)if(n<cfg_name_length && cfg_name[255-n*8-:8]==0)config_ok=0;
 end
 wire phase_expired=busy && !tx_phase && state!=WAIT_ACK && now-phase_tick>=timeout_cycles;
 task finish;input [7:0] why;reg [7:0] final_reason;begin
  // One effective disposition, even when finalACK and accepted cancellation
  // or phase expiry coincide. Never count both success and failure.
  final_reason=phase_expired?8'd9:(host_cancel && busy)?8'd5:why;
  state<=RESULT;reason<=final_reason;done<=1;cancelled<=0;retry_stop<=1;store_cancel<=1;
  if(final_reason==0)completed<=completed+1'b1;else failed<=failed+1'b1;
 end endtask
 task phase;input [4:0] next;begin state<=next;phase_tick<=now;end endtask
 task next_chunk;input [15:0] remain;begin
  chunk<=remain>=512?10'd512:remain[9:0];received<=0;
  if(remain==0)phase(TX_CMD);else phase(READ_CMD);
 end endtask
 always @(posedge clk)begin
  if(!rst_n)begin
   state<=IDLE;reason<=0;cancelled<=0;done<=0;h_result_valid<=0;h_error<=0;h_result<=0;
   cfg_ip<=32'hc0000214;cfg_mac<=48'h020000001003;cfg_port<=69;cfg_network<=0;cfg_object<=0;
   cfg_name_length<=10;cfg_name<={"client.bin",176'd0};
   peer_ip<=0;peer_mac<=0;peer_port<=0;initial_port<=0;network<=0;object_id<=0;bound<=0;name_length<=0;name<=0;
   file_size<=0;offset<=0;block<=0;chunk<=0;index<=0;received<=0;kind<=0;auxiliary<=0;auxiliary_port<=0;
   source_tid<=TID_HIGH;next_tid<=TID_HIGH;tid_epoch<=0;tid_epoch_valid<=0;tid_expired<=0;
   phase_tick<=0;rx_head<=0;rx_count<=0;packet_length<=0;packet_peer<=0;packet_session<=0;packet_port<=0;packet_bad<=0;
   completed<=0;failed<=0;retransmitted<=0;confirmed_bytes<=0;confirmed_blocks<=0;ignored<=0;starts<=0;
   retry_restart<=0;retry_stop<=0;retry_sent<=0;retry_take<=0;store_cancel<=0;rx_release<=0;
  end else begin
   retry_restart<=0;retry_stop<=0;retry_sent<=0;retry_take<=0;store_cancel<=0;rx_release<=0;
   if(tid_epoch_valid && now-tid_epoch>=TID_HOLD_TICKS)tid_expired<=1;
   if(h_result_valid && h_result_ready)h_result_valid<=0;
   if(h_valid && h_ready)begin
    h_result_valid<=1;h_error<=0;h_result<=0;
    if(h_write)begin
     if(h_address==0)begin
      if(h_data==2)begin if(!busy)h_error<=1;end
      else if(h_data==1)begin
       if(busy || start_blocked || !config_ok || tid_guard)h_error<=1;
       else begin
        peer_ip<=cfg_ip;peer_mac<=cfg_mac;initial_port<=cfg_port;network<=cfg_network;object_id<=cfg_object;
        name<=cfg_name;name_length<=cfg_name_length;bound<=0;peer_port<=0;kind<=0;auxiliary<=0;done<=0;reason<=0;cancelled<=0;
        offset<=0;block<=0;chunk<=0;index<=0;received<=0;retry_restart<=1;starts<=starts+1'b1;phase(STAT);
        source_tid<=next_tid;next_tid<=next_tid==TID_LOW?TID_HIGH:next_tid-1'b1;
        if(next_tid==TID_HIGH)begin tid_epoch<=now;tid_epoch_valid<=1;tid_expired<=0;end
       end
      end else h_error<=1;
     end else if(busy)h_error<=1;
     else case(h_address)
      1:cfg_ip<=h_data;
      2:cfg_mac[31:0]<=h_data;
      3:if(h_data[31:16]!=0)h_error<=1;else cfg_mac[47:32]<=h_data[15:0];
      4:if(h_data[31:16]!=0 || h_data[15:0]==0)h_error<=1;else cfg_port<=h_data[15:0];
      5:if(h_data[31:14]!=0 || h_data[7:2]!=0)h_error<=1;else begin cfg_name_length<=h_data[13:8];cfg_network<=h_data[0];cfg_object<=h_data[1];end
      8,9,10,11,12,13,14,15:cfg_name[255-(h_address-8)*32-:32]<=h_data;
      default:h_error<=1;
     endcase
    end else case(h_address)
     0:h_result<={11'd0,state,reason,6'd0,done,busy};
     1:h_result<=cfg_ip;2:h_result<=cfg_mac[31:0];3:h_result<={16'd0,cfg_mac[47:32]};4:h_result<={16'd0,cfg_port};
     5:h_result<={18'd0,cfg_name_length,6'd0,cfg_object,cfg_network};
     8,9,10,11,12,13,14,15:h_result<=cfg_name[255-(h_address-8)*32-:32];
     16:h_result<=completed;17:h_result<=failed;18:h_result<=retransmitted;19:h_result<=confirmed_bytes;
     20:h_result<=confirmed_blocks;21:h_result<=ignored;22:h_result<=starts;
     23:h_result<={file_size,offset};24:h_result<={16'd0,peer_port};25:h_result<=retry_interval;
     26:h_result<={27'd0,retry_armed,retry_attempts};
     27:h_result<={source_tid,next_tid};28:h_result<={31'd0,tid_guard};
     default:h_error<=1;
    endcase
   end
   case(state)
    IDLE,RESULT:if(rx_context_valid && rx_context_ready)begin
     packet_session<=0;rx_count<=0;rx_head<=0;packet_length<=rx_length;packet_bad<=0;phase(RX);
    end
    STAT:if(store_req_ready)phase(STAT_WAIT);
    STAT_WAIT:if(store_result_valid)begin
     if(store_error || (store_flags & 3)!=3 || store_size>(object_id?512:2048))finish(2);
     else begin file_size<=store_size;index<=0;phase(TX_CMD);end
    end
    READ_CMD:if(store_req_ready)begin received<=0;phase(READ_DATA);end
    READ_DATA:begin
     if(store_result_valid)finish(3);
     else if(store_valid && store_ready)begin
      if(received>=chunk || store_last!=(received+1'b1==chunk))finish(3);
      else begin received<=received+1'b1;if(store_last)phase(READ_WAIT);end
     end
    end
    READ_WAIT:if(store_result_valid)begin if(store_error || received!=chunk)finish(3);else begin index<=0;phase(TX_CMD);end end
    TX_CMD:if(tx_cmd_ready)begin index<=0;state<=TX_BYTE;end
    TX_BYTE:if(tx_valid && tx_ready)begin
     if(tx_last)state<=TX_WAIT;
     else begin index<=index+1'b1;if(kind && !auxiliary && index>=3)state<=TX_READ;end
    end
    TX_READ:state<=TX_BYTE;
    TX_WAIT:if(tx_done)begin if(tx_error)finish(4);else state<=TX_LINE;end
    TX_LINE:if(tx_line_done)begin
     if(cancelled || host_cancel)finish(5);
     else begin if(!auxiliary)retry_sent<=1;auxiliary<=0;phase(WAIT_ACK);end
    end
    WAIT_ACK:begin
     if(retry_due)begin
      retry_take<=1;
      if(retry_exhausted)finish(6);
      else begin retransmitted<=retransmitted+1'b1;index<=0;auxiliary<=0;phase(TX_CMD);end
     end else if(rx_context_valid && rx_context_ready)begin
      packet_session<=1;packet_peer<=rx_network==network && rx_mac==peer_mac && rx_ip==peer_ip && rx_destination==source_tid;
      packet_port<=rx_port;packet_length<=rx_length;rx_count<=0;rx_head<=0;packet_bad<=0;phase(RX);
     end
    end
    RX:if(rx_valid && rx_ready)begin
     if(rx_count<4)rx_head<={rx_head[23:0],rx_data};
     if(rx_count>=516 || rx_last!=(rx_count+1'b1==packet_length))packet_bad<=1;
     rx_count<=rx_count+1'b1;
     if(rx_last)begin rx_release<=1;state<=RX_CHECK;end
    end
    RX_CHECK:begin
     phase(packet_session?WAIT_ACK:(done?RESULT:IDLE));
     if(packet_session && packet_peer && !packet_bad && rx_count==packet_length)begin
      if(bound && packet_port!=peer_port)begin auxiliary<=1;auxiliary_port<=packet_port;index<=0;phase(TX_CMD);end
      else if(packet_length>=5 && rx_head[31:16]==5)finish(7);
      else if(packet_length==4 && rx_head[31:16]==4 && rx_head[15:0]==block)begin
       retry_restart<=1;
       if(!kind)begin peer_port<=packet_port;bound<=1;kind<=1;block<=1;next_chunk(file_size);end
       else begin
        confirmed_bytes<=confirmed_bytes+{22'd0,chunk};confirmed_blocks<=confirmed_blocks+1'b1;
        if(chunk<512)finish(0);
        else begin offset<=offset+{6'd0,chunk};block<=block+1'b1;next_chunk(file_size-offset-{6'd0,chunk});end
       end
      end else ignored<=ignored+1'b1;
     end else ignored<=ignored+1'b1;
    end
    default:finish(8);
   endcase
   // A command/data already offered to the shared encoder is completed once;
   // cancellation then waits for its physical line completion. No replay and
   // no success result. Unbounded downstream blockage has no finite guarantee.
   if(host_cancel && busy)begin
    if(tx_phase)cancelled<=1;
    else begin if(state==RX)rx_release<=1;finish(5);end
   end
   if(phase_expired)begin
    if(state==RX)rx_release<=1;finish(9);
   end
  end
 end
endmodule
