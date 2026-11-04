// C32 RFC1350 octet server: one session, one 2048-byte object,512-byte blocks.
// WRITE acknowledgement waits for storage success; RRQ reads actual metadata.
module tftp_duplex_server #(
 parameter [31:0] RTO_MIN=32'd100000000,RTO_MAX=32'd800000000,DALLY_TICKS=32'd1600000000,
 parameter [3:0] RETRY_LIMIT=4'd5
) (
 input wire clk,rst_n,input wire [31:0] now,timeout_cycles,input wire cancel,
 input wire rx_context_valid,output wire rx_context_ready,input wire rx_network,
 input wire [47:0] rx_mac,input wire [31:0] rx_ip,input wire [15:0] rx_port,rx_destination,
 input wire [9:0] rx_length,input wire [7:0] rx_data,input wire rx_valid,rx_last,output wire rx_ready,output reg rx_release,
 output wire tx_cmd_valid,input wire tx_cmd_ready,output wire tx_network,
 output wire [47:0] tx_mac,output wire [31:0] tx_ip,output wire [15:0] tx_port,tx_source,
 output wire [9:0] tx_length,output wire [7:0] tx_data,output wire tx_valid,tx_last,input wire tx_ready,tx_done,tx_error,tx_line_done,
 input wire dn_allowed,dn_lna_allowed,dn_network,input wire [47:0] dn_mac,input wire [31:0] dn_ip,
 output reg lno_complete,lno_network,lna_complete,output reg [47:0] lno_mac,output reg [31:0] lno_ip,output reg [15:0] lna_size,
 input wire lur_allowed,input wire expected_network,input wire [47:0] expected_mac,input wire [31:0] expected_ip,output reg lur_complete,output reg [15:0] lur_size,input wire client_active,output reg lui_complete,output reg lui_network,output reg [47:0] lui_mac,output reg [31:0] lui_ip,output wire server_busy,output reg [3:0] store_object,output wire store_req_valid,input wire store_req_ready,output wire [2:0] store_op,
 output wire [15:0] store_offset,output wire [9:0] store_length,output wire store_final,
 output wire [7:0] store_data,output wire store_valid,store_last,input wire store_ready,
 input wire [7:0] store_read_data,input wire store_read_valid,store_read_last,output wire store_read_ready,
 input wire store_result_valid,store_error,input wire [15:0] store_size,input wire [7:0] store_flags,
 output wire store_result_ready,output reg store_cancel,output wire [511:0] diagnostics
);
 localparam [4:0] IDLE=0,COLLECT=1,DISPATCH=2,P_READ=3,P_BYTE=4,OPEN=5,OPEN_WAIT=6,
 WRITE_CMD=7,S_READ=8,S_DATA=9,WRITE_WAIT=10,TX_CMD=11,TX_DATA=12,TX_WAIT=13,
 STAT_CMD=14,STAT_WAIT=15,READ_CMD=16,READ_DATA=17,READ_WAIT=18,T_READ=19,T_DATA=20,LINE_WAIT=21;
 reg [4:0] state;wire [7:0] ram_data,cache_data;
 reg [9:0] length,index,parse_index,store_index,block_length,tx_index;
 reg [15:0] total_length,file_size,block_number,last_block;
 reg [31:0] first;reg [7:0] last_octet;reg packet_network;reg [47:0] packet_mac;reg [31:0] packet_ip;reg [15:0] packet_port,packet_destination;
 reg active,committed,finished,reading,peer_network;reg [47:0] peer_mac;reg [31:0] peer_ip;reg [15:0] peer_port,tid;
 reg [13:0] lfsr;reg [31:0] last_activity;
 reg [1:0] section;reg [5:0] chars;reg filename_ok,control_name_ok,lur_name_ok,lno_name_ok,lna_name_ok,mode_ok,request_read;
 reg reply_network;reg [47:0] reply_mac;reg [31:0] reply_ip;reg [15:0] reply_port,reply_source,reply_opcode,reply_number;reg drop_after_reply;
 reg [31:0] sessions,blocks,rejects,timeouts,duplicates,cancels,files_written,files_read;reg [7:0] last_error;
 wire initial_peer_match=packet_network==peer_network && packet_mac==peer_mac && packet_ip==peer_ip && packet_port==peer_port;
 reg timer_restart,timer_sent,timer_take,reply_progress;
 wire rto_due,rto_exhausted,rto_armed;wire [31:0] rto_interval;wire [3:0] rto_attempts;
 reg [31:0] retransmissions,retry_exhaustions;reg [7:0] timeout_reason;
 tftp_retry #(.INITIAL_TICKS(RTO_MIN),.MAX_TICKS(RTO_MAX),.MAX_RETRIES(RETRY_LIMIT)) retry_timer(
 .clk(clk),.rst_n(rst_n),.now(now),.restart(timer_restart),.stop(!active || !reading),.sent(timer_sent),.take(timer_take),
 .due(rto_due),.exhausted(rto_exhausted),.armed(rto_armed),.interval(rto_interval),.attempts(rto_attempts));
 assign server_busy=rst_n && (active || state!=IDLE);
 wire peer_match=packet_network==peer_network && packet_mac==peer_mac && packet_ip==peer_ip && packet_port==peer_port && packet_destination==tid;
 wire [31:0] age=now-last_activity;
 wire [16:0] next_total={1'b0,total_length}+{7'd0,block_length};
 assign rx_context_ready=rst_n && state==IDLE && !(active && reading && rto_due) && !(active && !reading && age>=(finished?DALLY_TICKS:timeout_cycles));assign rx_ready=rst_n && state==COLLECT;
 assign tx_cmd_valid=rst_n && state==TX_CMD;assign tx_valid=rst_n && (state==TX_DATA || state==T_DATA);
 assign tx_network=reply_network;assign tx_mac=reply_mac;assign tx_ip=reply_ip;assign tx_port=reply_port;assign tx_source=reply_source;
 assign tx_length=reply_opcode==3?block_length+10'd4:reply_opcode==4?10'd4:10'd8;
 assign tx_last=tx_index+1'b1==tx_length;
 function [7:0] reply_byte;input [9:0] p;input [15:0] op,n;begin
  case(p)0:reply_byte=op[15:8];1:reply_byte=op[7:0];2:reply_byte=n[15:8];3:reply_byte=n[7:0];
   4:reply_byte="C";5:reply_byte="3";6:reply_byte="2";default:reply_byte=0;endcase
 end endfunction
 assign tx_data=(reply_opcode==3 && tx_index>=4)?cache_data:reply_byte(tx_index,reply_opcode,reply_number);
 assign store_req_valid=rst_n && (state==OPEN || state==WRITE_CMD || state==STAT_CMD || state==READ_CMD);
 assign store_op=state==OPEN?3'd1:state==WRITE_CMD?3'd2:state==STAT_CMD?3'd4:3'd3;
 assign store_offset=(state==WRITE_CMD || state==READ_CMD)?total_length:16'd0;
 assign store_length=(state==WRITE_CMD || state==READ_CMD)?block_length:10'd0;
 assign store_final=block_length<512;
 assign store_result_ready=rst_n && (state==OPEN_WAIT || state==WRITE_WAIT || state==STAT_WAIT || state==READ_WAIT || state==READ_DATA);
 assign store_data=ram_data;assign store_valid=rst_n && state==S_DATA;assign store_last=store_index+1'b1==block_length;
 assign store_read_ready=rst_n && state==READ_DATA;
 assign diagnostics={{timeout_reason,19'd0,rto_armed,rto_attempts},rto_interval,retry_exhaustions,retransmissions,files_read,files_written,cancels,duplicates,timeouts,rejects,blocks,sessions,
  {5'd0,reading,finished,committed,last_error,total_length},{tid,13'd0,finished,committed,active},32'd0,32'd0};
 payload_buffer #(.CAPACITY(1024),.ADDR_WIDTH(10)) packet_ram(.clk(clk),
 .write_enable(rst_n && rx_valid && rx_ready && index<516),.write_addr(index),.write_data(rx_data),
 .read_enable(state==P_READ || state==S_READ),.read_addr(state==P_READ?parse_index:store_index+10'd4),.read_data(ram_data));
 payload_buffer #(.CAPACITY(512),.ADDR_WIDTH(9)) read_cache(.clk(clk),
 .write_enable(rst_n && store_read_valid && store_read_ready && store_index<512),.write_addr(store_index[8:0]),.write_data(store_read_data),
 .read_enable(state==T_READ),.read_addr(tx_index[8:0]-9'd4),.read_data(cache_data));
 task reply;input [15:0] op,n;input close_session;begin
  reply_network<=packet_network;reply_mac<=packet_mac;reply_ip<=packet_ip;reply_port<=packet_port;reply_source<=packet_destination;
  reply_progress<=0;reply_opcode<=op;reply_number<=n;tx_index<=0;drop_after_reply<=close_session;state<=TX_CMD;
  if(op==5)begin rejects<=rejects+1'b1;last_error<=n[7:0];end
 end endtask
 task send_data;begin
  reply_network<=peer_network;reply_mac<=peer_mac;reply_ip<=peer_ip;reply_port<=peer_port;reply_source<=tid;
  reply_progress<=0;reply_opcode<=3;reply_number<=block_number;tx_index<=0;drop_after_reply<=0;state<=TX_CMD;
 end endtask
 task request_complete;begin
  if(!(filename_ok || control_name_ok || lur_name_ok || lno_name_ok || lna_name_ok) || chars==0 && section==0)reply(5,1,0);
  else if(lno_name_ok && (!request_read || packet_destination!=59 || !dn_allowed))reply(5,2,0);
  else if(lna_name_ok && (request_read || packet_destination!=59 || !dn_lna_allowed || packet_network!=dn_network || packet_mac!=dn_mac || packet_ip!=dn_ip))reply(5,2,0);
  else if(lur_name_ok && (request_read || packet_destination!=59 || !lur_allowed || packet_network!=expected_network || packet_mac!=expected_mac || packet_ip!=expected_ip))reply(5,2,0);
  else if(control_name_ok && (!request_read || packet_destination!=59))reply(5,2,0);
  else if(filename_ok && packet_destination!=69)reply(5,1,0);
  else if(active && initial_peer_match && !reading && !request_read && !committed)begin
   // Lost ACK0: exact peer and fully parsed identical object/mode, same TID.
   duplicates<=duplicates+1'b1;reply(4,0,0);reply_source<=tid;
  end else if(active && initial_peer_match && reading && request_read && block_number==1)state<=IDLE;
  else if(active || (client_active && !lno_name_ok && !lna_name_ok))reply(5,0,0);
  else begin
   store_object<=lno_name_ok?4'd7:lna_name_ok?4'd9:lur_name_ok?4'd3:control_name_ok?4'd1:4'd0;peer_network<=packet_network;peer_mac<=packet_mac;peer_ip<=packet_ip;peer_port<=packet_port;
   tid<=({2'b11,lfsr}==tid)?{2'b11,(lfsr+14'd1)}:{2'b11,lfsr};last_activity<=now;
   reading<=request_read;committed<=0;finished<=0;total_length<=0;file_size<=0;last_block<=0;block_number<=1;
   state<=request_read?STAT_CMD:OPEN;
  end
 end endtask
 function [7:0] name_byte;input [5:0] n;begin
  case(n)0:name_byte="u";1:name_byte="p";2:name_byte="l";3:name_byte="o";4:name_byte="a";5:name_byte="d";6:name_byte=".";7:name_byte="b";8:name_byte="i";9:name_byte="n";default:name_byte=0;endcase
 end endfunction
 function [7:0] control_byte;input [5:0] n;begin
  case(n)0:control_byte="A";1:control_byte="F";2:control_byte="D";3:control_byte="X";4:control_byte="_";5:control_byte="0";6:control_byte="1";7:control_byte=".";8:control_byte="L";9:control_byte="U";10:control_byte="I";default:control_byte=0;endcase
 end endfunction
 function [7:0] mode_byte;input [5:0] n;begin
  case(n)0:mode_byte="o";1:mode_byte="c";2:mode_byte="t";3:mode_byte="e";4:mode_byte="t";default:mode_byte=0;endcase
 end endfunction
 always @(posedge clk)begin
  if(!rst_n)begin
   lno_complete<=0;lno_network<=0;lno_mac<=0;lno_ip<=0;lna_complete<=0;lna_size<=0;lur_complete<=0;lur_size<=0;lui_complete<=0;lui_network<=0;lui_mac<=0;lui_ip<=0;state<=IDLE;store_object<=0;control_name_ok<=0;lur_name_ok<=0;lno_name_ok<=0;lna_name_ok<=0;length<=0;index<=0;parse_index<=0;store_index<=0;block_length<=0;tx_index<=0;total_length<=0;file_size<=0;block_number<=1;last_block<=0;first<=0;last_octet<=0;
   packet_network<=0;packet_mac<=0;packet_ip<=0;packet_port<=0;packet_destination<=0;
   active<=0;committed<=0;finished<=0;reading<=0;peer_network<=0;peer_mac<=0;peer_ip<=0;peer_port<=0;tid<=0;lfsr<=14'h2a35;last_activity<=0;
   section<=0;chars<=0;filename_ok<=0;mode_ok<=0;request_read<=0;
   reply_network<=0;reply_mac<=0;reply_ip<=0;reply_port<=0;reply_source<=0;reply_opcode<=0;reply_number<=0;drop_after_reply<=0;
   sessions<=0;blocks<=0;rejects<=0;timeouts<=0;duplicates<=0;cancels<=0;files_written<=0;files_read<=0;last_error<=0;rx_release<=0;store_cancel<=0;timer_restart<=0;timer_sent<=0;timer_take<=0;reply_progress<=0;retransmissions<=0;retry_exhaustions<=0;timeout_reason<=0;
  end else begin
   lno_complete<=0;lna_complete<=0;lur_complete<=0;lui_complete<=0;rx_release<=0;store_cancel<=0;timer_restart<=0;timer_sent<=0;timer_take<=0;
   lfsr<={lfsr[12:0],lfsr[13]^lfsr[12]^lfsr[11]^lfsr[1]};
   case(state)
    IDLE:begin
     if(active && reading && rto_due)begin
      timer_take<=1;
      if(rto_exhausted)begin active<=0;committed<=0;finished<=0;store_cancel<=1;timeouts<=timeouts+1'b1;retry_exhaustions<=retry_exhaustions+1'b1;timeout_reason<=2;end
      else begin retransmissions<=retransmissions+1'b1;send_data;end
     end else if(active && !reading && age>=(finished?DALLY_TICKS:timeout_cycles))begin
      active<=0;committed<=0;finished<=0;store_cancel<=1;timeouts<=timeouts+1'b1;timeout_reason<=finished?3:1;
     end else if(rx_context_valid && rx_context_ready)begin
      packet_network<=rx_network;packet_mac<=rx_mac;packet_ip<=rx_ip;packet_port<=rx_port;packet_destination<=rx_destination;
      length<=rx_length;index<=0;first<=0;state<=COLLECT;
     end
    end
    COLLECT:if(rx_valid && rx_ready)begin
     last_octet<=rx_data;if(index<4)first<={first[23:0],rx_data};
     if(rx_last)begin rx_release<=1;
      if(index+1'b1!=length || length<4 || length>516)begin state<=IDLE;rejects<=rejects+1'b1;end else state<=DISPATCH;
     end else if(index<1023)index<=index+1'b1;
    end
    DISPATCH:begin
     if(active && packet_destination==tid && !initial_peer_match && first[31:16]!=5)reply(5,5,0);
     else if((first[31:16]==1 || first[31:16]==2) && (packet_destination==69 || packet_destination==59))begin
      if(length>512)reply(5,4,0);else begin request_read<=first[31:16]==1;parse_index<=2;section<=0;chars<=0;filename_ok<=1;control_name_ok<=1;lur_name_ok<=1;lno_name_ok<=1;lna_name_ok<=1;mode_ok<=1;state<=P_READ;end
     end else if(first[31:16]==3)begin
      if(!active || !peer_match)reply(5,5,0);
      else if(reading)begin reply(5,4,1);store_cancel<=1;end
      else if(committed && first[15:0]==last_block)begin duplicates<=duplicates+1'b1;reply(4,last_block,0);end
      else if(finished || first[15:0]!=block_number)begin duplicates<=duplicates+1'b1;state<=IDLE;end
      else if({1'b0,total_length}+{7'd0,length}-17'd4>2048)begin reply(5,3,1);store_cancel<=1;end
      else begin block_length<=length-10'd4;last_activity<=now;state<=WRITE_CMD;end
     end else if(first[31:16]==4)begin
      if(!active)state<=IDLE;
      else if(!peer_match)reply(5,5,0);
      else if(length!=4 || !reading)begin reply(5,4,1);store_cancel<=1;end
      else if(reading && length==4 && first[15:0]==block_number)begin
       timer_restart<=1;
       // A DATA sender advances once only for its current, matching ACK.
       last_activity<=now;blocks<=blocks+1'b1;total_length<=next_total[15:0];
       if(block_length<512)begin
        if(store_object==7)begin lno_complete<=1;lno_network<=peer_network;lno_mac<=peer_mac;lno_ip<=peer_ip;end
        if(store_object==1)begin lui_complete<=1;lui_network<=peer_network;lui_mac<=peer_mac;lui_ip<=peer_ip;end
        active<=0;finished<=1;files_read<=files_read+1'b1;state<=IDLE;end
       else begin block_number<=block_number+1'b1;
        block_length<=file_size-next_total[15:0]>=512?10'd512:file_size[9:0]-next_total[9:0];
        if(file_size==next_total[15:0])begin
         // A full final block is followed by zero DATA; never READ at capacity.
         send_data;reply_number<=block_number+1'b1;
        end else state<=READ_CMD;
       end
      end else begin duplicates<=duplicates+1'b1;state<=IDLE;end
      // RFC1123 4.2.3.1: no DATA retransmission for a duplicate/old ACK.
     end else if(first[31:16]==5)begin
      if(active && peer_match && length>=5 && last_octet==0)begin active<=0;committed<=0;finished<=0;cancels<=cancels+1'b1;store_cancel<=1;end
      state<=IDLE;
     end else begin reply(5,4,active && peer_match);if(active && peer_match)store_cancel<=1;end
    end
    P_READ:state<=P_BYTE;
    P_BYTE:begin
     if(ram_data==0)begin
      if(chars==0)reply(5,4,0);
      else if(section==0)begin
       if(chars!=10)filename_ok<=0;if(chars!=11)begin control_name_ok<=0;lur_name_ok<=0;lno_name_ok<=0;lna_name_ok<=0;end section<=1;chars<=0;
       if(parse_index+1'b1==length)reply(5,4,0);else begin parse_index<=parse_index+1'b1;state<=P_READ;end
      end else if(section==1)begin
       if(chars!=5 || !mode_ok)reply(5,4,0);
       else if(parse_index+1'b1==length)request_complete;
       else begin section<=2;chars<=0;parse_index<=parse_index+1'b1;state<=P_READ;end
      end else if(section==2)begin
       if(parse_index+1'b1==length)reply(5,4,0);else begin section<=3;chars<=0;parse_index<=parse_index+1'b1;state<=P_READ;end
      end else if(parse_index+1'b1==length)request_complete;
      else begin section<=2;chars<=0;parse_index<=parse_index+1'b1;state<=P_READ;end
     end else if(parse_index+1'b1==length || chars==31)reply(5,4,0);
     else begin
      if(section==0)begin if(ram_data!=name_byte(chars))filename_ok<=0;if(ram_data!=control_byte(chars))control_name_ok<=0;if(ram_data!=(chars==10?8'h52:control_byte(chars)))lur_name_ok<=0;if(ram_data!=(chars==9?8'h4e:chars==10?8'h4f:control_byte(chars)))lno_name_ok<=0;if(ram_data!=(chars==9?8'h4e:chars==10?8'h41:control_byte(chars)))lna_name_ok<=0;end
      if(section==1 && (ram_data|8'h20)!=mode_byte(chars))mode_ok<=0;
      chars<=chars+1'b1;parse_index<=parse_index+1'b1;state<=P_READ;
     end
    end

    OPEN:if(store_req_ready)state<=OPEN_WAIT;
    OPEN_WAIT:if(store_result_valid)begin
     if(store_error)reply(5,2,0);else begin active<=1;sessions<=sessions+1'b1;last_activity<=now;reply(4,0,0);reply_source<=tid;reply_progress<=1;end
    end
    WRITE_CMD:if(store_req_ready)begin store_index<=0;state<=block_length==0?WRITE_WAIT:S_READ;end
    S_READ:state<=S_DATA;
    S_DATA:if(store_ready)begin if(store_last)state<=WRITE_WAIT;else begin store_index<=store_index+1'b1;state<=S_READ;end end
    WRITE_WAIT:if(store_result_valid)begin
     if(store_error)begin reply(5,3,1);store_cancel<=1;end
     else begin
      committed<=1;finished<=block_length<512;total_length<=next_total[15:0];last_block<=block_number;block_number<=block_number+1'b1;
      blocks<=blocks+1'b1;last_activity<=now;if(block_length<512)begin files_written<=files_written+1'b1;if(store_object==3)begin lur_complete<=1;lur_size<=next_total[15:0];end if(store_object==9)begin lna_complete<=1;lna_size<=next_total[15:0];end end reply(4,block_number,0);reply_progress<=1;
     end
    end
    STAT_CMD:if(store_req_ready)state<=STAT_WAIT;
    STAT_WAIT:if(store_result_valid)begin
     if(store_error || !store_flags[0])reply(5,1,0);
     else if(!store_flags[1])reply(5,2,0);
     else if(store_size>2048)reply(5,3,0);
     else begin timer_restart<=1;active<=1;sessions<=sessions+1'b1;file_size<=store_size;block_length<=store_size>=512?10'd512:store_size[9:0];last_activity<=now;
      if(store_size==0)send_data;else state<=READ_CMD;
     end
    end
    READ_CMD:if(store_req_ready)begin store_index<=0;state<=READ_DATA;end
    READ_DATA:if(store_result_valid)reply(5,0,1);
     else if(store_read_valid && store_read_ready)begin if(store_read_last)state<=READ_WAIT;else store_index<=store_index+1'b1;end
    READ_WAIT:if(store_result_valid)begin if(store_error)reply(5,0,1);else send_data;end
    TX_CMD:if(tx_cmd_ready)begin tx_index<=0;state<=TX_DATA;end
    TX_DATA:if(tx_ready)begin
     if(tx_last)state<=TX_WAIT;else begin tx_index<=tx_index+1'b1;if(reply_opcode==3 && tx_index>=3)state<=T_READ;end
    end
    T_READ:state<=T_DATA;
    T_DATA:if(tx_ready)begin if(tx_last)state<=TX_WAIT;else begin tx_index<=tx_index+1'b1;state<=T_READ;end end
    TX_WAIT:if(tx_done)begin
     if(tx_error)begin state<=IDLE;active<=0;committed<=0;finished<=0;store_cancel<=1;end
     else state<=LINE_WAIT;
    end
    LINE_WAIT:if(tx_line_done)begin state<=IDLE;
     if(reply_progress)last_activity<=now;
     if(active && reading && reply_opcode==3)timer_sent<=1;
     if(drop_after_reply)begin active<=0;committed<=0;finished<=0;store_cancel<=1;end
    end
    default:state<=IDLE;
   endcase
   if(cancel)begin
    active<=0;committed<=0;finished<=0;cancels<=cancels+1'b1;store_cancel<=1;
    if(state==TX_CMD || state==TX_DATA || state==T_READ || state==T_DATA || state==TX_WAIT || state==LINE_WAIT)drop_after_reply<=1;
    else begin state<=IDLE;rx_release<=1;end
   end
   if((state==OPEN || state==OPEN_WAIT || state==WRITE_CMD || state==S_READ || state==S_DATA || state==WRITE_WAIT || state==STAT_CMD || state==STAT_WAIT || state==READ_CMD || state==READ_DATA || state==READ_WAIT) && age>=timeout_cycles)begin
    active<=0;committed<=0;finished<=0;state<=IDLE;store_cancel<=1;timeouts<=timeouts+1'b1;
   end
  end
 end
endmodule
