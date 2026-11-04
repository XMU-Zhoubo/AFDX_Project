// C34 manual LUI provision and strict LUI/LUR validator. Automatic
// initialization is a separate module; this legacy status is not its result.
module arinc615a_control (
 input wire clk,rst_n,input wire [31:0] now,input wire server_active,output wire busy,
 input wire h_valid,h_write,input wire [9:0] h_address,input wire [31:0] h_data,
 output wire h_ready,output reg h_result_valid,input wire h_result_ready,output reg h_error,output reg [31:0] h_result,
 output wire req_valid,input wire req_ready,output wire [2:0] req_op,output wire [9:0] req_length,
 output wire [7:0] s_data,output wire s_valid,s_last,input wire s_ready,
 input wire result_valid,result_error,output wire result_ready,output reg cancel,
 output reg available,output wire accepted,output wire initialization_complete
);
 localparam [2:0] IDLE=0,OPEN=1,OPEN_WAIT=2,WRITE=3,DATA=4,WAIT=5;
 reg [2:0] state;reg acceptance;reg [4:0] index;reg [31:0] provisions,failures,stamp;
 assign busy=rst_n && state!=0;
 reg parser_command,parser_byte,parser_cancel,parser_take,query;
 wire pc_ready,pb_ready,presult,perror,qvalid;wire [3:0] preason;wire [15:0] pstatus;wire [7:0] pdesc,qdata;wire [2:0] pcount;
 reg p_kind,p_last;reg [9:0] p_length;reg [7:0] p_data;reg [8:0] qaddress;reg query_wait;
 wire [7:0] desc_length=acceptance?8'd6:8'd10;
 wire [9:0] file_length=10'd9+{2'd0,desc_length};
 assign initialization_complete=1'b0;
 assign accepted=acceptance;
 assign req_valid=rst_n && (state==OPEN || state==WRITE);assign req_op=state==OPEN?3'd1:3'd2;
 assign req_length=state==OPEN?10'd0:file_length;assign s_valid=rst_n && state==DATA;assign s_last={5'd0,index}+10'd1==file_length;
 assign result_ready=state==OPEN_WAIT || state==WAIT;
 function [7:0] description_byte;input [4:0] n;begin
  if(acceptance)case(n)0:description_byte="R";1:description_byte="e";2:description_byte="a";3:description_byte="d";4:description_byte="y";default:description_byte=0;endcase
  else case(n)0:description_byte="N";1:description_byte="o";2:description_byte="t";3:description_byte=" ";4:description_byte="r";5:description_byte="e";6:description_byte="a";7:description_byte="d";8:description_byte="y";default:description_byte=0;endcase
 end endfunction
 assign s_data=index<3?8'd0:index==3?file_length[7:0]:index==4?8'h41:index==5?8'h34:index==6?(acceptance?8'h00:8'h10):index==7?(acceptance?8'h01:8'h00):index==8?desc_length:description_byte(index-5'd9);
 assign h_ready=rst_n && !h_result_valid && !query_wait &&
  (!(h_write && h_address==0) || (state==IDLE && !server_active)) &&
  (!(h_write && h_address==16) || pc_ready) && (!(h_write && h_address==17) || pb_ready);
 arinc615a_files files(.clk(clk),.rst_n(rst_n),.cancel(parser_cancel),.cmd_valid(parser_command),.cmd_ready(pc_ready),.cmd_kind(p_kind),.cmd_length(p_length),
 .s_data(p_data),.s_valid(parser_byte),.s_last(p_last),.s_ready(pb_ready),.result_valid(presult),.result_ready(parser_take),.result_error(perror),.result_reason(preason),
 .result_status(pstatus),.result_description_length(pdesc),.result_count(pcount),.query_valid(query),.query_address(qaddress),.query_result_valid(qvalid),.query_data(qdata));
 always @(posedge clk)begin
  if(!rst_n)begin state<=IDLE;acceptance<=0;index<=0;provisions<=0;failures<=0;stamp<=0;available<=0;cancel<=0;h_result_valid<=0;h_error<=0;h_result<=0;
   parser_command<=0;parser_byte<=0;parser_cancel<=0;parser_take<=0;query<=0;query_wait<=0;p_kind<=0;p_last<=0;p_length<=0;p_data<=0;qaddress<=0;
  end else begin
   parser_command<=0;parser_byte<=0;parser_cancel<=0;parser_take<=0;query<=0;cancel<=0;
   if(h_result_valid && h_result_ready)h_result_valid<=0;
   if(query_wait && qvalid)begin h_result_valid<=1;h_result<={24'd0,qdata};h_error<=0;query_wait<=0;end
   if(h_valid && h_ready)begin h_result_valid<=1;h_result<=0;h_error<=0;
    if(h_write)case(h_address)
     0:if(h_data<=1)begin acceptance<=h_data[0];state<=OPEN;available<=0;stamp<=now;end else h_error<=1;
     2:if(h_data==1 && !server_active)begin cancel<=1;state<=IDLE;available<=0;parser_cancel<=1;end else h_error<=1;
     16:begin parser_command<=1;p_kind<=h_data[16];p_length<=h_data[9:0];end
     17:begin parser_byte<=1;p_data<=h_data[7:0];p_last<=h_data[8];end
     18:if(h_data==1)parser_take<=1;else h_error<=1;
     19:if(h_data==1)parser_cancel<=1;else h_error<=1;
     default:h_error<=1;
    endcase
    else case(h_address)
     0:h_result<={30'd0,available,acceptance};1:h_result<={28'd0,1'b0,state};2:h_result<=provisions;3:h_result<=failures;4:h_result<=stamp;
     5:h_result<=32'd0; // Not a shortcut to READY: LUS has not been verified.
     18:h_result<={pstatus,pdesc,1'b0,pcount,preason};20:h_result<={30'd0,perror,presult};
     default:if(h_address>=32 && h_address<544 && presult && h_address-10'd32<p_length)begin query<=1;qaddress<=h_address[8:0]-9'd32;query_wait<=1;h_result_valid<=0;end else h_error<=1;
    endcase
   end
   case(state)
    OPEN:if(req_ready)state<=OPEN_WAIT;
    OPEN_WAIT:if(result_valid)begin if(result_error)begin failures<=failures+1'b1;state<=IDLE;cancel<=1;end else state<=WRITE;end
    WRITE:if(req_ready)begin index<=0;state<=DATA;end
    DATA:if(s_ready)begin if(s_last)state<=WAIT;else index<=index+1'b1;end
    WAIT:if(result_valid)begin state<=IDLE;if(result_error)begin failures<=failures+1'b1;cancel<=1;end else begin available<=1;provisions<=provisions+1'b1;end end
    default:begin end
   endcase
   // Cancel wins even on the last data beat/request acceptance edge.
   if(h_valid && h_ready && h_write && h_address==2 && h_data==1 && !server_active)begin state<=IDLE;cancel<=1;available<=0;parser_cancel<=1;end
  end
 end
endmodule
