// A4 ODD files from pinned DownloadOperationList/StatusFile serializers.
// One immutable generated control object; shared status WRQ client.
module arinc615a_download_files(
 input wire clk,rst_n,input wire [31:0] now,deadline,
 input wire start,output wire ready,input wire cancel,input wire [1:0] kind,
 input wire selected,has_file,network,input wire [47:0] mac,input wire [31:0] ip,
 input wire [15:0] counter,status,input wire [6:0] ratio,
 output wire busy,result_valid,input wire result_ready,output reg [7:0] reason,
 output wire client_owned,client_valid,client_write,output wire [9:0] client_address,
 output wire [31:0] client_data,input wire client_ready,client_result_valid,client_error,
 input wire [31:0] client_result,output wire client_take,input wire writer_busy,
 output wire [3:0] object_id,output wire req_valid,input wire req_ready,
 output wire [2:0] req_op,output wire [9:0] req_length,
 output wire [7:0] s_data,output wire s_valid,s_last,input wire s_ready,
 input wire store_result,store_error,output wire store_take,output reg store_cancel
);
 localparam IDLE=0,OPEN=1,OPENWAIT=2,WRITE=3,DATA=4,STOREWAIT=5,
  CFG=6,CFGWAIT=7,POLL=8,POLLWAIT=9,STOP=10,STOPWAIT=11,RESULT=12,ABORT=13,ABORTWAIT=14;
 reg [3:0] state,step;reg [1:0] mode;reg sel,with_file,net,stopping,leased;
 reg [47:0] peer_mac;reg [31:0] peer_ip,started;reg [15:0] code,count;
 reg [6:0] progress;reg [9:0] index,length;
 assign ready=rst_n && state==IDLE && !writer_busy;assign busy=rst_n && state!=IDLE && state!=RESULT;
 assign result_valid=rst_n && state==RESULT;assign object_id=mode==0?4'd7:mode==1?4'd8:4'd10;
 assign client_owned=busy && mode!=0;assign client_valid=rst_n && (state==CFG || state==POLL || state==STOP);
 assign client_write=state!=POLL;assign client_take=state==CFGWAIT || state==POLLWAIT || state==STOPWAIT;
 assign client_address=state==POLL || state==STOP?10'd0:step==0?10'd1:step==1?10'd2:step==2?10'd3:step==3?10'd4:step==4?10'd5:step==5?10'd8:step==6?10'd9:step==7?10'd10:10'd0;
 assign client_data=state==STOP?32'd2:step==0?peer_ip:step==1?peer_mac[31:0]:step==2?{16'd0,peer_mac[47:32]}:
  step==3?32'd59:step==4?{18'd0,6'd11,7'd0,net}:step==5?32'h41464458:step==6?32'h5f30312e:step==7?(mode==1?32'h4c4e4c00:32'h4c4e5300):32'd1;
 assign req_valid=rst_n && (state==OPEN || state==WRITE || state==ABORT);
 assign req_op=state==OPEN?3'd1:state==ABORT?3'd5:3'd2;
 assign req_length=state==WRITE?length:10'd0;assign store_take=state==OPENWAIT || state==STOREWAIT || state==ABORTWAIT;
 assign s_valid=rst_n && state==DATA;assign s_last=index+1'b1==length;
 function [7:0] file_byte;input big;input [3:0] n;reg [71:0] v;begin
  v=big?"BIG64.BIN":"SMALL.BIN";file_byte=n<9?v[71-n*8-:8]:8'd0;
 end endfunction
 function [7:0] digit;input [1:0] n;input [6:0] v;begin
  if(n==0)digit=v==100?"1":" ";else if(n==1)digit=v==100?"0":" ";else digit=v==100?"0":"0";
 end endfunction
 function [7:0] byte_at;input [9:0] k;begin
  byte_at=0;
  if(k==3)byte_at=length[7:0];else if(k==4)byte_at="A";else if(k==5)byte_at="4";
  else if(mode==0)begin
   case(k)7:byte_at=1;8:byte_at=6;9:byte_at="R";10:byte_at="e";11:byte_at="a";12:byte_at="d";13:byte_at="y";default:byte_at=0;endcase
  end else if(mode==1)begin
   if(k==7)byte_at=2;else if(k==8 || k==20)byte_at=10;
   else if(k>=9 && k<19)byte_at=file_byte(0,k-9);
   else if(k>=21 && k<31)byte_at=file_byte(1,k-21);
  end else begin
   case(k)
    6:byte_at=code[15:8];7:byte_at=code[7:0];9:byte_at=count[15:8];10:byte_at=count[7:0];
    15,16,17:byte_at=digit(k-15,progress);19:byte_at={7'd0,with_file};20:byte_at=10;
    31:byte_at=code[15:8];32:byte_at=code[7:0];
    default:if(k>=21 && k<31)byte_at=file_byte(sel,k-21);
   endcase
  end
 end endfunction
 assign s_data=byte_at(index);
 task finish;input [7:0] why;begin reason<=why;state<=why!=0 && leased?ABORT:RESULT;end endtask
 always @(posedge clk)begin
  if(!rst_n)begin state<=IDLE;step<=0;mode<=0;sel<=0;with_file<=0;net<=0;stopping<=0;leased<=0;peer_mac<=0;peer_ip<=0;started<=0;code<=0;count<=0;progress<=0;index<=0;length<=0;reason<=0;store_cancel<=0;end
  else begin
   store_cancel<=0;if(busy && (cancel || now-started>=deadline))stopping<=1;
   case(state)
    IDLE:if(start && ready)begin mode<=kind;sel<=selected;with_file<=has_file;net<=network;peer_mac<=mac;peer_ip<=ip;count<=counter;code<=status;progress<=ratio;
     length<=kind==0?10'd15:kind==1?10'd32:has_file?10'd34:10'd20;index<=0;started<=now;stopping<=0;reason<=0;state<=OPEN;end
    OPEN:if(req_ready)begin leased<=1;state<=OPENWAIT;end
    OPENWAIT:if(store_result)begin if(store_error || stopping)finish(1);else state<=WRITE;end
    WRITE:if(req_ready)begin index<=0;state<=DATA;end
    DATA:if(s_ready)begin if(s_last)state<=STOREWAIT;else index<=index+1'b1;end
    STOREWAIT:if(store_result)begin leased<=0;if(store_error || stopping)finish(1);else if(mode==0)finish(0);else begin step<=0;state<=CFG;end end
    CFG:if(client_ready)state<=CFGWAIT;
    CFGWAIT:if(client_result_valid)begin
     if(stopping)begin if(writer_busy || step==8)state<=STOP;else finish(2);end
     else if(client_error)finish(3);else if(step==8)state<=POLL;else begin step<=step+1'b1;state<=CFG;end
    end
    POLL:if(client_ready)state<=POLLWAIT;
    POLLWAIT:if(client_result_valid)begin
     if(client_error)finish(3);else if(client_result[1] && !client_result[0])finish(stopping?8'd2:client_result[15:8]);
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
