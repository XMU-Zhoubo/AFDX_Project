// C33 v2 tag32 storage bridge. Request API remains C32; wire header11 bytes and every response starts with the same BE32 tag.
// C32 byte storage bridge. Same 23-pin external link as C31, no file-system.
// Header: op, object=0, offset BE16, length BE16, final. OPEN1/WRITE2/READ3/STAT4.
// Response: status; READ bytes or STAT {flags,lengthBE16}; LAST terminates.
module storage_epoch_if (
 input wire clk,rst_n,epoch_change_allowed,input wire req_valid,output wire req_ready,input wire [2:0] req_op,
 input wire [3:0] req_object,input wire [16:0] req_offset,input wire [9:0] req_length,input wire req_final,
 input wire [7:0] s_data,input wire s_valid,s_last,output wire s_ready,
 output wire [7:0] m_data,output wire m_valid,m_last,input wire m_ready,
 output wire result_valid,input wire result_ready,output reg result_error,
 output reg [7:0] result_flags,output reg [16:0] result_size,input wire cancel,
 input wire h_valid,h_write,input wire [9:0] h_address,input wire [31:0] h_data,
 output wire h_ready,output reg h_result_valid,input wire h_result_ready,
 output reg h_error,output reg [31:0] h_result,input wire [511:0] diagnostics,input wire [159:0] event_diagnostics,
 output reg [31:0] timeout_cycles,output reg cancel_request,
 output wire [7:0] store_tx_data,output wire store_tx_valid,store_tx_last,input wire store_tx_ready,
 input wire [7:0] store_rx_data,input wire store_rx_valid,store_rx_last,output wire store_rx_ready,
 output reg store_cancel
);
 localparam IDLE=0,HEADER=1,WRITE=2,STATUS=3,READ=4,META=5,RESULT=6,TAG=7,SKIP=8;
 reg [3:0] state,header_index;reg [2:0] operation;
 reg epoch_valid;reg [15:0] epoch;reg [3:0] host_object;
 reg [31:0] nonce,expected_tag,received_tag,stale_responses;reg [1:0] tag_index;reg host,final_block;reg [3:0] object_id;
 reg [16:0] offset;reg [16:0] host_base;reg [31:0] metadata_size;reg [9:0] length,index;reg [31:0] operation_age;
 wire host_byte=!h_write && h_address>=32 && h_address<544;
 wire [17:0] request_end={1'b0,req_offset}+{8'd0,req_length};
 wire extended=object_id>=5;
 wire [16:0] capacity=req_object==6?17'd65536:req_object==5?17'd37:req_object==0?17'd4096:17'd512;
 wire [87:0] command={5'd0,operation,4'd0,object_id,offset[15:0],6'd0,length,7'd0,final_block,expected_tag};
 wire [103:0] wide_command={1'b1,4'd0,operation,4'd0,object_id,15'd0,offset,6'd0,length,7'd0,final_block,expected_tag};
 wire [3:0] header_end=extended?4'd12:4'd10;
 wire epoch_write=h_valid && h_write && h_address==19;
 assign req_ready=rst_n && state==IDLE && !epoch_write;
 assign h_ready=rst_n && !h_result_valid && (!host_byte || (state==IDLE && !req_valid));
 assign s_ready=rst_n && state==WRITE && store_tx_ready;
 assign result_valid=rst_n && state==RESULT && !host;
 assign m_data=store_rx_data;assign m_valid=rst_n && state==READ && !host && store_rx_valid;
 assign m_last=index+1'b1==length;
 assign store_tx_valid=rst_n && (state==HEADER || (state==WRITE && s_valid));
 assign store_tx_data=state==HEADER?(extended?wide_command[103-header_index*8-:8]:command[87-header_index*8-:8]):s_data;
 assign store_tx_last=state==HEADER?(header_index==header_end && (operation!=2 || length==0)):(index+1'b1==length);
 assign store_rx_ready=rst_n && (state==TAG || state==SKIP || state==STATUS || state==META || (state==READ && (host || m_ready)));
 always @(posedge clk)begin
  if(!rst_n)begin object_id<=0; state<=IDLE;host<=0;operation<=0;header_index<=0;offset<=0;host_base<=0;length<=0;index<=0;final_block<=0;
   h_result_valid<=0;h_error<=0;h_result<=0;result_error<=0;result_flags<=0;result_size<=0;metadata_size<=0;
   epoch_valid<=0;epoch<=0;host_object<=0;timeout_cycles<=1600000000;nonce<=1;expected_tag<=0;received_tag<=0;tag_index<=0;stale_responses<=0;cancel_request<=0;store_cancel<=0;operation_age<=0;end
  else begin
   cancel_request<=0;store_cancel<=0;
   if(state==IDLE || state==RESULT)operation_age<=0;else operation_age<=operation_age+1'b1;
   if(h_result_valid && h_result_ready)h_result_valid<=0;
   if(h_valid && h_ready)begin
    if(host_byte)begin
     host<=1;object_id<=host_object;operation<=3;expected_tag<=nonce;nonce<=nonce+1'b1;if(nonce[15:0]==16'hffff)epoch_valid<=0;tag_index<=0;offset<=host_base+{7'd0,h_address}-17'd32;length<=1;index<=0;header_index<=0;final_block<=0;
     if(!epoch_valid || {1'b0,host_base}+{8'd0,h_address}-18'd32>=(host_object==6?18'd65536:host_object==5?18'd37:18'd4096))begin h_error<=1;h_result<=0;h_result_valid<=1;end else state<=HEADER;
    end else begin
     h_result_valid<=1;h_error<=0;h_result<=0;
     if(h_write)begin
      if(h_address==16 && h_data>=1000 && h_data<=2000000000)timeout_cycles<=h_data;
      else if(h_address==17 && h_data==1)cancel_request<=1;
      else if(h_address==18 && h_data<=65535)host_base<=h_data[16:0];
      else if(h_address==22 && (h_data==0 || h_data==5 || h_data==6))host_object<=h_data[3:0];
      else if(h_address==19 && state==IDLE && epoch_change_allowed && h_data!=0 && h_data<=65535 && h_data[15:0]!=epoch)begin
       epoch<=h_data[15:0];nonce<={h_data[15:0],16'd1};epoch_valid<=1;
      end else h_error<=1;
     end else if(h_address<16)h_result<=diagnostics[h_address*32+:32];
     else if(h_address==16)h_result<=timeout_cycles;else if(h_address==28)h_result<=stale_responses;
     else if(h_address==19)h_result<={16'd0,epoch};else if(h_address==20)h_result<=nonce;else if(h_address==21)h_result<={31'd0,epoch_valid};else if(h_address==22)h_result<={28'd0,host_object};else if(h_address==18)h_result<={15'd0,host_base};else if(h_address>=23 && h_address<=27)h_result<=event_diagnostics[(h_address-23)*32+:32];else h_error<=1;
    end
   end
   case(state)
    IDLE:if(req_valid && req_ready)begin
     host<=0;object_id<=req_object;operation<=req_op;expected_tag<=nonce;nonce<=nonce+1'b1;if(nonce[15:0]==16'hffff)epoch_valid<=0;tag_index<=0;offset<=req_offset;length<=req_length;final_block<=req_final;
     index<=0;header_index<=0;result_error<=0;result_flags<=0;result_size<=0;metadata_size<=0;
     if(!epoch_valid || req_op<1 || req_op>7 || req_length>512 || req_object>10 || request_end>{1'b0,capacity} || (req_object>=5 && req_object<=6 && !(req_op==3 || req_op==4 || req_op==6 || req_op==7)) || ((req_op==6 || req_op==7) && !(req_object==5 || req_object==6)) ||
       ((req_op==1 || req_op==4 || req_op==5 || req_op==6 || req_op==7) && (req_length!=0 || req_offset!=0)) || (req_op==3 && req_length==0))begin result_error<=1;state<=RESULT;end
     else state<=HEADER;
    end
    HEADER:if(store_tx_valid && store_tx_ready)begin
     if(header_index==header_end)begin if(operation==2 && length!=0)state<=WRITE;else state<=TAG;end
     else header_index<=header_index+1'b1;
    end
    WRITE:if(s_valid && s_ready)begin
     if(s_last!=(index+1'b1==length))begin result_error<=1;store_cancel<=1;state<=RESULT;end
     else if(s_last)state<=TAG;else index<=index+1'b1;
    end
    TAG:if(store_rx_valid && store_rx_ready)begin
     received_tag<={received_tag[23:0],store_rx_data};
     if(store_rx_last)begin stale_responses<=stale_responses+1'b1;tag_index<=0;end
     else if(tag_index==3)begin
      tag_index<=0;
      if({received_tag[23:0],store_rx_data}==expected_tag)state<=STATUS;
      else begin stale_responses<=stale_responses+1'b1;state<=SKIP;end
     end else tag_index<=tag_index+1'b1;
    end
    SKIP:if(store_rx_valid && store_rx_ready && store_rx_last)begin tag_index<=0;state<=TAG;end
    STATUS:if(store_rx_valid && store_rx_ready)begin
     if(store_rx_data!=0 || store_rx_last!=(operation!=3 && operation!=4))begin
      if(host)begin h_error<=1;h_result<=0;h_result_valid<=1;state<=IDLE;end
      else begin result_error<=1;state<=RESULT;end
      if(!store_rx_last)store_cancel<=1;
     end else if(operation==3)begin index<=0;state<=READ;end
     else if(operation==4)begin index<=0;state<=META;end
     else state<=RESULT;
    end
    READ:if(store_rx_valid && store_rx_ready)begin
     if(host)begin h_result<={24'd0,store_rx_data};h_error<=!store_rx_last;h_result_valid<=1;state<=IDLE;end
     else if(store_rx_last!=(index+1'b1==length))begin result_error<=1;store_cancel<=1;state<=RESULT;end
     else if(store_rx_last)state<=RESULT;else index<=index+1'b1;
    end
    META:if(store_rx_valid && store_rx_ready)begin
     if(index==0)result_flags<=store_rx_data;
     else if(extended)metadata_size<={metadata_size[23:0],store_rx_data};
     else if(index==1)result_size[15:8]<=store_rx_data;else result_size[7:0]<=store_rx_data;
     if(store_rx_last!=(index==(extended?4:2)))begin result_error<=1;store_cancel<=1;state<=RESULT;end
     else if(store_rx_last)begin
      if(extended)begin
       if({metadata_size[23:0],store_rx_data}>65536)result_error<=1;
       else result_size<={metadata_size[8:0],store_rx_data};
      end
      state<=RESULT;
     end else index<=index+1'b1;
    end
    RESULT:if(result_ready)state<=IDLE;
    default:state<=IDLE;
   endcase
   // Cancel is also a session invalidation signal: an adapter must invalidate
   // an OPEN but unfinished object even when no byte operation is outstanding.
   if(cancel)begin store_cancel<=1;
    if(host && state!=IDLE)begin h_result_valid<=1;h_error<=1;h_result<=0;end
    state<=IDLE;
   end else if(state!=IDLE && state!=RESULT && operation_age>=timeout_cycles)begin
    store_cancel<=1;if(host)begin state<=IDLE;h_result_valid<=1;h_error<=1;h_result<=0;end
    else begin state<=RESULT;result_error<=1;end
   end
  end
 end
endmodule
