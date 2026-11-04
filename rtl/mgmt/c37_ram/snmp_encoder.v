// Metadata-driven bounded encoder. Builds backwards into 512-byte buffer;
// publishes no output until the entire message has been checked and built.
module snmp_encoder (
 input wire clk,rst_n,cancel,
 input wire w_valid,output wire w_ready,input wire [11:0] w_address,input wire [31:0] w_data,
 input wire start_valid,output wire start_ready,
 output wire [7:0] m_data,output wire m_valid,input wire m_ready,output wire m_last,
 output wire result_valid,input wire result_ready,output reg [3:0] result_error,output reg [9:0] result_length
);
 localparam [7:0] IDLE=0,GLOBAL=1,GLOBAL_GOT=2,CHECK=3,VB=4,VB_FIELDS=5,VB_GOT=6,VALUE=7,
 VALUE_PREFIX=8,NAME=9,VB_PREFIX=10,VB_FINISH=11,LIST_PREFIX=12,AFTER_LIST=13,
 COMMON=14,COMMON_GOT=15,COMMON_NEXT=16,TRAP=17,TRAP_NEXT=18,PDU_PREFIX=19,
 COMMUNITY=20,COMM_PREFIX=21,VERSION=22,VERSION_PREFIX=23,OUTER=24,DONE=25,OUTPUT=26,RESULT=27,
 READ0=32,READ1=33,PUT=34,PREFIX=35,PREFIX_MORE=36,
 NUMBER=40,NUMBER_MORE=41,NUMBER_DONE=42,
 STR=44,STR_GOT=45,STR_DONE=46,
 OID=48,OID0=49,OID1=50,OID_ARC=51,OID_GOT=52,OID_GROUP=53,OID_MORE=54,OID_DONE=55,
 IP=56,IP_NEXT=57,OUT_READ=58;
 reg [7:0] state,read_return,put_return,prefix_return,number_return,str_return,oid_return;
 reg [31:0] objects[0:4095];(* ramstyle = "M4K" *) reg [7:0] bytes[0:511];
 reg [11:0] read_address;reg [31:0] read_data,word;
 reg [7:0] emit_byte;reg [9:0] ptr,out_ptr;
 reg [3:0] global_index;reg [31:0] meta[0:10];
 reg [3:0] vb_index;reg [1:0] vb_field;
 reg [11:0] vb_base;reg [31:0] oid_size,value_tag,value_size,value_num;
 reg [9:0] pdu_mark,list_mark,vb_mark,field_mark;
 reg [7:0] prefix_tag;reg [15:0] prefix_size;reg [2:0] prefix_step;
 reg [31:0] number;reg number_unsigned;reg [7:0] number_tag,number_byte;
 reg [11:0] str_base;reg [15:0] str_left;
 reg [11:0] oid_base;reg [5:0] oid_count,oid_index;reg [31:0] arc0;
 reg [32:0] subid,first_subid;reg oid_last_group;
 reg [1:0] common_index,trap_index,ip_index;
 reg [31:0] ip_value;
 wire [3:0] previous_vb=vb_index-4'd1;
 task fail;input [3:0] reason;begin result_error<=reason;state<=RESULT;end endtask
 task get;input [11:0] address;input [7:0] ret;
 begin read_address<=address;read_return<=ret;state<=READ0;end endtask
 task put;input [7:0] b;input [7:0] ret;
 begin emit_byte<=b;put_return<=ret;state<=PUT;end endtask
 task prefix;input [7:0] tag;input [15:0] len;input [7:0] ret;
 begin prefix_tag<=tag;prefix_size<=len;prefix_step<=0;prefix_return<=ret;state<=PREFIX;end endtask
 task encode_number;input [31:0] n;input u;input [7:0] tag,ret;
 begin number<=n;number_unsigned<=u;number_tag<=tag;number_return<=ret;field_mark<=ptr;state<=NUMBER;end endtask
 task encode_string;input [11:0] base;input [15:0] count;input [7:0] ret;
 begin str_base<=base;str_left<=count;str_return<=ret;state<=STR;end endtask
 task encode_oid;input [11:0] base;input [5:0] count;input [7:0] ret;
 begin oid_base<=base;oid_count<=count;oid_return<=ret;field_mark<=ptr;state<=OID;end endtask
 assign w_ready=rst_n && state==IDLE && !start_valid && !cancel;
 assign start_ready=rst_n && state==IDLE && !cancel;
 assign m_valid=rst_n && state==OUTPUT && !cancel;
 reg [7:0] output_byte;
 assign m_data=output_byte;
 assign m_last=out_ptr==511;
 assign result_valid=rst_n && !cancel && state==RESULT;
 always @(posedge clk)begin
  if(state==OUT_READ && rst_n && !cancel)output_byte<=bytes[out_ptr[8:0]];
  if(w_valid && w_ready)objects[w_address]<=w_data;
  if(state==READ0 && rst_n && !cancel)read_data<=objects[read_address];
  if(state==PUT && ptr!=0 && rst_n && !cancel)bytes[ptr[8:0]-9'd1]<=emit_byte;
 end
 integer i;
 always @(posedge clk)begin
  if(!rst_n)begin
   state<=IDLE;result_error<=0;result_length<=0;ptr<=512;out_ptr<=0;
   read_address<=0;read_return<=0;word<=0;emit_byte<=0;put_return<=0;
   global_index<=0;vb_index<=0;vb_field<=0;vb_base<=128;oid_size<=0;value_tag<=0;value_size<=0;value_num<=0;
   pdu_mark<=0;list_mark<=0;vb_mark<=0;field_mark<=0;
   prefix_tag<=0;prefix_size<=0;prefix_step<=0;prefix_return<=0;
   number<=0;number_unsigned<=0;number_tag<=0;number_return<=0;number_byte<=0;
   str_base<=0;str_left<=0;str_return<=0;oid_base<=0;oid_count<=0;oid_index<=0;arc0<=0;subid<=0;first_subid<=0;oid_last_group<=1;oid_return<=0;
   common_index<=0;trap_index<=0;ip_index<=0;ip_value<=0;
   for(i=0;i<11;i=i+1)meta[i]<=0;
  end else if(cancel && state!=IDLE)begin result_error<=9;state<=RESULT;end
  else case(state)
   IDLE:if(start_valid && start_ready)begin
    result_error<=0;result_length<=0;ptr<=512;global_index<=0;state<=GLOBAL;
   end
   GLOBAL:get({8'd0,global_index},GLOBAL_GOT);
   GLOBAL_GOT:begin meta[global_index]<=word;
    if(global_index==10)state<=CHECK;else begin global_index<=global_index+1'b1;state<=GLOBAL;end
   end
   CHECK:if(meta[0]<8'ha0 || meta[0]>8'ha4)fail(4);
    else if(meta[4]>32 || meta[5]>8 || meta[2]>5 || (meta[0]==8'ha4 &&
      (meta[6]<2 || meta[6]>32 || meta[8]>6 || meta[9][31])))fail(3);
    else begin pdu_mark<=ptr;list_mark<=ptr;vb_index<=meta[5][3:0];state<=VB;end
   VB:if(vb_index==0)state<=LIST_PREFIX;
    else begin vb_index<=previous_vb;vb_base<=12'd128+{previous_vb,8'd0}+{1'b0,previous_vb,7'd0};vb_field<=0;vb_mark<=ptr;state<=VB_FIELDS;end
   VB_FIELDS:get(vb_base+vb_field,VB_GOT);
   VB_GOT:begin
    case(vb_field)0:oid_size<=word;1:value_tag<=word;2:value_size<=word;3:value_num<=word;endcase
    if(vb_field==3)state<=VALUE;else begin vb_field<=vb_field+1'b1;state<=VB_FIELDS;end
   end
   VALUE:if(oid_size<2 || oid_size>32)fail(3);
    else if(value_tag==2 || value_tag==8'h41 || value_tag==8'h42 || value_tag==8'h43)
      encode_number(value_num,value_tag!=2,value_tag[7:0],NAME);
    else if(value_tag==5)begin if(value_size!=0)fail(2);else prefix(5,0,NAME);end
    else if(value_tag==6)begin
     if(value_size<2 || value_size>32)fail(3);else encode_oid(vb_base+36,value_size[5:0],NAME);
    end else if(value_tag==4 || value_tag==8'h40 || value_tag==8'h44)begin
     if(value_size>256)fail(3);else if(value_tag==8'h40 && value_size!=4)fail(2);
     else begin encode_string(vb_base+68,value_size[15:0],VALUE_PREFIX);end
    end else fail(4);
   VALUE_PREFIX:prefix(value_tag[7:0],value_size[15:0],NAME);
   NAME:encode_oid(vb_base+4,oid_size[5:0],VB_PREFIX);
   VB_PREFIX:prefix(8'h30,{6'd0,vb_mark}-{6'd0,ptr},VB_FINISH);
   VB_FINISH:state<=VB;
   LIST_PREFIX:prefix(8'h30,{6'd0,list_mark}-{6'd0,ptr},AFTER_LIST);
   AFTER_LIST:begin common_index<=2;trap_index<=0;state<=meta[0]==8'ha4 ? TRAP:COMMON;end
   COMMON:case(common_index)
    2:encode_number(meta[3],0,2,COMMON_NEXT);
    1:encode_number(meta[2],0,2,COMMON_NEXT);
    default:encode_number(meta[1],0,2,COMMON_NEXT);
   endcase
   COMMON_NEXT:if(common_index==0)state<=PDU_PREFIX;else begin common_index<=common_index-1'b1;state<=COMMON;end
   TRAP:case(trap_index)
    0:encode_number(meta[10],1,8'h43,TRAP_NEXT);
    1:encode_number(meta[9],0,2,TRAP_NEXT);
    2:encode_number(meta[8],0,2,TRAP_NEXT);
    3:begin ip_value<=meta[7];ip_index<=0;state<=IP;end
   endcase
   TRAP_NEXT:if(trap_index==3)encode_oid(48,meta[6][5:0],PDU_PREFIX);
    else begin trap_index<=trap_index+1'b1;state<=TRAP;end
   IP:begin put(ip_value[7:0],IP_NEXT);ip_value<={8'd0,ip_value[31:8]};end
   IP_NEXT:if(ip_index==3)prefix(8'h40,4,TRAP_NEXT);else begin ip_index<=ip_index+1'b1;state<=IP;end
   PDU_PREFIX:prefix(meta[0][7:0],{6'd0,pdu_mark}-{6'd0,ptr},COMMUNITY);
   COMMUNITY:encode_string(16,meta[4][15:0],COMM_PREFIX);
   COMM_PREFIX:prefix(4,meta[4][15:0],VERSION);
   VERSION:encode_number(0,0,2,OUTER);
   OUTER:prefix(8'h30,16'd512-{6'd0,ptr},DONE);
   DONE:begin result_length<=10'd512-ptr;out_ptr<=ptr;state<=OUT_READ;end
   OUT_READ:state<=OUTPUT;
   OUTPUT:if(m_ready)begin if(out_ptr==511)state<=RESULT;else begin out_ptr<=out_ptr+1'b1;state<=OUT_READ;end end
   RESULT:if(result_ready)state<=IDLE;
   READ0:state<=READ1;
   READ1:begin word<=read_data;state<=read_return;end
   PUT:if(ptr==0)fail(3);else begin ptr<=ptr-1'b1;state<=put_return;end
   PREFIX:begin
    prefix_step<=prefix_step+1'b1;
    if(prefix_size<128)begin
     if(prefix_step==0)put(prefix_size[7:0],PREFIX);else put(prefix_tag,prefix_return);
    end else if(prefix_size<256)begin
     case(prefix_step)0:put(prefix_size[7:0],PREFIX);1:put(8'h81,PREFIX);default:put(prefix_tag,prefix_return);endcase
    end else begin
     case(prefix_step)0:put(prefix_size[7:0],PREFIX);1:put(prefix_size[15:8],PREFIX);2:put(8'h82,PREFIX);default:put(prefix_tag,prefix_return);endcase
    end
   end
   NUMBER:begin number_byte<=number[7:0];put(number[7:0],NUMBER_MORE);end
   NUMBER_MORE:begin
    if(number_unsigned)begin
     if(number[31:8]==0)begin
      if(number_byte[7])put(0,NUMBER_DONE);else state<=NUMBER_DONE;
     end else begin number<={8'd0,number[31:8]};state<=NUMBER;end
    end else if((number[31:8]==0 && !number_byte[7]) || (number[31:8]==24'hffffff && number_byte[7]))state<=NUMBER_DONE;
    else begin number<={{8{number[31]}},number[31:8]};state<=NUMBER;end
   end
   NUMBER_DONE:prefix(number_tag,{6'd0,field_mark}-{6'd0,ptr},number_return);
   STR:if(str_left==0)state<=str_return;else get(str_base+str_left-1'b1,STR_GOT);
   STR_GOT:if(word>255)fail(3);else begin str_left<=str_left-1'b1;put(word[7:0],STR);end
   OID:if(oid_count<2 || oid_count>32)fail(3);else get(oid_base,OID0);
   OID0:if(word>2)fail(3);else begin arc0<=word;get(oid_base+1,OID1);end
   OID1:if(arc0<2 && word>39)fail(3);
    else begin first_subid<=({1'b0,arc0}<<5)+({1'b0,arc0}<<3)+{1'b0,word};oid_index<=oid_count-1'b1;state<=OID_ARC;end
   OID_ARC:begin
    oid_last_group<=1;
    if(oid_index==1)begin subid<=first_subid;state<=OID_GROUP;end
    else get(oid_base+oid_index,OID_GOT);
   end
   OID_GOT:begin subid<={1'b0,word};state<=OID_GROUP;end
   OID_GROUP:begin put({!oid_last_group,subid[6:0]},OID_MORE);subid<=subid>>7;oid_last_group<=0;end
   OID_MORE:if(subid!=0)state<=OID_GROUP;
    else if(oid_index==1)state<=OID_DONE;else begin oid_index<=oid_index-1'b1;state<=OID_ARC;end
   OID_DONE:prefix(6,{6'd0,field_mark}-{6'd0,ptr},oid_return);
   default:fail(8);
  endcase
 end
endmodule
