// Bounded LUI/LUR validator. Public Manager/Wireshark common file layout.
// No LUS generator, no claim that validation completes a615a initialization.
module arinc615a_files (
 input wire clk,rst_n,cancel,
 input wire cmd_valid,output wire cmd_ready,input wire cmd_kind,input wire [9:0] cmd_length,
 input wire [7:0] s_data,input wire s_valid,s_last,output wire s_ready,
 output wire result_valid,input wire result_ready,output reg result_error,output reg [3:0] result_reason,
 output reg [15:0] result_status,output reg [7:0] result_description_length,output reg [2:0] result_count,
 input wire query_valid,input wire [8:0] query_address,output reg query_result_valid,output reg [7:0] query_data
);
 localparam IDLE=0,COLLECT=1,READ=2,BYTE=3,RESULT=4;
 reg [2:0] state;reg kind;reg [9:0] length,index,p;
 reg [31:0] declared;reg [15:0] version;
 reg [2:0] phase;reg [7:0] string_length,string_left;reg [2:0] entry;
 wire [7:0] ram_data;reg query_pending;
 assign cmd_ready=rst_n && state==IDLE;assign s_ready=rst_n && state==COLLECT;
 assign result_valid=rst_n && state==RESULT;
 payload_buffer #(.CAPACITY(512),.ADDR_WIDTH(9)) ram(.clk(clk),
 .write_enable(s_valid && s_ready && index<512),.write_addr(index[8:0]),.write_data(s_data),
 .read_enable(state==READ || (state==RESULT && query_valid && query_address<length)),
 .read_addr(state==READ?p[8:0]:query_address),.read_data(ram_data));
 task fail;input [3:0] reason;begin result_error<=1;result_reason<=reason;state<=RESULT;end endtask
 task advance;begin if(p+1'b1>=length)fail(4);else begin p<=p+1'b1;state<=READ;end end endtask
 task finish_string;begin
  if(!kind)begin if(p+1'b1!=length)fail(5);else state<=RESULT;end
  else if(phase==1)begin phase<=2;advance;end
  else if(entry+1'b1==result_count)begin if(p+1'b1!=length)fail(5);else state<=RESULT;end
  else begin entry<=entry+1'b1;phase<=1;advance;end
 end endtask
 always @(posedge clk)begin
  if(!rst_n || cancel)begin state<=IDLE;kind<=0;length<=0;index<=0;p<=0;declared<=0;version<=0;phase<=0;string_length<=0;string_left<=0;entry<=0;result_error<=0;result_reason<=0;result_status<=0;result_description_length<=0;result_count<=0;query_pending<=0;query_result_valid<=0;query_data<=0;end
  else begin
   query_result_valid<=query_pending;query_pending<=state==RESULT && query_valid && query_address<length;
   if(query_pending)query_data<=ram_data;
   case(state)
    IDLE:if(cmd_valid)begin kind<=cmd_kind;length<=cmd_length;index<=0;result_error<=0;result_reason<=0;result_status<=0;result_description_length<=0;result_count<=0;entry<=0;phase<=0;declared<=0;version<=0;
     // Even unsupported length commands drain their complete actual stream.
     state<=COLLECT;if(cmd_length==0)fail(1);
    end
    COLLECT:if(s_valid && s_ready)begin
     if(s_last)begin
      if(index+1'b1!=length || length>512 || length<(kind?8:9))fail(1);
      else begin p<=0;state<=READ;end
     end else if(index==1023)begin result_error<=1;result_reason<=1;end
     else index<=index+1'b1;
    end
    READ:state<=BYTE;
    BYTE:begin
     if(p<4)begin declared<={declared[23:0],ram_data};advance;end
     else if(p<6)begin version<={version[7:0],ram_data};
      if(p==5 && ({version[7:0],ram_data}!=16'h4134 || declared!={22'd0,length}))fail(2);else advance;
     end else if(p==6)begin result_status<={8'd0,ram_data};advance;end
     else if(p==7)begin
      if(kind)begin
       if(result_status[7:0]!=0 || ram_data==0 || ram_data>4)fail(3);
       else begin result_count<=ram_data[2:0];phase<=1;string_left<=0;advance;end
      end else begin result_status<={result_status[7:0],ram_data};
       if({result_status[7:0],ram_data}!=16'h0001 && {result_status[7:0],ram_data}!=16'h1000 && {result_status[7:0],ram_data}!=16'h1002)fail(3);else advance;
      end
     end else if(string_left==0)begin
      string_length<=ram_data;string_left<=ram_data;
      if(!kind)result_description_length<=ram_data;
      if(ram_data==0)begin if(kind)fail(3);else finish_string;end
      else if((kind && ram_data>32) || p+{2'd0,ram_data}>=length)fail(kind?4'd3:4'd4);
      else advance;
     end else begin
      if((string_left==1 && ram_data!=0) || (string_left!=1 && ram_data==0))fail(4);
      else if(string_left==1)begin string_left<=0;finish_string;end
      else begin string_left<=string_left-1'b1;advance;end
     end
    end
    RESULT:if(result_ready)begin state<=IDLE;query_pending<=0;end
    default:state<=IDLE;
   endcase
  end
 end
endmodule
