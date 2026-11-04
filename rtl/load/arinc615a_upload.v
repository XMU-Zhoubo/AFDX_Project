// C35 one LUR / one LUH / one data file upload control. Storage is external;
// parsing, active RRQ, checksum decision, validity commit and LUS are DUT work.
module arinc615a_upload(
 input wire clk,rst_n,input wire [31:0] now,
 input wire initialized,input wire init_network,input wire [47:0] init_mac,input wire [31:0] init_ip,input wire [15:0] init_serial,
 input wire lur_complete,input wire [15:0] lur_size,
 input wire h_valid,h_write,input wire [9:0] h_address,input wire [31:0] h_data,output wire h_ready,
 output reg h_result_valid,input wire h_result_ready,output reg h_error,output reg [31:0] h_result,
 output wire busy,output wire accept_lur,output wire [47:0] loader_mac,output wire [31:0] loader_ip,output wire loader_network,
 output wire rr_start,input wire rr_ready,rr_busy,rr_result,input wire [7:0] rr_reason,input wire [15:0] rr_length,rr_crc16,input wire [31:0] rr_crc32,
 output wire rr_take,output wire rr_cancel,output wire [255:0] rr_filename,output wire [5:0] rr_name_length,output wire [2:0] rr_object,output wire [31:0] rr_seed,
 output wire req_valid,input wire req_ready,output wire [2:0] req_op,req_object,output wire [15:0] req_offset,output wire [9:0] req_length,output wire req_final,
 input wire [7:0] read_data,input wire read_valid,read_last,output wire read_ready,input wire store_result,store_error,input wire [15:0] store_size,input wire [7:0] store_flags,output wire store_take,output reg store_cancel,
 output wire notice_start,input wire notice_ready,notice_busy,notice_result,input wire [7:0] notice_reason,output wire notice_take,notice_cancel,
 output wire [15:0] notice_serial,notice_status,output wire [6:0] notice_ratio,output wire [255:0] notice_name,notice_pn,output wire [5:0] notice_nl,notice_pl,
 output wire [31:0] notice_deadline
);
 localparam IDLE=0,STAT=1,STATWAIT=2,PARSESTART=3,READ=4,READDATA=5,READWAIT=6,PARSEWAIT=7,RRSTART=8,RRWAIT=9,COMMIT=10,COMMITWAIT=11,FINALWAIT=12,DONE=13,FAILED=14,CANCELLING=15,ABORT=16,ABORTWAIT=17;
 reg [4:0] state;reg header_phase;reg [9:0] file_size;reg [15:0] expected_size,expected_crc;reg [31:0] expected_load,seed;
 reg [255:0] header_name,pn,data_name;reg [5:0] header_nl,pnl,data_nl;
 reg net;reg [47:0] peer_mac;reg [31:0] peer_ip;reg [7:0] reason;
 reg local_valid,operation_ok,notified,data_opened,cleanup_cancel;reg [31:0] successes,failures,cancels,started,finished,period,deadline,last_notice;
 reg pending,final_notice,notice_inflight,notice_final_inflight;reg [15:0] status,counter;reg [6:0] progress;
 reg [31:0] notices,notice_failures;reg cancel_latched,serial_used;reg [15:0] consumed_serial;
 wire host_cancel=h_valid && h_ready && h_write && h_address==0 && h_data==2;
 wire parser_start=state==PARSESTART;wire parser_ready,parser_result;wire [7:0] parser_error;
 wire [255:0] parsed_name,parsed_pn;wire [5:0] parsed_nl,parsed_pl;wire [15:0] parsed_length,parsed_crc;wire [31:0] parsed_load,parsed_seed;
 load_file_parser parser(.clk(clk),.rst_n(rst_n && !cancel_latched),.start(parser_start),.kind(header_phase),.length(file_size),
 .s_data(read_data),.s_valid(read_valid && state==READDATA),.s_last(read_last),.s_ready(parser_ready),
 .result_valid(parser_result),.result_ready(state==PARSEWAIT),.error(parser_error),.filename(parsed_name),.part_number(parsed_pn),.name_length(parsed_nl),.pn_length(parsed_pl),
 .data_length(parsed_length),.data_crc(parsed_crc),.load_crc(parsed_load),.load_seed(parsed_seed));
 assign busy=rst_n && state!=IDLE && state!=DONE && state!=FAILED;
 assign accept_lur=rst_n && initialized && !busy && !notice_busy && !rr_busy && (!serial_used || init_serial!=consumed_serial);
 assign loader_mac=busy?peer_mac:init_mac;assign loader_ip=busy?peer_ip:init_ip;assign loader_network=busy?net:init_network;
 assign h_ready=rst_n && !h_result_valid;
 assign rr_start=rst_n && state==RRSTART && !cancel_latched;
 assign rr_filename=header_phase?data_name:header_name;assign rr_name_length=header_phase?data_nl:header_nl;
 assign rr_object=header_phase?3'd0:3'd4;assign rr_seed=header_phase?seed:32'hffffffff;
 assign rr_take=state==RRWAIT || state==CANCELLING;assign rr_cancel=cancel_latched && state==CANCELLING;
 assign req_valid=rst_n && (state==STAT || state==READ || state==COMMIT || state==ABORT) && (!cancel_latched || state==ABORT);
 assign req_op=state==STAT?3'd4:state==READ?3'd3:state==ABORT?3'd5:3'd2;
 assign req_object=(state==COMMIT || state==ABORT)?3'd0:header_phase?3'd4:3'd3;
 assign req_offset=state==COMMIT?expected_size:16'd0;assign req_length=state==READ?file_size:10'd0;
 // Zero-data final commit: file bytes are already stored but not readable until
 // every data/header/load check has passed. No read/write byte at address4096.
 assign req_final=state==COMMIT;
 assign read_ready=state==READDATA && parser_ready;
 assign store_take=state==STATWAIT || state==READWAIT || state==COMMITWAIT || state==ABORTWAIT || state==CANCELLING;
 assign notice_start=pending && notice_ready && !cancel_latched && state!=ABORT && state!=ABORTWAIT;
 assign notice_serial=counter;assign notice_status=status;assign notice_ratio=progress;
 assign notice_name=header_name;assign notice_pn=pn;assign notice_nl=header_nl;assign notice_pl=pnl;
 assign notice_deadline=deadline;assign notice_take=notice_inflight && notice_result;assign notice_cancel=cancel_latched;
 task fail;input [7:0] why;begin
  reason<=why;operation_ok<=0;status<=16'h1003;progress<=0;pending<=1;final_notice<=1;state<=data_opened?ABORT:FINALWAIT;cleanup_cancel<=0;failures<=failures+1'b1;
 end endtask
 always @(posedge clk)begin
  if(!rst_n)begin
   state<=IDLE;header_phase<=0;file_size<=0;expected_size<=0;expected_crc<=0;expected_load<=0;seed<=0;
   header_name<=0;pn<=0;data_name<=0;header_nl<=0;pnl<=0;data_nl<=0;net<=0;peer_mac<=0;peer_ip<=0;reason<=0;
   local_valid<=0;operation_ok<=0;notified<=0;data_opened<=0;cleanup_cancel<=0;successes<=0;failures<=0;cancels<=0;started<=0;finished<=0;period<=100000000;deadline<=1300000000;last_notice<=0;
   pending<=0;final_notice<=0;notice_inflight<=0;notice_final_inflight<=0;status<=2;counter<=0;progress<=0;notices<=0;notice_failures<=0;cancel_latched<=0;serial_used<=0;consumed_serial<=0;
   h_result_valid<=0;h_error<=0;h_result<=0;store_cancel<=0;
  end else begin
   store_cancel<=0;if(h_result_valid && h_result_ready)h_result_valid<=0;
   if(h_valid && h_ready)begin
    h_result_valid<=1;h_error<=0;h_result<=0;
    if(h_write)case(h_address)
     0:if(h_data!=2 || !busy)h_error<=1;
     1:if(busy || h_data<1000 || h_data>2000000000)h_error<=1;else period<=h_data;
     2:if(busy || h_data<1000 || h_data>2000000000)h_error<=1;else deadline<=h_data;
     default:h_error<=1;
    endcase
    else case(h_address)
     0:h_result<={16'd0,reason,3'd0,state};1:h_result<={29'd0,notified,operation_ok,local_valid};2:h_result<=expected_size;
     3:h_result<=successes;4:h_result<=failures;5:h_result<=cancels;6:h_result<=notices;7:h_result<=notice_failures;8:h_result<={16'd0,counter};
     9:h_result<=started;10:h_result<=finished;11:h_result<=period;12:h_result<=deadline;13:h_result<=expected_crc;14:h_result<=expected_load;
     default:h_error<=1;
    endcase
   end
   if(notice_start)begin pending<=0;notice_inflight<=1;notice_final_inflight<=final_notice;last_notice<=now;counter<=counter+1'b1;end
   if(notice_take)begin
    notice_inflight<=0;
    if(notice_reason!=0 && !cancel_latched)begin
     notice_failures<=notice_failures+1'b1;operation_ok<=0;reason<=9;cancel_latched<=1;pending<=0;state<=CANCELLING;
    end else if(notice_reason==0 && !cancel_latched)begin
     notices<=notices+1'b1;
     if(notice_final_inflight && state==FINALWAIT && !pending)begin notified<=1;finished<=now;state<=operation_ok?DONE:FAILED;end
    end
   end
   if(busy && !final_notice && !pending && !notice_inflight && now-last_notice>=period)pending<=1;
   case(state)
    IDLE,DONE,FAILED:if(lur_complete && initialized && accept_lur)begin
     serial_used<=1;consumed_serial<=init_serial;net<=init_network;peer_mac<=init_mac;peer_ip<=init_ip;header_phase<=0;file_size<=lur_size[9:0];state<=STAT;
     local_valid<=0;operation_ok<=0;notified<=0;data_opened<=0;header_name<=0;header_nl<=0;pn<=0;pnl<=0;reason<=0;cancel_latched<=0;pending<=0;final_notice<=0;
     started<=now;counter<=init_serial+1'b1;last_notice<=now;
    end
    STAT:if(req_ready)state<=STATWAIT;
    STATWAIT:if(store_result)begin
     if(store_error || !store_flags[0] || store_size<8 || store_size>512)fail(1);
     else begin file_size<=store_size[9:0];state<=PARSESTART;end
    end
    PARSESTART:state<=READ;
    READ:if(req_ready)state<=READDATA;
    READDATA:if(read_valid && read_ready && read_last)state<=READWAIT;
    READWAIT:if(store_result)begin if(store_error)fail(2);else state<=PARSEWAIT;end
    PARSEWAIT:if(parser_result)begin
     if(parser_error!=0)fail(header_phase?8'd4:8'd3);
     else if(!header_phase)begin
      header_name<=parsed_name;header_nl<=parsed_nl;pn<=parsed_pn;pnl<=parsed_pl;progress<=0;status<=2;pending<=1;state<=RRSTART;
     end else if(parsed_pn!=pn || parsed_pl!=pnl)fail(5);
     else begin data_name<=parsed_name;data_nl<=parsed_nl;expected_size<=parsed_length;expected_crc<=parsed_crc;expected_load<=parsed_load;seed<=parsed_seed;state<=RRSTART;end
    end
    RRSTART:if(rr_start && rr_ready)begin if(header_phase)data_opened<=1;state<=RRWAIT;end
    RRWAIT:if(rr_result)begin
     if(rr_reason!=0)fail(6);
     else if(!header_phase)begin header_phase<=1;state<=STAT;end
     else if(rr_length!=expected_size || rr_crc16!=expected_crc || rr_crc32!=expected_load)fail(7);
     else state<=COMMIT;
    end
    COMMIT:if(req_ready)state<=COMMITWAIT;
    COMMITWAIT:if(store_result)begin
     if(store_error)fail(8);
     else begin data_opened<=0;local_valid<=1;operation_ok<=1;successes<=successes+1'b1;status<=3;progress<=100;pending<=1;final_notice<=1;state<=FINALWAIT;end
    end
    ABORT:if(req_ready)state<=ABORTWAIT;
    ABORTWAIT:if(store_result)begin data_opened<=0;state<=cleanup_cancel?FAILED:FINALWAIT;end
    FINALWAIT:begin end
    CANCELLING:if(!rr_busy && !notice_busy && !notice_inflight)begin cleanup_cancel<=1;state<=data_opened?ABORT:FAILED;finished<=now;end
    default:state<=IDLE;
   endcase
   if(host_cancel && busy)begin cancels<=cancels+1'b1;operation_ok<=0;reason<=10;cancel_latched<=1;pending<=0;state<=CANCELLING;end
   if(busy && state!=CANCELLING && now-started>=deadline)begin operation_ok<=0;reason<=11;cancel_latched<=1;pending<=0;state<=CANCELLING;end
  end
 end
endmodule
