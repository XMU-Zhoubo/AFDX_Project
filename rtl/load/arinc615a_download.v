// One A4 operator-defined download, two catalog entries, one selected file.
// Data comes only from the tagged storage interface. Separate data/status
// TFTP contexts share the outer encoder/MAC and disjoint guarded TID ranges.
module arinc615a_download #(
 parameter [31:0] RTO_MIN=100000000,RTO_MAX=800000000,parameter [3:0] RETRY_LIMIT=5
)(
 input wire clk,rst_n,input wire [31:0] now,timeout_cycles,input wire start_allowed,
 input wire lno_complete,lno_network,input wire [47:0] lno_mac,input wire [31:0] lno_ip,
 input wire lna_complete,input wire [15:0] lna_size,
 output wire lno_allowed,lna_allowed,output wire busy,output wire network,output wire [47:0] mac,output wire [31:0] ip,
 input wire h_valid,h_write,input wire [9:0] h_address,input wire [31:0] h_data,
 output wire h_ready,output reg h_result_valid,input wire h_result_ready,output reg h_error,output reg [31:0] h_result,
 output wire notice_owned,output wire [3:0] notice_object,
 output wire client_valid,client_write,output wire [9:0] client_address,output wire [31:0] client_data,
 input wire client_ready,client_result_valid,client_error,input wire [31:0] client_result,output wire client_take,input wire writer_busy,
 input wire rx_context_valid,output wire rx_context_ready,input wire rx_network,input wire [47:0] rx_mac,
 input wire [31:0] rx_ip,input wire [15:0] rx_port,rx_destination,input wire [9:0] rx_length,
 input wire [7:0] rx_data,input wire rx_valid,rx_last,output wire rx_ready,rx_release,
 output wire tx_cmd_valid,input wire tx_cmd_ready,output wire tx_network,output wire [47:0] tx_mac,
 output wire [31:0] tx_ip,output wire [15:0] tx_port,tx_source,output wire [9:0] tx_length,
 output wire [7:0] tx_data,output wire tx_valid,tx_last,input wire tx_ready,tx_done,tx_error,tx_line_done,
 output wire req_valid,input wire req_ready,output wire [2:0] req_op,output wire [3:0] req_object,
 output wire [16:0] req_offset,output wire [9:0] req_length,output wire req_final,
 output wire [7:0] s_data,output wire s_valid,s_last,input wire s_ready,
 input wire [7:0] m_data,input wire m_valid,m_last,output wire m_ready,
 input wire result_valid,result_error,input wire [16:0] result_size,input wire [7:0] result_flags,
 output wire result_ready,cancel
);
 localparam IDLE=0,PREPARE=1,ARMED=2,ACCEPTED=3,LIST=4,ANSWER=5,ASTAT=6,ASTATWAIT=7,
  AREAD=8,ADATA=9,AREADWAIT=10,LOCK=11,LOCKWAIT=12,CONFIG=13,CONFIGWAIT=14,
  POLL=15,POLLWAIT=16,SIZE=17,SIZEWAIT=18,UNLOCK=19,UNLOCKWAIT=20,FINAL=21,DONE=22,FAILED=23,CANCELLING=24;
 reg [4:0] state;reg [3:0] step;reg net,selected,has_file,leased,stopping,cancel_sent,file_confirmed;
 reg [47:0] peer_mac;reg [31:0] peer_ip;reg [7:0] reason;
 reg [31:0] started,period,deadline,last_status,successes,failures,cancellations,data_successes,notifications,notify_failures;
 reg [16:0] length;reg [15:0] counter;reg [9:0] answer_size,answer_index;
 reg [31:0] acc;reg bad,match_small,match_big;
 reg pending,file_inflight;reg [1:0] file_kind,inflight_kind;reg [15:0] status,inflight_status;reg [6:0] ratio;
 wire f_ready,f_busy,f_result;wire [7:0] f_reason;wire f_req,f_req_ready,f_take,f_store_take,f_cancel,f_valid,f_last,f_sready;
 wire [2:0] f_op;wire [9:0] f_length;wire [7:0] f_data;wire [3:0] f_object;
 wire w_ready,w_result,w_error,w_busy,w_req,w_req_ready,w_take,w_store_take,w_read_ready,w_cancel;
 wire [31:0] w_value;wire [2:0] w_op;wire [3:0] w_object;wire [16:0] w_offset;wire [9:0] w_length;
 reg [1:0] storage_owner;reg storage_owned;reg [2:0] held_ctrl_op;
 wire ctrl_req=state==ASTAT || state==AREAD || state==LOCK || state==UNLOCK;
 wire [1:0] choice=ctrl_req?2'd0:f_req?2'd1:2'd2;
 wire ctrl_take=state==ASTATWAIT || state==AREADWAIT || state==LOCKWAIT || state==UNLOCKWAIT || state==CANCELLING;
 wire ctrl_ready=req_ready && req_valid && choice==0;
 wire ctrl_result=result_valid && storage_owned && storage_owner==0;
 wire ctrl_read=storage_owned && storage_owner==0 && m_valid;
 wire f_store_result=result_valid && storage_owned && storage_owner==1;
 wire w_store_result=result_valid && storage_owned && storage_owner==2;
 assign req_valid=rst_n && !storage_owned && (ctrl_req || f_req || w_req);
 assign req_op=choice==0?(state==ASTAT?3'd4:state==AREAD?3'd3:state==LOCK?3'd6:3'd7):choice==1?f_op:w_op;
 assign req_object=choice==0?(state==ASTAT || state==AREAD?4'd9:selected?4'd6:4'd5):choice==1?f_object:w_object;
 assign req_offset=choice==2?w_offset:17'd0;assign req_length=choice==0?(state==AREAD?answer_size:10'd0):choice==1?f_length:w_length;
 assign req_final=choice==1;assign f_req_ready=req_ready && req_valid && choice==1;assign w_req_ready=req_ready && req_valid && choice==2;
 assign s_data=f_data;assign s_valid=storage_owned && storage_owner==1 && f_valid;assign s_last=f_last;
 assign f_sready=s_ready && storage_owned && storage_owner==1;
 assign m_ready=storage_owned && (storage_owner==0?(state==ADATA || state==CANCELLING):storage_owner==2?w_read_ready:1'b0);
 assign result_ready=storage_owned && (storage_owner==0?ctrl_take:storage_owner==1?f_store_take:w_store_take);
 assign cancel=storage_owned && ((storage_owner==1 && f_cancel) || (storage_owner==2 && w_cancel));
 always @(posedge clk)begin
  if(!rst_n)begin storage_owner<=0;storage_owned<=0;held_ctrl_op<=0;end
  else begin
   if((result_valid && result_ready) || cancel)storage_owned<=0;
   if(req_valid && req_ready)begin storage_owned<=1;storage_owner<=choice;if(choice==0)held_ctrl_op<=req_op;end
  end
 end
 wire file_start=pending && f_ready && !stopping;
 assign f_take=file_inflight && f_result;
 arinc615a_download_files files(.clk(clk),.rst_n(rst_n),.now(now),.deadline(timeout_cycles),
  .start(file_start),.ready(f_ready),.cancel(stopping),.kind(file_kind),.selected(selected),.has_file(has_file),
  .network(net),.mac(peer_mac),.ip(peer_ip),.counter(counter),.status(status),.ratio(ratio),
  .busy(f_busy),.result_valid(f_result),.result_ready(f_take),.reason(f_reason),
  .client_owned(notice_owned),.client_valid(client_valid),.client_write(client_write),.client_address(client_address),.client_data(client_data),
  .client_ready(client_ready),.client_result_valid(client_result_valid),.client_error(client_error),.client_result(client_result),.client_take(client_take),.writer_busy(writer_busy),
  .object_id(f_object),.req_valid(f_req),.req_ready(f_req_ready),.req_op(f_op),.req_length(f_length),
  .s_data(f_data),.s_valid(f_valid),.s_last(f_last),.s_ready(f_sready),.store_result(f_store_result),.store_error(result_error),.store_take(f_store_take),.store_cancel(f_cancel));
 assign notice_object=f_object;
 wire w_valid=state==CONFIG || state==POLL || state==SIZE || (state==CANCELLING && !cancel_sent && w_busy);
 wire w_write=state==CONFIG || state==CANCELLING;
 wire [9:0] w_address=state==POLL || state==CANCELLING?10'd0:state==SIZE?10'd30:
  step==0?10'd1:step==1?10'd2:step==2?10'd3:step==3?10'd4:step==4?10'd5:step==5?10'd8:step==6?10'd9:step==7?10'd10:step==8?10'd29:10'd0;
 wire [31:0] w_data=state==CANCELLING?32'd2:step==0?peer_ip:step==1?peer_mac[31:0]:step==2?{16'd0,peer_mac[47:32]}:
  step==3?32'd59:step==4?{18'd0,6'd9,7'd0,net}:step==5?(selected?32'h42494736:32'h534d414c):
  step==6?(selected?32'h342e4249:32'h4c2e4249):step==7?32'h4e000000:step==8?(selected?32'd6:32'd5):32'd1;
 assign w_take=state==CONFIGWAIT || state==POLLWAIT || state==SIZEWAIT || state==CANCELLING;
 tftp_download_client #(.RTO_MIN(RTO_MIN),.RTO_MAX(RTO_MAX),.RETRY_LIMIT(RETRY_LIMIT)) data_sender(
  .clk(clk),.rst_n(rst_n),.now(now),.timeout_cycles(timeout_cycles),.start_blocked(1'b0),
  .h_valid(w_valid),.h_write(w_write),.h_address(w_address),.h_data(w_data),.h_ready(w_ready),.h_result_valid(w_result),.h_result_ready(w_take),.h_error(w_error),.h_result(w_value),.busy(w_busy),
  .rx_context_valid(rx_context_valid),.rx_context_ready(rx_context_ready),.rx_network(rx_network),.rx_mac(rx_mac),.rx_ip(rx_ip),.rx_port(rx_port),.rx_destination(rx_destination),.rx_length(rx_length),
  .rx_data(rx_data),.rx_valid(rx_valid),.rx_last(rx_last),.rx_ready(rx_ready),.rx_release(rx_release),
  .tx_cmd_valid(tx_cmd_valid),.tx_cmd_ready(tx_cmd_ready),.tx_network(tx_network),.tx_mac(tx_mac),.tx_ip(tx_ip),.tx_port(tx_port),.tx_source(tx_source),.tx_length(tx_length),
  .tx_data(tx_data),.tx_valid(tx_valid),.tx_last(tx_last),.tx_ready(tx_ready),.tx_done(tx_done),.tx_error(tx_error),.tx_line_done(tx_line_done),
  .store_req_valid(w_req),.store_req_ready(w_req_ready),.store_op(w_op),.store_object(w_object),.store_offset(w_offset),.store_length(w_length),
  .store_size(result_size),.store_flags(result_flags),.store_data(m_data),.store_valid(m_valid && storage_owned && storage_owner==2),.store_last(m_last),.store_ready(w_read_ready),
  .store_result_valid(w_store_result),.store_error(result_error),.store_result_ready(w_store_take),.store_cancel(w_cancel));
 assign busy=rst_n && state!=IDLE && state!=DONE && state!=FAILED;
 assign lno_allowed=rst_n && state==ARMED;assign lna_allowed=rst_n && state==ANSWER;
 assign network=net;assign mac=peer_mac;assign ip=peer_ip;assign h_ready=rst_n && !h_result_valid;
 wire host_start=h_valid && h_ready && h_write && h_address==0 && h_data==1;
 wire host_cancel=h_valid && h_ready && h_write && h_address==0 && h_data==2;
 wire expired=busy && now-started>=deadline;
 function [7:0] fname;input big;input [3:0] n;reg [71:0] v;begin v=big?"BIG64.BIN":"SMALL.BIN";fname=n<9?v[71-n*8-:8]:8'd0;end endfunction
 task terminal;input [7:0] why;begin
  reason<=why;status<=16'h1003;ratio<=0;file_kind<=2;pending<=1;failures<=failures+1'b1;state<=FINAL;
 end endtask
 always @(posedge clk)begin
  if(!rst_n)begin
   state<=IDLE;step<=0;net<=0;selected<=0;has_file<=0;leased<=0;stopping<=0;cancel_sent<=0;file_confirmed<=0;peer_mac<=0;peer_ip<=0;reason<=0;
   started<=0;period<=100000000;deadline<=2000000000;last_status<=0;successes<=0;failures<=0;cancellations<=0;data_successes<=0;notifications<=0;notify_failures<=0;
   length<=0;counter<=1;answer_size<=0;answer_index<=0;acc<=0;bad<=0;match_small<=0;match_big<=0;
   pending<=0;file_inflight<=0;file_kind<=0;inflight_kind<=0;status<=1;inflight_status<=0;ratio<=0;
   h_result_valid<=0;h_error<=0;h_result<=0;
  end else begin
   if(h_result_valid && h_result_ready)h_result_valid<=0;
   if(h_valid && h_ready)begin
    h_result_valid<=1;h_error<=0;h_result<=0;
    if(h_write)case(h_address)
     0:if(h_data==1)begin
      if(busy || !start_allowed || !f_ready || w_busy || storage_owned)h_error<=1;
      else begin state<=PREPARE;file_kind<=0;pending<=1;started<=now;reason<=0;has_file<=0;selected<=0;length<=0;stopping<=0;cancel_sent<=0;file_confirmed<=0;status<=1;ratio<=0;end
     end else if(h_data!=2 || !busy)h_error<=1;
     1:if(busy || h_data<1000 || h_data>2000000000)h_error<=1;else period<=h_data;
     2:if(busy || h_data<1000 || h_data>2000000000)h_error<=1;else deadline<=h_data;
     default:h_error<=1;
    endcase
    else case(h_address)
     0:h_result<={16'd0,reason,3'd0,state};1:h_result<={26'd0,leased,has_file,selected,state==DONE,file_confirmed,busy};
     2:h_result<=successes;3:h_result<=failures;4:h_result<=cancellations;5:h_result<={15'd0,length};
     6:h_result<=data_successes;7:h_result<=notifications;8:h_result<=notify_failures;9:h_result<={16'd0,counter};10:h_result<=period;11:h_result<=deadline;
     default:h_error<=1;
    endcase
   end
   if(file_start)begin
    pending<=0;file_inflight<=1;inflight_kind<=file_kind;inflight_status<=status;
    if(file_kind==2)begin counter<=counter+1'b1;last_status<=now;end
   end
   if(f_take)begin
    file_inflight<=0;
    if(f_reason!=0 && !stopping)begin reason<=20;notify_failures<=notify_failures+1'b1;stopping<=1;pending<=0;state<=CANCELLING;end
    else if(!stopping)begin
     if(inflight_kind!=0)notifications<=notifications+1'b1;
     if(state==PREPARE && inflight_kind==0)state<=ARMED;
     else if(state==ACCEPTED && inflight_kind==2)begin state<=LIST;file_kind<=1;pending<=1;end
     else if(state==LIST && inflight_kind==1)state<=ANSWER;
     else if(state==FINAL && inflight_kind==2 && inflight_status==status && !pending)begin
      if(leased)state<=UNLOCK;
      else begin state<=status==3?DONE:FAILED;if(status==3)successes<=successes+1'b1;end
     end
    end
   end
   // Periodic status is coalesced while a previous immutable snapshot is sent.
   if((state==ANSWER || (state>=LOCK && state<=SIZEWAIT)) && !pending && !file_inflight && now-last_status>=period)begin file_kind<=2;status<=2;ratio<=0;pending<=1;end
   case(state)
    ARMED:if(lno_complete)begin net<=lno_network;peer_mac<=lno_mac;peer_ip<=lno_ip;started<=now;status<=1;file_kind<=2;ratio<=0;pending<=1;state<=ACCEPTED;end
    ANSWER:if(lna_complete)begin answer_size<=lna_size[9:0];state<=ASTAT;end
    ASTAT:if(ctrl_ready)state<=ASTATWAIT;
    ASTATWAIT:if(ctrl_result)begin
     if(result_error || !result_flags[0] || result_size!=19 || answer_size!=19)terminal(1);
     else begin answer_index<=0;acc<=0;bad<=0;match_small<=1;match_big<=1;state<=AREAD;end
    end
    AREAD:if(ctrl_ready)state<=ADATA;
    ADATA:if(ctrl_read && m_ready)begin
     if(answer_index<4)acc<={acc[23:0],m_data};
     if(answer_index==4 && (acc!=19 || m_data!="A"))bad<=1;
     if(answer_index==5 && m_data!="4")bad<=1;
     if((answer_index==6 && m_data!=0) || (answer_index==7 && m_data!=1) || (answer_index==8 && m_data!=10) || (answer_index==18 && m_data!=0))bad<=1;
     if(answer_index>=9 && answer_index<18)begin
      if(m_data!=fname(0,answer_index-9))match_small<=0;if(m_data!=fname(1,answer_index-9))match_big<=0;
     end
     answer_index<=answer_index+1'b1;if(m_last)state<=AREADWAIT;
    end
    AREADWAIT:if(ctrl_result)begin
     if(result_error || bad || answer_index!=19 || !(match_small || match_big))terminal(2);
     else begin selected<=match_big;has_file<=1;status<=2;ratio<=0;file_kind<=2;pending<=1;state<=LOCK;end
    end
    LOCK:if(ctrl_ready)begin leased<=1;state<=LOCKWAIT;end
    LOCKWAIT:if(ctrl_result)begin if(result_error)terminal(3);else begin leased<=1;step<=0;state<=CONFIG;end end
    CONFIG:if(w_valid && w_ready)state<=CONFIGWAIT;
    CONFIGWAIT:if(w_result)begin if(w_error)terminal(4);else if(step==9)state<=POLL;else begin step<=step+1'b1;state<=CONFIG;end end
    POLL:if(w_valid && w_ready)state<=POLLWAIT;
    POLLWAIT:if(w_result)begin
     if(w_error)terminal(4);
     else if(w_value[1] && !w_value[0])begin
      if(w_value[15:8]!=0)terminal(5);
      else begin data_successes<=data_successes+1'b1;file_confirmed<=1;state<=SIZE;end
     end else state<=POLL;
    end
    SIZE:if(w_valid && w_ready)state<=SIZEWAIT;
    SIZEWAIT:if(w_result)begin
     if(w_error || w_value>65536)terminal(6);
     else begin length<=w_value[16:0];status<=3;ratio<=100;file_kind<=2;pending<=1;state<=FINAL;end
    end
    UNLOCK:if(ctrl_ready)state<=UNLOCKWAIT;
    UNLOCKWAIT:if(ctrl_result)begin
     leased<=0;
     if(stopping)state<=FAILED;
     else if(result_error)begin reason<=7;state<=FAILED;end
     else begin state<=status==3?DONE:FAILED;if(status==3)successes<=successes+1'b1;end
    end
    CANCELLING:begin
     if(ctrl_result && held_ctrl_op==7)leased<=0;
     if(w_valid && w_ready)cancel_sent<=1;
     if(!w_busy && !f_busy && !file_inflight && !storage_owned)state<=leased?UNLOCK:FAILED;
    end
    default:begin end
   endcase
   if((host_cancel || expired) && busy && !stopping)begin
    reason<=host_cancel?8'd10:8'd11;cancellations<=cancellations+1'b1;pending<=0;stopping<=1;cancel_sent<=0;state<=CANCELLING;
   end
  end
 end
endmodule
