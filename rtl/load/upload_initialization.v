// C34 target initialization only. Actual RRQ-LUI final ACK triggers one
// generated/stored A4 accepted LUS; the existing active client sends it.
// WAIT_LUR is initialization success, never upload/operation completion.
module upload_initialization #(
 parameter [31:0] DEADLINE_TICKS=32'd1300000000
) (
 input wire clk,rst_n,input wire [31:0] now,input wire control_available,control_accepted,control_busy,server_busy,writer_busy,
 input wire lui_complete,lui_network,input wire [47:0] lui_mac,input wire [31:0] lui_ip,
 input wire h_valid,h_write,input wire [9:0] h_address,input wire [31:0] h_data,
 output wire h_ready,output reg h_result_valid,input wire h_result_ready,output reg h_error,output reg [31:0] h_result,
 output wire client_owned,output wire client_valid,client_write,output wire [9:0] client_address,output wire [31:0] client_data,
 input wire client_ready,client_result_valid,client_error,input wire [31:0] client_result,output wire client_result_ready,
 output wire req_valid,input wire req_ready,output wire [2:0] req_op,output wire [9:0] req_length,
 output wire [7:0] s_data,output wire s_valid,s_last,input wire s_ready,
 input wire result_valid,result_error,output wire result_ready,output reg cancel,
 output wire [15:0] serial_value,output wire peer_network,output wire [47:0] loader_mac,output wire [31:0] loader_ip,output wire busy,initialization_complete,storage_locked,output reg storage_leased
);
 localparam [4:0] IDLE=0,WAIT_LUI=1,OPEN=2,OPEN_WAIT=3,ENCODE=4,WRITE=5,DATA=6,STORE_WAIT=7,
  CFG=8,CFG_WAIT=9,POLL=10,POLL_WAIT=11,STOP=12,STOP_WAIT=13,WAIT_LUR=14,FAILED=15,REFUSED=16;
 reg [4:0] state;reg [3:0] step;reg network;reg [47:0] peer_mac;reg [31:0] peer_ip;
 reg [31:0] deadline,started,finished,notifications,failures,cancellations,duplicate_lui;
 reg [15:0] serial;reg [7:0] reason,stop_reason;reg stop_pending;
 reg [15:0] destination;
 wire ec_ready,ec_valid,ec_error;wire [7:0] ec_data;wire ec_byte,ec_last;
 wire host_cancel=h_valid && h_ready && h_write && h_address==0 && h_data==2;
 wire expired=busy && now-started>=deadline;
 assign busy=rst_n && state!=IDLE && state!=WAIT_LUR && state!=FAILED && state!=REFUSED;
 assign initialization_complete=rst_n && state==WAIT_LUR;
 assign storage_locked=rst_n && ((state>=OPEN && state<=STORE_WAIT) || storage_leased || cancel);
 assign client_owned=rst_n && state>=OPEN && state<=STOP_WAIT;
 assign h_ready=rst_n && !h_result_valid;
 assign req_valid=rst_n && (state==OPEN || state==WRITE);assign req_op=state==OPEN?3'd1:3'd2;
 assign req_length=state==OPEN?10'd0:10'd20;
 assign s_data=ec_data;assign s_valid=state==DATA && ec_byte;assign s_last=ec_last;
 assign result_ready=state==OPEN_WAIT || state==STORE_WAIT;
 arinc615a_lus lus(.clk(clk),.rst_n(rst_n),.cancel(cancel),.cmd_valid(state==ENCODE),.cmd_ready(ec_ready),
  .version(16'h4134),.status(16'd1),.counter(serial),.ratio(8'd0),
  .m_data(ec_data),.m_valid(ec_byte),.m_last(ec_last),.m_ready(state==DATA && s_ready),
  .result_valid(ec_valid),.result_ready(state==STORE_WAIT),.result_error(ec_error));
 assign client_valid=rst_n && ((state==CFG && (step!=8 || (!server_busy && !control_busy))) || state==POLL || state==STOP);
 assign serial_value=serial;assign peer_network=network;assign loader_mac=peer_mac;assign loader_ip=peer_ip;
 assign client_write=state!=POLL;assign client_address=state==POLL || state==STOP?10'd0:
  step==0?10'd1:step==1?10'd2:step==2?10'd3:step==3?10'd4:step==4?10'd5:step==5?10'd8:step==6?10'd9:step==7?10'd10:10'd0;
 assign client_data=state==STOP?32'd2:step==0?peer_ip:step==1?peer_mac[31:0]:step==2?{16'd0,peer_mac[47:32]}:
  step==3?{16'd0,destination}:step==4?{18'd0,6'd11,7'd0,network}:
  step==5?32'h41464458:step==6?32'h5f30312e:step==7?32'h4c555300:32'd1;
 assign client_result_ready=state==CFG_WAIT || state==POLL_WAIT || state==STOP_WAIT;
 task fail;input [7:0] why;begin state<=FAILED;reason<=why;failures<=failures+1'b1;finished<=now;cancel<=1;end endtask
 always @(posedge clk)begin
  if(!rst_n)begin
   state<=IDLE;step<=0;network<=0;peer_mac<=0;peer_ip<=0;deadline<=DEADLINE_TICKS;destination<=59;
   started<=0;finished<=0;notifications<=0;failures<=0;cancellations<=0;duplicate_lui<=0;serial<=0;reason<=0;stop_reason<=0;stop_pending<=0;
   cancel<=0;storage_leased<=0;h_result_valid<=0;h_error<=0;h_result<=0;
  end else begin
   cancel<=0;if(cancel)storage_leased<=0;if(h_result_valid && h_result_ready)h_result_valid<=0;
   if(h_valid && h_ready)begin
    h_result_valid<=1;h_error<=0;h_result<=0;
    if(h_write)case(h_address)
     0:if(h_data==1)begin
      if(busy || writer_busy || server_busy || control_busy || !control_available)h_error<=1;
      else begin state<=WAIT_LUI;started<=now;finished<=0;reason<=0;stop_pending<=0;end
     end else if(h_data!=2 || !busy)h_error<=1;
     9:if(busy || h_data<1000 || h_data>32'd2000000000)h_error<=1;else deadline<=h_data;
     10:if(busy || h_data==0 || h_data>65535)h_error<=1;else destination<=h_data[15:0];
     default:h_error<=1;
    endcase
    else case(h_address)
     0:h_result<={27'd0,state};1:h_result<={31'd0,initialization_complete};2:h_result<={24'd0,reason};
     3:h_result<=notifications;4:h_result<=failures;5:h_result<={16'd0,serial};6:h_result<=cancellations;
     7:h_result<=started;8:h_result<=finished;9:h_result<=deadline;10:h_result<={16'd0,destination};11:h_result<=duplicate_lui;
     default:h_error<=1;
    endcase
   end
   if(lui_complete && state!=WAIT_LUI && state!=IDLE)duplicate_lui<=duplicate_lui+1'b1;
   case(state)
    WAIT_LUI:if(lui_complete)begin
     if(!control_available || !control_accepted)begin state<=REFUSED;reason<=2;finished<=now;end
     else begin peer_mac<=lui_mac;peer_ip<=lui_ip;network<=lui_network;serial<=serial+1'b1;started<=now;state<=OPEN;end
    end
    OPEN:if(req_ready)begin state<=OPEN_WAIT;storage_leased<=1;end
    OPEN_WAIT:if(result_valid)begin if(result_error)fail(5);else state<=ENCODE;end
    ENCODE:if(ec_ready)state<=WRITE;
    WRITE:if(req_ready)state<=DATA;
    DATA:if(s_valid && s_ready && s_last)state<=STORE_WAIT;
    STORE_WAIT:if(result_valid)begin if(result_error || ec_error)fail(5);else begin storage_leased<=0;step<=0;state<=CFG;end end
    CFG:if(client_valid && client_ready)state<=CFG_WAIT;
    CFG_WAIT:if(client_result_valid)begin
     if(stop_pending || host_cancel || expired)begin
      if(writer_busy || step==8)state<=STOP;else fail(host_cancel?8'd3:stop_pending?stop_reason:8'd4);
     end else if(client_error)fail(6);
     else if(step==8)state<=POLL;
     else begin step<=step+1'b1;state<=CFG;end
    end
    POLL:if(client_ready)state<=POLL_WAIT;
    POLL_WAIT:if(client_result_valid)begin
     if(client_error)fail(6);
     else if(client_result[1] && !client_result[0])begin
      if(stop_pending || host_cancel || expired)fail(host_cancel?8'd3:stop_pending?stop_reason:8'd4);
      else if(client_result[15:8]!=0)fail(1);
      else begin state<=WAIT_LUR;notifications<=notifications+1'b1;finished<=now;reason<=0;end
     end else if(stop_pending)state<=STOP;else state<=POLL;
    end
    STOP:if(client_ready)state<=STOP_WAIT;
    STOP_WAIT:if(client_result_valid)state<=POLL;
    default:begin end
   endcase
   // Cancellation/deadline wins over a coincident successful final ACK.
   // Drain an accepted CSR before issuing cancel; never abandon its response.
   if((host_cancel || expired) && busy && !stop_pending)begin
    if(host_cancel)cancellations<=cancellations+1'b1;
    stop_reason<=host_cancel?8'd3:8'd4;stop_pending<=1;
    if(state==CFG || state==CFG_WAIT || state==POLL || state==POLL_WAIT || state==STOP_WAIT)begin end
    else if(writer_busy)begin if(state!=STOP)state<=STOP;end
    else fail(host_cancel?8'd3:8'd4);
   end
  end
 end
endmodule
