// C35 one immutable A4 one-entry LUS snapshot, shared transparent WRQ client.
module arinc615a_notice(
 input wire clk,rst_n,input wire [31:0] now,deadline,
 input wire start,output wire ready,input wire cancel,
 input wire network,input wire [47:0] mac,input wire [31:0] ip,input wire [15:0] port,
 input wire [15:0] serial,status,input wire [6:0] ratio,input wire [255:0] filename,part_number,input wire [5:0] name_length,pn_length,
 output wire busy,output wire result_valid,input wire result_ready,output reg [7:0] reason,
 output wire client_owned,client_valid,client_write,output wire [9:0] client_address,output wire [31:0] client_data,
 input wire client_ready,client_result_valid,client_error,input wire [31:0] client_result,output wire client_take,input wire writer_busy,
 output wire req_valid,input wire req_ready,output wire [2:0] req_op,output wire [9:0] req_length,
 output wire [7:0] s_data,output wire s_valid,s_last,input wire s_ready,
 input wire store_result,store_error,output wire store_take,output reg store_cancel);
 localparam IDLE=0,OPEN=1,OPENWAIT=2,WRITE=3,DATA=4,STOREWAIT=5,CFG=6,CFGWAIT=7,POLL=8,POLLWAIT=9,STOP=10,STOPWAIT=11,RESULT=12,ABORT=13,ABORTWAIT=14;
 reg [3:0] state,step;reg net;reg [47:0] peer_mac;reg [31:0] peer_ip;reg [15:0] dest,count,code;
 reg [6:0] progress;reg [255:0] name,pn;reg [5:0] nl,pl;reg [9:0] index,length;reg [31:0] started;reg stopping,leased;
 assign ready=rst_n && state==IDLE;assign busy=rst_n && state!=IDLE && state!=RESULT;assign result_valid=rst_n && state==RESULT;
 assign client_owned=busy;assign client_valid=rst_n && (state==CFG || state==POLL || state==STOP);
 assign client_write=state!=POLL;assign client_address=state==POLL || state==STOP?0:step==0?1:step==1?2:step==2?3:step==3?4:step==4?5:step==5?8:step==6?9:step==7?10:0;
 assign client_data=state==STOP?2:step==0?peer_ip:step==1?peer_mac[31:0]:step==2?{16'd0,peer_mac[47:32]}:step==3?{16'd0,dest}:step==4?{18'd0,6'd11,7'd0,net}:step==5?32'h41464458:step==6?32'h5f30312e:step==7?32'h4c555300:1;
 assign client_take=state==CFGWAIT || state==POLLWAIT || state==STOPWAIT;
 assign req_valid=rst_n && (state==OPEN || state==WRITE || state==ABORT);assign req_op=state==OPEN?3'd1:state==ABORT?3'd5:3'd2;assign req_length=state==OPEN || state==ABORT?10'd0:length;
 assign store_take=state==OPENWAIT || state==STOREWAIT || state==ABORTWAIT;
 assign s_valid=rst_n && state==DATA;assign s_last=index+1'b1==length;
 function [7:0] digit;input [1:0] place;input [6:0] r;begin
  if(place==0)digit=r==100?"1":" ";else if(place==1)digit=r==100?"0":r<10?" ":"0"+r/10;else digit="0"+r%10;
 end endfunction
 function [7:0] byte_at;input [9:0] k;reg [9:0] n;begin
  byte_at=0;
  case(k)
   2:byte_at=length[9:8];3:byte_at=length[7:0];4:byte_at="A";5:byte_at="4";6:byte_at=code[15:8];7:byte_at=code[7:0];9:byte_at=count[15:8];10:byte_at=count[7:0];
   15,16,17:byte_at=digit(k-15,progress);19:byte_at=nl!=0;
   20:byte_at={2'd0,nl}+1'b1;
   default:begin
    if(k>=21 && k<21+nl)byte_at=name[255-(k-21)*8-:8];
    else if(k==22+nl)byte_at={2'd0,pl}+1'b1;
    else if(k>=23+nl && k<23+nl+pl)byte_at=pn[255-(k-23-nl)*8-:8];
    else if(k>=24+nl+pl && k<27+nl+pl)byte_at=digit(k-24-nl-pl,progress);
    else if(k==27+nl+pl)byte_at=code[15:8];else if(k==28+nl+pl)byte_at=code[7:0];
   end
  endcase
 end endfunction
 assign s_data=byte_at(index);
 task finish;input [7:0] why;begin state<=why!=0 && leased?ABORT:RESULT;reason<=why;store_cancel<=0;end endtask
 always @(posedge clk)begin
  if(!rst_n)begin state<=IDLE;step<=0;net<=0;peer_mac<=0;peer_ip<=0;dest<=59;count<=0;code<=0;progress<=0;name<=0;pn<=0;nl<=0;pl<=0;index<=0;length<=0;started<=0;reason<=0;stopping<=0;leased<=0;store_cancel<=0;end
  else begin
   store_cancel<=0;
   if(busy && (cancel || now-started>=deadline))stopping<=1;
   case(state)
    IDLE:if(start && ready)begin net<=network;peer_mac<=mac;peer_ip<=ip;dest<=port;count<=serial;code<=status;progress<=ratio;name<=filename;pn<=part_number;nl<=name_length;pl<=pn_length;
     length<=name_length==0?10'd20:30+{4'd0,name_length}+{4'd0,pn_length};index<=0;started<=now;reason<=0;stopping<=0;state<=OPEN;end
    OPEN:if(req_ready)begin leased<=1;state<=OPENWAIT;end
    OPENWAIT:if(store_result)begin if(store_error || stopping)finish(1);else state<=WRITE;end
    WRITE:if(req_ready)begin index<=0;state<=DATA;end
    DATA:if(s_ready)begin if(s_last)state<=STOREWAIT;else index<=index+1'b1;end
    STOREWAIT:if(store_result)begin leased<=0; if(store_error || stopping)finish(1);else begin step<=0;state<=CFG;end end
    CFG:if(client_ready)state<=CFGWAIT;
    CFGWAIT:if(client_result_valid)begin
     if(stopping)begin if(writer_busy || step==8)state<=STOP;else finish(2);end
     else if(client_error)finish(3);else if(step==8)state<=POLL;else begin step<=step+1'b1;state<=CFG;end
    end
    POLL:if(client_ready)state<=POLLWAIT;
    POLLWAIT:if(client_result_valid)begin
     if(client_error)finish(3);
     else if(client_result[1] && !client_result[0])finish(stopping?8'd2:client_result[15:8]);
     else if(stopping)state<=STOP;else state<=POLL;
    end
    STOP:if(client_ready)state<=STOPWAIT;
    STOPWAIT:if(client_result_valid)state<=POLL;
    ABORT:if(req_ready)state<=ABORTWAIT;
    ABORTWAIT:if(store_result)begin leased<=0;state<=RESULT;end
    RESULT:if(result_ready)state<=IDLE;
    default:state<=IDLE;
   endcase
  end
 end
endmodule
