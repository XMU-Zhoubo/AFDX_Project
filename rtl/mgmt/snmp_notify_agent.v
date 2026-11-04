// C26 one-in-flight SNMPv1 agent. Shared codec, 16 numeric scalar names.
// GET/GETNEXT cache real bus values; SET commits a separate candidate atomically.
module snmp_notify_agent (
 input wire clk,rst_n,
 input wire trap_valid,output wire trap_ready,input wire [31:0] trap_count,trap_ticks,input wire [15:0] trap_used,
 output wire tx_is_trap,trap_result_valid,trap_result_error,output reg [3:0] trap_result_reason,
 input wire context_valid,output wire context_ready,input wire context_network,
 input wire [47:0] context_mac,input wire [31:0] context_ip,input wire [15:0] context_port,
 input wire [7:0] s_data,input wire s_valid,s_last,output wire s_ready,output wire release_context,
 output wire stat_valid,stat_write,input wire stat_ready,output wire [12:0] stat_index,output wire [1:0] stat_kind,output wire stat_bank,output wire [3:0] stat_word,
 output wire lock_valid,lock_write,input wire lock_ready,lock_error,output wire lock_release,
 output wire cfg_commit_valid,input wire cfg_commit_ready,cfg_result_valid,cfg_result_ok,cfg_applied,input wire [2:0] cfg_result_code,input wire [15:0] cfg_version,output wire cfg_result_ready,
 output wire [127:0] set_values,input wire [15:0] response_limit,
 input wire stat_result_valid,stat_result_error,input wire [31:0] stat_data,output wire stat_result_ready,
 output wire tx_context_valid,input wire tx_context_ready,output wire tx_network,
 output wire [47:0] tx_mac,output wire [31:0] tx_ip,output wire [15:0] tx_port,output wire [9:0] tx_length,
 output wire [7:0] m_data,output wire m_valid,m_last,input wire m_ready,
 input wire tx_done_valid,tx_done_error,output wire tx_done_ready,
 output wire [351:0] diagnostics
);
 localparam [7:0] IDLE=0,REQUEST=1,HEADER=2,HEADER_GOT=3,HEADER_NEXT=4,COMM=5,COMM_GOT=6,COMM_NEXT=7,
 VB=8,FIELDS=9,FIELD_GOT=10,FIELD_NEXT=11,NAME=12,NAME_GOT=13,NAME_NEXT=14,VALUE=15,VALUE_GOT=16,VALUE_NEXT=17,VB_NEXT=18,
 AFTER_OIDS=19,SNAPSHOT=20,SNAPSHOT_RESULT=21,COUNTER=22,COUNTER_RESULT=23,FIX=24,FIX_SIZE=25,FIX_NUMBER=26,FIX_NEXT=27,
 META=28,META_INDEX=29,ENCODE=30,ENCODE_WAIT=31,TX_FEED=32,TX_WAIT=33,RELEASE=34,Q_SEND=40,Q_WAIT=41,WRITE=42,
 ABORT_ENCODER=43,DRAIN_ENCODER=44,LOOKUP=46,LOOKUP_WAIT=47,ACQUIRE=49,CACHE_DONE=50,READ_RELEASE=51,BUILD=52,CAPACITY=53,SET_COMMIT=54,SET_WAIT=55,FIX_NAME=56,FIX_ARC=57,FIX_ARC_NEXT=58,ENCODE_READY=59,TRAP_BUILD=60,TRAP_NEXT=61;
 reg [7:0] state,read_return,write_return;
 reg is_trap,prefer_trap,trap_queued;reg [5:0] trap_step;
 reg [31:0] trap_snapshot,trap_stamp;reg [15:0] trap_occupancy;
 wire choose_trap=trap_valid && (!context_valid || prefer_trap);
 assign trap_ready=rst_n && state==IDLE && choose_trap;
 assign tx_is_trap=is_trap;assign trap_result_valid=rst_n && state==RELEASE && is_trap;assign trap_result_error=!trap_queued;
 reg [11:0] address,write_address,base;reg [31:0] word,write_data;
 reg [3:0] header_index,vb_index,field,vb_count;
 reg [5:0] name_count,arc_index;
 reg [8:0] value_index,value_size;reg [7:0] value_tag;
 reg [2:0] community_index;reg name_matches;
 reg [3:0] first_error;reg [31:0] error_status;
 reg [31:0] snapshot_value,last_request;
 reg network,snapshot_seen,encoder_done,encoder_failed,restore_bindings,copy_only;
 reg [47:0] peer_mac;reg [31:0] peer_ip;reg [15:0] peer_port;
 reg [31:0] datagrams,responses,bad_ber,bad_community,unsupported,no_such_name,internal_error,released;
 reg [7:0] pdu;reg private_view,leased,apply_seen;reg [5:0] cache_index;reg [17:0] wait_count;reg [15:0] start_version;reg [9:0] request_length;reg [3:0] community_length,name_error,value_error,capacity_index;
 reg [31:0] oid[0:31],cache[0:15],staged[0:3],candidate[0:3];reg [3:0] write_mask;reg [4:0] objects[0:7];reg [31:0] value_number;
 wire [1023:0] oid_bus;genvar k;generate for(k=0;k<32;k=k+1)begin:oid_words assign oid_bus[k*32+:32]=oid[k];end endgenerate
 wire lookup_ready,lookup_valid;wire [4:0] lookup_number;
 snmp_oid_lookup lookup(.clk(clk),.rst_n(rst_n),.start_valid(state==LOOKUP),.start_ready(lookup_ready),.successor(pdu==8'ha1),.name_count(name_count),.name_arcs(oid_bus),.result_valid(lookup_valid),.result_ready(state==LOOKUP_WAIT),.number(lookup_number));
 integer reset_word;
 wire [9:0] decoded_length;wire request_valid,request_ready;wire [3:0] request_error,request_count;wire [7:0] request_pdu;
 wire q_ready,q_result_valid;wire [31:0] q_data;
 wire w_ready,encode_ready,encoded_valid,encoded_last,encode_result_valid;
 wire [7:0] encoded_data;wire [9:0] encoded_length;wire [3:0] encode_error;
 wire encoder_result_ready=state==ENCODE_WAIT || state==TX_FEED || state==TX_WAIT || state==DRAIN_ENCODER;
 snmp_codec codec(.clk(clk),.rst_n(rst_n),.dec_cancel(1'b0),.enc_cancel(state==ABORT_ENCODER),
  .s_data(s_data),.s_valid(s_valid && state==REQUEST),.s_last(s_last),.s_ready(s_ready),
  .request_valid(request_valid),.request_ready(state==REQUEST),.request_error(request_error),.request_length(decoded_length),.request_pdu(request_pdu),.request_count(request_count),
  .request_release(state==RELEASE && !is_trap),.q_valid(state==Q_SEND),.q_ready(q_ready),.q_address(address),.q_result_valid(q_result_valid),.q_result_ready(state==Q_WAIT),.q_data(q_data),
  .w_valid(state==WRITE),.w_ready(w_ready),.w_address(write_address),.w_data(write_data),
  .encode_valid(state==ENCODE),.encode_ready(encode_ready),.m_data(encoded_data),.m_valid(encoded_valid),.m_ready(state==TX_FEED && m_ready),.m_last(encoded_last),
  .encode_result_valid(encode_result_valid),.encode_result_ready(encoder_result_ready),.encode_error(encode_error),.encode_length(encoded_length));
 assign context_ready=rst_n && state==IDLE && !choose_trap;assign release_context=rst_n && state==RELEASE && !is_trap;
 assign stat_valid=rst_n && (state==SNAPSHOT || state==COUNTER);assign stat_write=state==SNAPSHOT;
 function [12:0] counter_index;input [5:0] n;begin case(n)1:counter_index=0;2:counter_index=1;3:counter_index=24;4:counter_index=25;5:counter_index=9;6:counter_index=7;11:counter_index=28;12:counter_index=29;default:counter_index=0;endcase end endfunction
 assign stat_index=state==SNAPSHOT?13'd0:counter_index(cache_index);
 assign stat_kind=state==SNAPSHOT?2'd2:(cache_index>=13?2'd3:cache_index>=7 && cache_index<=10?2'd1:2'd2);
 assign stat_bank=cache_index>=7 && cache_index<=10;
 assign stat_word=cache_index>=13?cache_index-13:cache_index==7?4'd10:cache_index==8?4'd11:cache_index==9?4'd8:cache_index==10?4'd9:4'd0;
 assign lock_valid=rst_n && state==ACQUIRE && wait_count<100000;assign lock_write=pdu==8'ha3;
 assign lock_release=rst_n && leased && (state==READ_RELEASE || state==RELEASE);
 assign cfg_commit_valid=rst_n && state==SET_COMMIT && wait_count<100000;assign cfg_result_ready=rst_n && state==SET_WAIT;
 assign set_values={candidate[3],candidate[2],candidate[1],candidate[0]};
 assign stat_result_ready=rst_n && (state==SNAPSHOT_RESULT || state==COUNTER_RESULT);
 assign tx_context_valid=rst_n && state==ENCODE_READY && encoded_valid;
 assign tx_network=network;assign tx_mac=peer_mac;assign tx_ip=peer_ip;assign tx_port=peer_port;assign tx_length=encoded_length;
 assign m_data=encoded_data;assign m_valid=rst_n && state==TX_FEED && encoded_valid;assign m_last=encoded_last;
 assign tx_done_ready=rst_n && ((state==TX_WAIT && encoder_done) || (state==TX_FEED && tx_done_error));
 assign diagnostics={released,last_request,snapshot_value,22'd0,snapshot_seen,(state!=IDLE),state,
   internal_error,no_such_name,unsupported,bad_community,bad_ber,responses,datagrams};
 function [7:0] community_byte;input priv;input [2:0] i;begin
 if(priv)case(i)0:community_byte="p";1:community_byte="r";2:community_byte="i";3:community_byte="v";4:community_byte="a";5:community_byte="t";default:community_byte="e";endcase
 else case(i)0:community_byte="p";1:community_byte="u";2:community_byte="b";3:community_byte="l";4:community_byte="i";default:community_byte="c";endcase end endfunction
 function legal_value;input [4:0] n;input [31:0] v;begin case(n)13:legal_value=v>=43 && v<=1514;14:legal_value=v<=7;15:legal_value=v>=1 && v<=700000;16:legal_value=v>=1 && v<=80000;default:legal_value=0;endcase end endfunction
 function [31:0] expected_arc;input [4:0] object_number;input [5:0] i;begin
  case(i)0:expected_arc=1;1:expected_arc=3;2:expected_arc=6;3:expected_arc=1;4:expected_arc=3;
   5:expected_arc=664;6:expected_arc=2026;7:expected_arc=1;8:expected_arc={27'd0,object_number};default:expected_arc=0;endcase
 end endfunction
 task get;input [11:0] a;input [7:0] ret;begin address<=a;read_return<=ret;state<=Q_SEND;end endtask
 task put;input [11:0] a;input [31:0] d;input [7:0] ret;begin write_address<=a;write_data<=d;write_return<=ret;state<=WRITE;end endtask
 always @(posedge clk)begin
  if(!rst_n)begin
   state<=IDLE;is_trap<=0;prefer_trap<=0;trap_queued<=0;trap_result_reason<=0;trap_step<=0;trap_snapshot<=0;trap_stamp<=0;trap_occupancy<=0;read_return<=0;write_return<=0;address<=0;write_address<=0;base<=0;word<=0;write_data<=0;
   header_index<=0;vb_index<=0;field<=0;vb_count<=0;name_count<=0;arc_index<=0;value_index<=0;value_size<=0;value_tag<=0;community_index<=0;name_matches<=0;
   first_error<=0;error_status<=0;snapshot_value<=0;last_request<=0;network<=0;snapshot_seen<=0;encoder_done<=0;encoder_failed<=0;restore_bindings<=0;copy_only<=0;peer_mac<=0;peer_ip<=0;peer_port<=0;
   pdu<=0;private_view<=0;leased<=0;apply_seen<=0;cache_index<=0;wait_count<=0;start_version<=0;request_length<=0;community_length<=0;name_error<=0;value_error<=0;capacity_index<=1;value_number<=0;write_mask<=0;
   for(reset_word=0;reset_word<16;reset_word=reset_word+1)cache[reset_word]<=0;
   for(reset_word=0;reset_word<4;reset_word=reset_word+1)begin staged[reset_word]<=0;candidate[reset_word]<=0;end
   datagrams<=0;responses<=0;bad_ber<=0;bad_community<=0;unsupported<=0;no_such_name<=0;internal_error<=0;released<=0;
  end else begin
   if(leased && cfg_applied)apply_seen<=1;
   if(encode_result_valid && encoder_result_ready)begin encoder_done<=1;encoder_failed<=encode_error!=0;end
   case(state)
    IDLE:if(trap_valid && trap_ready)begin
     is_trap<=1;prefer_trap<=0;trap_queued<=0;trap_result_reason<=0;trap_step<=0;trap_snapshot<=trap_count;trap_stamp<=trap_ticks;trap_occupancy<=trap_used;
     peer_mac<=48'h020000001002;peer_ip<=32'hc0000201;peer_port<=16'd162;network<=0;
     pdu<=8'ha4;leased<=0;first_error<=0;error_status<=0;snapshot_seen<=0;encoder_done<=0;encoder_failed<=0;restore_bindings<=0;copy_only<=0;state<=TRAP_BUILD;
    end else if(context_valid && context_ready)begin
     is_trap<=0;prefer_trap<=1;
     peer_mac<=context_mac;peer_ip<=context_ip;peer_port<=context_port;network<=context_network;datagrams<=datagrams+1'b1;
     first_error<=0;name_error<=0;value_error<=0;write_mask<=0;capacity_index<=1;error_status<=0;snapshot_seen<=0;encoder_done<=0;encoder_failed<=0;restore_bindings<=0;copy_only<=0;state<=REQUEST;
    end
    TRAP_BUILD:if(trap_step<11)begin
     case(trap_step)
      0:put(0,32'ha4,TRAP_NEXT);4:put(4,6,TRAP_NEXT);5:put(5,2,TRAP_NEXT);
      6:put(6,8,TRAP_NEXT);7:put(7,32'hc000020a,TRAP_NEXT);8:put(8,6,TRAP_NEXT);9:put(9,1,TRAP_NEXT);10:put(10,trap_stamp,TRAP_NEXT);
      default:put({6'd0,trap_step},0,TRAP_NEXT);
     endcase
    end else if(trap_step<17)put(12'd16+trap_step-11,{24'd0,community_byte(1'b0,trap_step-11)},TRAP_NEXT);
    else if(trap_step<25)put(12'd48+trap_step-17,expected_arc(0,trap_step-17),TRAP_NEXT);
    else begin
     if(trap_step<39)begin
      case(trap_step-25)
       0:put(128,10,TRAP_NEXT);1:put(129,32'h41,TRAP_NEXT);2:put(130,0,TRAP_NEXT);3:put(131,trap_snapshot,TRAP_NEXT);
       default:put(12'd132+trap_step-29,expected_arc(6,trap_step-29),TRAP_NEXT);
      endcase
     end else begin
      case(trap_step-39)
       0:put(512,10,TRAP_NEXT);1:put(513,32'h42,TRAP_NEXT);2:put(514,0,TRAP_NEXT);3:put(515,{16'd0,trap_occupancy},TRAP_NEXT);
       default:put(12'd516+trap_step-43,expected_arc(12,trap_step-43),TRAP_NEXT);
      endcase
     end
    end
    TRAP_NEXT:if(trap_step==52)state<=ENCODE;else begin trap_step<=trap_step+1'b1;state<=TRAP_BUILD;end
    REQUEST:if(request_valid)begin
     if(request_error!=0)begin bad_ber<=bad_ber+1'b1;state<=RELEASE;end
     else if(request_pdu!=8'ha0 && request_pdu!=8'ha1 && request_pdu!=8'ha3)begin unsupported<=unsupported+1'b1;state<=RELEASE;end
     else begin vb_count<=request_count;pdu<=request_pdu;request_length<=decoded_length;header_index<=0;state<=HEADER;end
    end
    HEADER:get({8'd0,header_index},HEADER_GOT);
    HEADER_GOT:begin
     if(header_index==1)last_request<=word;
     if(header_index==4)begin private_view<=word==7;community_length<=word[3:0];end
     if(header_index==4 && word!=6 && word!=7)begin bad_community<=bad_community+1'b1;state<=RELEASE;end
     else put({8'd0,header_index},header_index==0?32'ha2:(header_index==2 || header_index==3)?32'd0:word,HEADER_NEXT);
    end
    HEADER_NEXT:if(header_index==10)begin community_index<=0;state<=COMM;end
     else begin header_index<=header_index+1'b1;state<=HEADER;end
    COMM:get(12'd16+{9'd0,community_index},COMM_GOT);
    COMM_GOT:if(word!={24'd0,community_byte(private_view,community_index)})begin bad_community<=bad_community+1'b1;state<=RELEASE;end
     else put(12'd16+{9'd0,community_index},word,COMM_NEXT);
    COMM_NEXT:if(community_index+1'b1==community_length)begin vb_index<=0;state<=VB;end
     else begin community_index<=community_index+1'b1;state<=COMM;end
    VB:if(vb_index==vb_count)state<=AFTER_OIDS;
     else begin base<=12'd128+{vb_index,8'd0}+{1'b0,vb_index,7'd0};field<=0;state<=FIELDS;end
    FIELDS:get(base+{8'd0,field},FIELD_GOT);
    FIELD_GOT:begin
     if(field==0)begin name_count<=word[5:0];name_matches<=word==10;end
     if(field==1)value_tag<=word[7:0];if(field==2)value_size<=word[8:0];if(field==3)value_number<=word;
     put(base+{8'd0,field},word,FIELD_NEXT);
    end
    FIELD_NEXT:if(field==3)begin arc_index<=0;state<=NAME;end else begin field<=field+1'b1;state<=FIELDS;end
    NAME:get(base+12'd4+{6'd0,arc_index},NAME_GOT);
    NAME_GOT:begin oid[arc_index[4:0]]<=word;put(base+12'd4+{6'd0,arc_index},word,NAME_NEXT);end
    NAME_NEXT:if(arc_index+1'b1==name_count)begin
      state<=LOOKUP;
     end else begin arc_index<=arc_index+1'b1;state<=NAME;end
    LOOKUP:if(lookup_ready)state<=LOOKUP_WAIT;
    LOOKUP_WAIT:if(lookup_valid)begin
     objects[vb_index]<=lookup_number;
     if((lookup_number==0 || (pdu==8'ha3 && (!private_view || lookup_number<13))) && name_error==0)name_error<=vb_index+1'b1;
     if(pdu==8'ha3 && lookup_number>=13)begin
      if(value_tag!=2 || value_size!=0 || !legal_value(lookup_number,value_number))begin if(value_error==0)value_error<=vb_index+1'b1;end
      else if(write_mask[lookup_number-13] && staged[lookup_number-13]!=value_number)begin if(value_error==0)value_error<=vb_index+1'b1;end
      else begin staged[lookup_number-13]<=value_number;write_mask[lookup_number-13]<=1;if(lookup_number==13)capacity_index<=vb_index+1'b1;end
     end
     value_index<=0;state<=VALUE;
    end
    VALUE:if((value_tag!=6 && value_tag!=4 && value_tag!=8'h40 && value_tag!=8'h44) || value_index==value_size)state<=VB_NEXT;
     else get(base+(value_tag==6?12'd36:12'd68)+{3'd0,value_index},VALUE_GOT);
    VALUE_GOT:put(base+(value_tag==6?12'd36:12'd68)+{3'd0,value_index},word,VALUE_NEXT);
    VALUE_NEXT:begin value_index<=value_index+1'b1;state<=VALUE;end
    VB_NEXT:begin vb_index<=vb_index+1'b1;state<=VB;end
    AFTER_OIDS:if(copy_only)state<=META;
     else if(name_error!=0)begin error_status<=2;first_error<=name_error;state<=META;end
     else if(value_error!=0)begin error_status<=3;first_error<=value_error;state<=META;end
     else if(vb_count==0)state<=META;else begin wait_count<=0;state<=ACQUIRE;end
    ACQUIRE:if(lock_valid && lock_ready)begin
     if(lock_error)begin error_status<=5;first_error<=1;state<=META;end
     else begin leased<=1;start_version<=cfg_version;state<=SNAPSHOT;end
    end else if(wait_count==100000)begin error_status<=5;first_error<=1;state<=META;end else wait_count<=wait_count+1'b1;
    SNAPSHOT:if(stat_ready)state<=SNAPSHOT_RESULT;
    SNAPSHOT_RESULT:if(stat_result_valid)begin
     if(stat_result_error)begin error_status<=5;first_error<=1;state<=META;end else begin cache_index<=1;state<=COUNTER;end
    end
    COUNTER:if(stat_ready)state<=COUNTER_RESULT;
    COUNTER_RESULT:if(stat_result_valid)begin
     if(stat_result_error)begin error_status<=5;first_error<=1;state<=META;end
     else begin
      cache[cache_index-1'b1]<=(cache_index==11 || cache_index==12)?{16'd0,stat_data[15:0]}:stat_data;
      if(cache_index==3)snapshot_value<=stat_data;
      if(cache_index==16)state<=CACHE_DONE;else begin cache_index<=cache_index+1'b1;state<=COUNTER;end
     end
    end
    CACHE_DONE:begin snapshot_seen<=1;vb_index<=0;if(pdu==8'ha3)state<=BUILD;else state<=READ_RELEASE;end
    READ_RELEASE:begin leased<=0;state<=FIX;end
    BUILD:begin
     for(reset_word=0;reset_word<4;reset_word=reset_word+1)candidate[reset_word]<=write_mask[reset_word]?staged[reset_word]:cache[12+reset_word];
     state<=CAPACITY;
    end
    CAPACITY:if(candidate[0]<({22'd0,request_length}+32'd42))begin error_status<=3;first_error<=capacity_index;state<=META;end
     else if(!tx_context_ready)begin error_status<=5;first_error<=1;state<=META;end
     else begin wait_count<=0;apply_seen<=0;state<=SET_COMMIT;end
    SET_COMMIT:if(cfg_commit_valid && cfg_commit_ready)state<=SET_WAIT;
     else if(wait_count==100000)begin error_status<=5;first_error<=1;state<=META;end else wait_count<=wait_count+1'b1;
    SET_WAIT:if(cfg_result_valid)begin
     if(!cfg_result_ok || !(apply_seen || cfg_applied) || cfg_version!=start_version+16'd1)begin error_status<=cfg_result_code==3 || cfg_result_code==4?3:5;first_error<=1;end
     state<=META;
    end
    FIX:if(vb_index==vb_count)state<=META;
     else begin base<=12'd128+{vb_index,8'd0}+{1'b0,vb_index,7'd0};arc_index<=0;state<=FIX_NAME;end
    FIX_NAME:put(base,32'd10,FIX_ARC);
    FIX_ARC:put(base+12'd4+{6'd0,arc_index},expected_arc(objects[vb_index],arc_index),FIX_ARC_NEXT);
    FIX_ARC_NEXT:if(arc_index==9)state<=FIX_SIZE;else begin arc_index<=arc_index+1'b1;state<=FIX_ARC;end
    FIX_SIZE:put(base+12'd1,objects[vb_index]>=13?32'h02:objects[vb_index]>=11?32'h42:32'h41,FIX_NUMBER);
    FIX_NUMBER:put(base+12'd2,0,45);
    45:put(base+12'd3,cache[objects[vb_index]-1'b1],FIX_NEXT);
    FIX_NEXT:begin vb_index<=vb_index+1'b1;state<=FIX;end
    META:put(12'd2,error_status,META_INDEX);
    META_INDEX:put(12'd3,{28'd0,first_error},ENCODE);
    ENCODE:if(encode_ready)begin encoder_done<=0;encoder_failed<=0;state<=ENCODE_WAIT;end
    ENCODE_WAIT:if(encode_result_valid && encode_error!=0)begin internal_error<=internal_error+1'b1;if(is_trap)trap_result_reason<=2;state<=RELEASE;end
     else if(encoded_valid)begin
      if({6'd0,encoded_length}+16'd42<=response_limit)state<=ENCODE_READY;
      else if(error_status==0 && pdu!=8'ha3 && !is_trap)begin
       error_status<=1;first_error<=0;restore_bindings<=1;state<=ABORT_ENCODER;
      end else begin if(is_trap)trap_result_reason<=1;restore_bindings<=0;state<=ABORT_ENCODER;end
     end
    // Once published, valid and context cannot depend on a changing limit.
    // snmp_udp_tx/management_buffer retain C25's accept-time real recheck.
    ENCODE_READY:if(tx_context_valid && tx_context_ready)state<=TX_FEED;
    TX_FEED:if(tx_done_valid && tx_done_error)begin internal_error<=internal_error+1'b1;if(is_trap)trap_result_reason<=3;state<=ABORT_ENCODER;end
     else if(m_valid && m_ready && m_last)state<=TX_WAIT;
    TX_WAIT:if(tx_done_valid && tx_done_ready)begin
     if(tx_done_error || encoder_failed)begin internal_error<=internal_error+1'b1;if(is_trap)trap_result_reason<=4;end
     else if(is_trap)trap_queued<=1;
     else begin responses<=responses+1'b1;if(error_status==2)no_such_name<=no_such_name+1'b1;end
     state<=RELEASE;
    end
    ABORT_ENCODER:state<=DRAIN_ENCODER;
    DRAIN_ENCODER:if(encode_result_valid)begin
     if(restore_bindings)begin restore_bindings<=0;copy_only<=1;vb_index<=0;state<=VB;end
     else state<=RELEASE;
    end
    RELEASE:begin leased<=0;if(!is_trap)released<=released+1'b1;state<=IDLE;end
    Q_SEND:if(q_ready)state<=Q_WAIT;
    Q_WAIT:if(q_result_valid)begin word<=q_data;state<=read_return;end
    WRITE:if(w_ready)state<=write_return;
    default:begin internal_error<=internal_error+1'b1;state<=RELEASE;end
   endcase
  end
 end
endmodule
