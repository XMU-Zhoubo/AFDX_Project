// Bounded SNMPv1 BER reader. Completed object file is held until release.
// No record is authoritative before successful m_valid handshake.
module snmp_decoder (
 input wire clk,rst_n,cancel,
 input wire [7:0] s_data,input wire s_valid,s_last,output wire s_ready,
 output wire m_valid,input wire m_ready,output reg [3:0] m_error,
 output reg [9:0] m_length,output reg [7:0] m_pdu,output reg [3:0] m_count,
 input wire release_valid,
 input wire q_valid,output wire q_ready,input wire [11:0] q_address,
 output reg q_result_valid,input wire q_result_ready,output reg [31:0] q_data
);
 localparam [7:0] COLLECT=0,DRAIN=1,CLEAR=2,BEGIN_MSG=3,OUTER=4,VERSION=5,VERSION_DONE=6,
 COMMUNITY=7,COMM_COPY=8,PDU=9,COMMON=10,COMMON_DONE=11,TRAP_OID=12,
 TRAP_AGENT=13,AGENT_COPY=14,TRAP_NUM=15,TRAP_NUM_DONE=16,VBL=17,VB_NEXT=18,
 VB_SEQ=19,NAME=20,VALUE=21,VALUE_DONE=22,VB_DONE=23,ALL_DONE=24,
 FINISH=25,RESULT=26,HELD=27,STORE=28,
 TL_TAG=32,TL_LENGTH=33,TL_LONG=34,TL_CHECK=35,
 NUM_BEGIN=40,NUM_BYTE=41,NUM_DONE=42,
 OID_BEGIN=48,OID_BYTE=49,OID_SPLIT=50,OID_SECOND=51,OID_DONE=52,
 BYTES=56,BYTES_DONE=57;
 reg [7:0] state,tl_return,num_return,oid_return,bytes_return,store_return;
 (* ramstyle = "M4K" *) reg [7:0] raw[0:511];
 reg [31:0] objects[0:4095];
 reg [9:0] collected;
 reg [3:0] pending_error;
 reg [15:0] pos,limit,outer_end,pdu_end,list_end,vb_end;
 reg [7:0] byte_in;reg [15:0] read_pos;
 reg [7:0] tag;
 reg [15:0] size,content_end;
 reg [1:0] length_left;
 reg [11:0] store_address;reg [31:0] store_data;
 reg [4:0] clear_index;
 reg [3:0] vb_index;reg [1:0] field;
 reg [11:0] vb_base;
 reg [31:0] number,accumulator,agent;
 reg number_unsigned;
 reg [15:0] number_left;
 reg [7:0] first_byte;reg [2:0] number_index;
 reg [32:0] oid_acc,combined;
 reg [2:0] oid_groups;
 reg [5:0] oid_count;
 reg oid_first;
 reg [11:0] oid_base,oid_count_address;
 reg [11:0] bytes_base,bytes_size_address;
 reg [15:0] bytes_index,bytes_size;
 wire need_byte=((state==TL_TAG || state==TL_LENGTH || state==TL_LONG) && pos<limit) ||
   state==AGENT_COPY || state==NUM_BYTE || (state==OID_BYTE && pos<content_end) ||
   (state==BYTES && bytes_index<bytes_size);
 wire fetch_byte=rst_n && !cancel && need_byte && pos<512 && pos<m_length && read_pos!=pos;
 task fail; input [3:0] reason;begin m_error<=reason;state<=FINISH;end endtask
 task read_tlv;input [7:0] ret;begin tl_return<=ret;state<=TL_TAG;end endtask
 task store;input [11:0] address;input [31:0] data;input [7:0] ret;
 begin store_address<=address;store_data<=data;store_return<=ret;state<=STORE;end endtask
 task read_number;input u;input [7:0] ret;
 begin number_unsigned<=u;num_return<=ret;state<=NUM_BEGIN;end endtask
 task read_oid;input [11:0] base,count_address;input [7:0] ret;
 begin oid_base<=base;oid_count_address<=count_address;oid_return<=ret;state<=OID_BEGIN;end endtask
 task read_bytes;input [11:0] base,size_address;input [7:0] ret;
 begin bytes_base<=base;bytes_size_address<=size_address;bytes_return<=ret;bytes_index<=0;bytes_size<=size;state<=BYTES;end endtask
 assign s_ready=rst_n && (state==COLLECT || state==DRAIN) && !cancel;
 assign m_valid=rst_n && !cancel && state==RESULT;
 assign q_ready=rst_n && !cancel && !release_valid && (state==RESULT || state==HELD) && m_error==0 && (!q_result_valid || q_result_ready);
 // Unreset synchronous RAM ports, both on THIS clk. Parser writes in STORE;
 // public reads only after completion, so simultaneous same-address RDW is
 // structurally impossible even if the mapper names its primitive dual-clock.
 always @(posedge clk)begin
  if(fetch_byte)byte_in<=raw[pos[8:0]];
  if(q_valid && q_ready)q_data<=objects[q_address];
  if(state==STORE && rst_n && !cancel)objects[store_address]<=store_data;
  if(s_valid && s_ready && state==COLLECT && collected<512)raw[collected[8:0]]<=s_data;
 end
 always @(posedge clk)begin
  if(!rst_n || cancel || state==COLLECT)read_pos<=16'hffff;
  else if(fetch_byte)read_pos<=pos;
 end
 always @(posedge clk)begin
  if(!rst_n)begin q_result_valid<=0;end
  else begin
   if(q_result_valid && q_result_ready)q_result_valid<=0;
   if(q_valid && q_ready)q_result_valid<=1;
   if(cancel)q_result_valid<=0;
  end
 end
 always @(posedge clk)begin
  if(!rst_n)begin
   state<=COLLECT;collected<=0;pending_error<=0;m_error<=0;m_length<=0;m_pdu<=0;m_count<=0;
   pos<=0;limit<=0;outer_end<=0;pdu_end<=0;list_end<=0;vb_end<=0;
   tag<=0;size<=0;content_end<=0;length_left<=0;clear_index<=0;vb_index<=0;field<=0;vb_base<=128;
   store_address<=0;store_data<=0;store_return<=0;tl_return<=0;num_return<=0;oid_return<=0;bytes_return<=0;
   number<=0;accumulator<=0;agent<=0;number_unsigned<=0;number_left<=0;first_byte<=0;number_index<=0;
   oid_acc<=0;combined<=0;oid_groups<=0;oid_count<=0;oid_first<=1;oid_base<=0;oid_count_address<=0;
   bytes_base<=0;bytes_size_address<=0;bytes_index<=0;bytes_size<=0;
  end else if(cancel)begin
   if(state==DRAIN)pending_error<=9;
   else if(state==COLLECT && collected!=0)begin state<=DRAIN;pending_error<=9;end
   else if(state!=COLLECT)begin m_error<=9;state<=FINISH;end
  end else if(need_byte && (pos>=512 || pos>=m_length))fail(1);
  else if(need_byte && read_pos!=pos)begin end
  else case(state)
   COLLECT:if(s_valid && s_ready)begin
    if(collected==0)begin m_error<=0;m_pdu<=0;m_count<=0;end
    if(collected==512)begin
     m_length<=513;pending_error<=3;
     if(s_last)fail(3);else state<=DRAIN;
    end else begin
     collected<=collected+1'b1;
     if(s_last)begin m_length<=collected+1'b1;clear_index<=0;state<=CLEAR;end
    end
   end
   DRAIN:if(s_valid && s_ready && s_last)fail(pending_error);
   CLEAR:begin
    store(clear_index,0,clear_index==10?BEGIN_MSG:CLEAR);clear_index<=clear_index+1'b1;
   end
   BEGIN_MSG:begin pos<=0;limit<={6'd0,m_length};vb_index<=0;read_tlv(OUTER);end
   OUTER:if(tag!=8'h30)fail(5);else if(content_end!=m_length)fail(1);
    else begin outer_end<=content_end;limit<=content_end;read_tlv(VERSION);end
   VERSION:if(tag!=2)fail(5);else read_number(0,VERSION_DONE);
   VERSION_DONE:if(number!=0)fail(6);else read_tlv(COMMUNITY);
   COMMUNITY:if(tag!=4)fail(5);else if(size>32)fail(3);
    else read_bytes(16,4,COMM_COPY);
   COMM_COPY:read_tlv(PDU);
   PDU:if(tag<8'ha0 || tag>8'ha4)fail(4);else if(content_end!=outer_end)fail(1);
    else begin m_pdu<=tag;pdu_end<=content_end;limit<=content_end;field<=0;
     store(0,{24'd0,tag},tag==8'ha4 ? TRAP_OID:COMMON);end
   COMMON:read_tlv(COMMON_DONE);
   COMMON_DONE:begin
    if(tag!=2)fail(5);
    else if(field==0)begin read_number(0,NUM_DONE+32);end
    else if(field==1)begin read_number(0,NUM_DONE+33);end
    else begin read_number(0,NUM_DONE+34);end
   end
   74:begin field<=1;store(1,number,COMMON);end
   75:if(number>5)fail(3);else begin field<=2;store(2,number,COMMON);end
   76:store(3,number,VBL);
   TRAP_OID:read_tlv(77);
   77:if(tag!=6)fail(5);else read_oid(48,6,TRAP_AGENT);
   TRAP_AGENT:read_tlv(78);
   78:if(tag!=8'h40)fail(5);else if(size!=4)fail(2);
    else begin agent<=0;field<=0;state<=AGENT_COPY;end
   AGENT_COPY:begin
    agent<={agent[23:0],byte_in};pos<=pos+1'b1;
    if(field==3)begin field<=0;store(7,{agent[23:0],byte_in},TRAP_NUM);end
    else field<=field+1'b1;
   end
   TRAP_NUM:read_tlv(TRAP_NUM_DONE);
   TRAP_NUM_DONE:if(tag!=(field==2?8'h43:8'h02))fail(5);else read_number(field==2,79);
   79:if((field==0 && number>6) || (field==1 && number[31]))fail(3);
    else begin field<=field+1'b1;store(8+field,number,field==2?VBL:TRAP_NUM);end
   VBL:read_tlv(80);
   80:if(tag!=8'h30)fail(5);else if(content_end!=pdu_end)fail(1);
    else begin list_end<=content_end;limit<=content_end;state<=VB_NEXT;end
   VB_NEXT:if(pos==list_end)begin m_count<=vb_index;store(5,{28'd0,vb_index},ALL_DONE);end
    else if(vb_index==8)fail(3);
    else begin vb_base<=12'd128+({8'd0,vb_index}<<8)+({8'd0,vb_index}<<7);read_tlv(VB_SEQ);end
   VB_SEQ:if(tag!=8'h30)fail(5);else begin vb_end<=content_end;limit<=content_end;read_tlv(NAME);end
   NAME:if(tag!=6)fail(5);else read_oid(vb_base+4,vb_base,81);
   81:read_tlv(VALUE);
   VALUE:begin
    store(vb_base+1,{24'd0,tag},82);
   end
   82:begin
    if(tag==2 || tag==8'h41 || tag==8'h42 || tag==8'h43)read_number(tag!=2,83);
    else if(tag==5)begin if(size!=0)fail(2);else store(vb_base+2,0,84);end
    else if(tag==6)begin store(vb_base+3,0,85);end
    else if(tag==4 || tag==8'h40 || tag==8'h44)begin
     if(tag==8'h40 && size!=4)fail(2);else if(size>256)fail(3);else store(vb_base+3,0,86);
    end else fail(4);
   end
   83:store(vb_base+3,number,87);
   87:store(vb_base+2,0,VALUE_DONE);
   84:store(vb_base+3,0,VALUE_DONE);
   85:read_oid(vb_base+36,vb_base+2,VALUE_DONE);
   86:read_bytes(vb_base+68,vb_base+2,VALUE_DONE);
   VALUE_DONE:if(pos!=vb_end)fail(1);else begin vb_index<=vb_index+1'b1;limit<=list_end;state<=VB_NEXT;end
   ALL_DONE:if(pos!=m_length)fail(1);else state<=FINISH;
   FINISH:state<=RESULT;
   RESULT:if(m_ready)state<=HELD;
   HELD:if(release_valid && !q_result_valid)begin state<=COLLECT;collected<=0;end
   STORE:state<=store_return;
   TL_TAG:if(pos>=limit)fail(1);else begin tag<=byte_in;pos<=pos+1'b1;state<=TL_LENGTH;end
   TL_LENGTH:if(pos>=limit)fail(1);else begin
    pos<=pos+1'b1;
    if(!byte_in[7])begin size<={9'd0,byte_in[6:0]};state<=TL_CHECK;end
    else if(byte_in==8'h80 || byte_in==8'hff)fail(2);
    else if(byte_in>8'h82)fail(3);
    else begin size<=0;length_left<=byte_in[1:0];state<=TL_LONG;end
   end
   TL_LONG:if(pos>=limit)fail(1);else begin
    size<={size[7:0],byte_in};pos<=pos+1'b1;length_left<=length_left-1'b1;
    if(length_left==1)state<=TL_CHECK;
   end
   TL_CHECK:if({1'b0,pos}+{1'b0,size}>{1'b0,limit})fail(1);
    else begin content_end<=pos+size;state<=tl_return;end
   NUM_BEGIN:if(size==0)fail(2);else if(size>(number_unsigned?5:4))fail(3);
    else begin number_left<=size;number_index<=0;accumulator<=0;state<=NUM_BYTE;end
   NUM_BYTE:begin
    if(number_index==0)begin
     first_byte<=byte_in;
     accumulator<=number_unsigned?{24'd0,byte_in}:{{24{byte_in[7]}},byte_in};
     if(number_unsigned && byte_in[7])fail(3);
    end else accumulator<={accumulator[23:0],byte_in};
    if(number_index==1 && ((first_byte==0 && !byte_in[7]) || (first_byte==255 && byte_in[7])))fail(2);
    else if(number_index==0 && number_unsigned && ((size==5 && byte_in!=0) || byte_in[7]))fail(3);
    else begin
     pos<=pos+1'b1;number_left<=number_left-1'b1;number_index<=number_index+1'b1;
     if(number_left==1)state<=NUM_DONE;
    end
   end
   NUM_DONE:begin number<=accumulator;state<=num_return;end
   OID_BEGIN:if(size==0)fail(2);else begin oid_acc<=0;oid_groups<=0;oid_count<=0;oid_first<=1;state<=OID_BYTE;end
   OID_BYTE:if(pos==content_end)begin if(oid_groups!=0)fail(2);else state<=OID_DONE;end
    else if(oid_groups==0 && byte_in==8'h80)fail(2);
    else if(oid_groups==5 || (oid_acc>(oid_first?33'h02000000:33'h01ffffff)))fail(3);
    else begin
     pos<=pos+1'b1;oid_acc<={oid_acc[25:0],byte_in[6:0]};oid_groups<=oid_groups+1'b1;
     if(!byte_in[7])begin
      if(({oid_acc[25:0],byte_in[6:0]}>(oid_first?33'h10000004f:33'h0ffffffff)))fail(3);
      else if(oid_first)begin combined<={oid_acc[25:0],byte_in[6:0]};state<=OID_SPLIT;end
      else if(oid_count==32)fail(3);
      else begin store(oid_base+oid_count,{oid_acc[24:0],byte_in[6:0]},OID_BYTE);oid_count<=oid_count+1'b1;oid_acc<=0;oid_groups<=0;end
     end
    end
   OID_SPLIT:store(oid_base,combined<40?0:combined<80?1:2,OID_SECOND);
   OID_SECOND:begin
    store(oid_base+1,combined<40?combined[31:0]:combined<80?combined[31:0]-32'd40:combined[31:0]-32'd80,OID_BYTE);
    oid_count<=2;oid_first<=0;oid_acc<=0;oid_groups<=0;
   end
   OID_DONE:store(oid_count_address,{26'd0,oid_count},oid_return);
   BYTES:if(bytes_index==bytes_size)state<=BYTES_DONE;
    else begin store(bytes_base+bytes_index,{24'd0,byte_in},BYTES);pos<=pos+1'b1;bytes_index<=bytes_index+1'b1;end
   BYTES_DONE:store(bytes_size_address,{16'd0,bytes_size},bytes_return);
   default:fail(8);
  endcase
 end
endmodule
