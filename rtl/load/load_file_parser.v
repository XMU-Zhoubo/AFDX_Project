// C35 bounded 615A A4 LUR / canonical 665-3 LUH parser. Actual input bytes,
// synchronous 512B RAM, one numeric/string field at a time. No fixed file template.
module load_file_parser(
 input wire clk,rst_n,start,kind,input wire [9:0] length,
 input wire [7:0] s_data,input wire s_valid,s_last,output wire s_ready,
 output wire result_valid,input wire result_ready,output reg [7:0] error,
 output reg [255:0] filename,part_number,output reg [5:0] name_length,pn_length,
 output reg [15:0] data_length,data_crc,output reg [31:0] load_crc,load_seed);
 localparam IDLE=0,COLLECT=1,FETCH=2,TAKE=3,NUMBER=4,STR_FETCH=5,STR_TAKE=6,RESULT=7;
 reg [3:0] state;reg file_kind;reg [9:0] size,index,cursor;
 reg [5:0] field;reg [3:0] width,taken;reg [63:0] acc;
 reg [9:0] hw_ptr,data_ptr,check_ptr;reg [31:0] words;
 reg [15:0] header_crc;reg [31:0] crc32_state;
 reg [5:0] str_len,str_index,str_content,next_field;reg [2:0] slot;reg nul_end,pad_end;
 wire [7:0] q;
 function [15:0] c16;input [15:0] a;input [7:0] b;integer j;reg [15:0] c;begin c=a^{b,8'd0};for(j=0;j<8;j=j+1)c=c[15]?(c<<1)^16'h1021:c<<1;c16=c;end endfunction
 function [31:0] c32;input [31:0] a;input [7:0] b;integer j;reg [31:0] c;begin c=a^{b,24'd0};for(j=0;j<8;j=j+1)c=c[31]?(c<<1)^32'h04c11db7:c<<1;c32=c;end endfunction
 payload_buffer #(.CAPACITY(512),.ADDR_WIDTH(9)) bytes(.clk(clk),.write_enable(state==COLLECT && s_valid && s_ready),.write_addr(index[8:0]),.write_data(s_data),
 .read_enable(state==FETCH || state==STR_FETCH),.read_addr(cursor[8:0]),.read_data(q));
 assign s_ready=rst_n && state==COLLECT;
 assign result_valid=rst_n && state==RESULT;
 task bad;input [7:0] e;begin error<=e;state<=RESULT;end endtask
 task number;input [5:0] f;input [3:0] n;begin field<=f;width<=n;taken<=0;acc<=0;state<=FETCH;end endtask
 task text;input [2:0] dest;input [5:0] n;input is_nul;input [5:0] following;begin
  slot<=dest;str_len<=n;str_content<=is_nul?n-1'b1:n;str_index<=0;nul_end<=is_nul;pad_end<=!is_nul && n[0];next_field<=following;
  if(dest==0)begin filename<=0;name_length<=is_nul?n-1'b1:n;end
  if(dest==1)begin part_number<=0;pn_length<=is_nul?n-1'b1:n;end
  state<=STR_FETCH;
 end endtask
 always @(posedge clk)begin
  if(!rst_n)begin state<=IDLE;file_kind<=0;size<=0;index<=0;cursor<=0;field<=0;width<=0;taken<=0;acc<=0;hw_ptr<=0;data_ptr<=0;check_ptr<=0;words<=0;
   header_crc<=16'hffff;crc32_state<=32'hffffffff;load_seed<=0;filename<=0;part_number<=0;name_length<=0;pn_length<=0;data_length<=0;data_crc<=0;load_crc<=0;error<=0;
   str_len<=0;str_content<=0;str_index<=0;slot<=0;nul_end<=0;pad_end<=0;next_field<=0;end
  else case(state)
   IDLE:if(start)begin file_kind<=kind;size<=length;index<=0;error<=0;header_crc<=16'hffff;crc32_state<=32'hffffffff;
    if(length<8 || length>512)bad(1);else state<=COLLECT;end
   COLLECT:if(s_valid && s_ready)begin
    if(file_kind && index<size-6)header_crc<=c16(header_crc,s_data);
    if(file_kind && index<size-4)crc32_state<=c32(crc32_state,s_data);
    if(s_last!=(index+1'b1==size))bad(2);
    else if(s_last)begin cursor<=0;number(0,4);end else index<=index+1'b1;
   end
   FETCH:if(cursor>=size)bad(3);else state<=TAKE;
   TAKE:begin acc<={acc[55:0],q};cursor<=cursor+1'b1;if(taken+1'b1==width)state<=NUMBER;else begin taken<=taken+1'b1;state<=FETCH;end end
   NUMBER:case(field)
    0:if(acc!=(file_kind?(size>>1):size))bad(4);else number(1,2);
    1:if(acc!=(file_kind?16'h8004:16'h4134))bad(5);else number(file_kind?2:40,2);
    2:if(acc!=0)bad(6);else number(3,4);
    3:if(acc!=20)bad(7);else number(4,4);
    4:if(acc>255 || acc<20)bad(7);else begin hw_ptr<=acc[8:0]<<1;number(5,4);end
    5:if(acc>255 || acc<20)bad(7);else begin data_ptr<=acc[8:0]<<1;number(6,4);end
    6,7,8,9:if(acc!=0)bad(8);else number(field+1'b1,4);
    10:if(acc>255 || acc<20)bad(7);else begin check_ptr<=acc[8:0]<<1;number(11,2);end
    11:if(acc<1 || acc>31)bad(9);else text(1,acc[5:0],0,13);
    13:if(cursor!=hw_ptr+2 || acc!=1)bad(10);else number(14,2);
    14:if(acc!=4)bad(10);else text(2,4,0,16);
    16:if(cursor!=data_ptr+2 || acc!=1)bad(11);else number(17,2);
    17:if(acc!=0)bad(11);else number(18,2);
    18:if(acc<1 || acc>31)bad(9);else text(0,acc[5:0],0,20);
    20:if(acc<1 || acc>31)bad(9);else text(3,acc[5:0],0,22);
    22:begin words<=acc[31:0];number(23,2);end
    23:begin data_crc<=acc[15:0];number(24,8);end
    24:if(acc>4096 || words!=((acc+1)>>1))bad(12);else begin data_length<=acc[15:0];number(25,2);end
    25:if(acc!=0 || cursor!=check_ptr)bad(13);else number(26,2);
    26:if(acc!=0 || cursor+6!=size)bad(13);else number(27,2);
    27:if(acc!=header_crc)bad(14);else number(28,4);
    28:if(cursor!=size)bad(15);else begin load_crc<=acc[31:0];load_seed<=crc32_state;state<=RESULT;end
    40:if(acc!=1)bad(16);else number(41,1);
    41:if(acc<2 || acc>32)bad(9);else text(0,acc[5:0],1,43);
    43:if(acc<2 || acc>32)bad(9);else text(1,acc[5:0],1,45);
    45:if(cursor!=size)bad(15);else state<=RESULT;
    default:bad(17);
   endcase
   STR_FETCH:if(cursor>=size)bad(3);else state<=STR_TAKE;
   STR_TAKE:begin
    cursor<=cursor+1'b1;str_index<=str_index+1'b1;
    if(str_index<str_content)begin
     if(q<32 || q>126 || (slot==2 && q!=(str_index==0?"A":str_index==1?"F":str_index==2?"D":"X")))bad(18);
     else begin
      if(slot==0)filename[255-str_index*8-:8]<=q;
      if(slot==1)part_number[255-str_index*8-:8]<=q;
      if(str_index+1'b1==str_content && !nul_end && !pad_end)begin
       if(next_field==45)begin if(cursor+1'b1!=size)bad(15);else state<=RESULT;end
       else number(next_field,next_field==22?4:2);
      end else state<=STR_FETCH;
     end
    end else if(q!=0)bad(19);
    else if(next_field==45)begin if(cursor+1'b1!=size)bad(15);else state<=RESULT;end
    else number(next_field,next_field==43?1:next_field==22?4:2);
   end
   RESULT:if(result_ready)state<=IDLE;
   default:state<=IDLE;
  endcase
 end
endmodule
