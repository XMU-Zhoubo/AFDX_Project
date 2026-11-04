// C21 single-network sequence state. Storage is the unchanged C20 bank primitive.
// A query never steals an event: events win IDLE arbitration and remain valid
// until ready. RX updates last observed *protocol-valid* SN even on IC rejection.
module sequence_core #(
 parameter ENTRY_COUNT=4096,
 parameter TX_MODE=0,
 parameter BANK_COUNT=(ENTRY_COUNT+2047)/2048
) (
 input wire clk,rst_n,
 output reg init_done,
 input wire s_valid, output wire s_ready,
 input wire [12:0] s_index, input wire [15:0] s_vl,
 input wire [7:0] s_sn, input wire s_invalidate,s_enable,
 output reg result_valid, input wire result_ready,
 output reg result_pass,result_error,
 output reg [3:0] result_reason,
 output reg [7:0] result_sn,
 // TX reserves once, advances only after complete MAC-client SN handshake.
 input wire commit_valid,cancel_valid,output wire finish_ready,
 input wire q_valid, output wire q_ready, input wire [12:0] q_index,
 output reg q_result_valid,input wire q_result_ready,
 output reg q_error,output reg [31:0] q_data,
 output reg [31:0] checked_count,accepted_count,rejected_count,
 output reg [31:0] zero_count,gap_count,cancel_count,
 output wire idle
);
 localparam ST_INIT=0,ST_IDLE=1,ST_READ=2,ST_RESULT=3,ST_RESERVED=4,ST_WRITE=5,ST_QREAD=6;
 reg [2:0] state;
 reg [12:0] clear_index,index;
 reg [15:0] vl;
 reg [7:0] sn;
 reg invalidate,enable_check,legal;
 reg [31:0] next_word;
 reg [31:0] q_word;
 reg q_bad;
 wire event_fire=s_valid && s_ready;
 wire query_fire=q_valid && q_ready;
 wire [12:0] address=state==ST_INIT?clear_index:(event_fire?s_index:query_fire?q_index:index);
 wire read_enable=event_fire || query_fire;
 wire write_enable=state==ST_INIT || state==ST_WRITE;
 wire [31:0] write_data=state==ST_INIT?32'd0:next_word;
 wire [BANK_COUNT*32-1:0] bank_words;
 reg [5:0] read_bank;
 wire [31:0] word=bank_words[read_bank*32+:32];
 genvar b;
 generate for(b=0;b<BANK_COUNT;b=b+1)begin:state_banks
  config_ram_bank storage(.clk(clk),.read_enable(read_enable && address[12:11]==b),
   .write_enable(write_enable && address[12:11]==b),.address(address[10:0]),
   .write_data(write_data),.read_data(bank_words[b*32+:32]));
 end endgenerate
 wire seen=word[8] && word[31:16]==vl;
 wire [7:0] previous=word[7:0];
 function [7:0] successor;
 input [7:0] value;
 begin successor=value==255?8'd1:value+1'b1;end
 endfunction
 wire one_step=sn==successor(previous);
 wire two_steps=sn==successor(successor(previous));
 assign s_ready=rst_n && init_done && state==ST_IDLE;
 assign q_ready=rst_n && init_done && state==ST_IDLE && !s_valid && !q_result_valid;
 assign finish_ready=rst_n && state==ST_RESERVED;
 assign idle=rst_n && init_done && state==ST_IDLE && !q_result_valid;
 always @(posedge clk)begin
  if(!rst_n)begin
   state<=ST_INIT;clear_index<=0;index<=0;vl<=0;sn<=0;invalidate<=0;enable_check<=1;legal<=0;
   init_done<=0;read_bank<=0;next_word<=0;q_word<=0;q_bad<=0;
   result_valid<=0;result_pass<=0;result_error<=0;result_reason<=0;result_sn<=0;
   q_result_valid<=0;q_error<=0;q_data<=0;
   checked_count<=0;accepted_count<=0;rejected_count<=0;zero_count<=0;gap_count<=0;cancel_count<=0;
  end else begin
   if(q_result_valid && q_result_ready)q_result_valid<=0;
   case(state)
    ST_INIT:if(clear_index==ENTRY_COUNT-1)begin init_done<=1;state<=ST_IDLE;end else clear_index<=clear_index+1'b1;
    ST_IDLE:begin
     if(event_fire)begin
      index<=s_index;vl<=s_vl;sn<=s_sn;invalidate<=s_invalidate;enable_check<=s_enable;
      legal<=s_index<ENTRY_COUNT && s_vl!=0;read_bank<=s_index[12:11];state<=ST_READ;
     end else if(query_fire)begin
      index<=q_index;read_bank<=q_index[12:11];q_bad<=q_index>=ENTRY_COUNT;state<=ST_QREAD;
     end
    end
    ST_QREAD:begin q_data<=q_bad?32'd0:word;q_error<=q_bad;q_result_valid<=1;state<=ST_IDLE;end
    ST_READ:begin
     result_valid<=1;result_error<=!legal;result_pass<=legal;result_sn<=sn;
     next_word<={vl,7'd0,1'b1,sn};
     if(!legal)begin result_reason<=15;next_word<=0;end
     else if(invalidate)begin result_reason<=6;next_word<=0;end
     else if(TX_MODE)begin
      result_sn<=seen?previous:8'd0;result_reason<=seen?0:1;
      next_word<={vl,7'd0,1'b1,successor(seen?previous:8'd0)};
     end else if(!enable_check)result_reason<=7;
     else if(!seen)result_reason<=1;
     else if(sn==0)result_reason<=2;
     else if(one_step)result_reason<=0;
     else if(two_steps)result_reason<=3;
     else begin result_pass<=0;result_reason<=sn==previous?4:5;end
     state<=ST_RESULT;
    end
    ST_RESULT:if(result_valid && result_ready)begin
     result_valid<=0;
     if(!result_error && !invalidate)begin
      checked_count<=checked_count+1'b1;
      if(result_pass)accepted_count<=accepted_count+1'b1;else rejected_count<=rejected_count+1'b1;
      if(!TX_MODE && result_pass && result_sn==0)zero_count<=zero_count+1'b1;
      if(!TX_MODE && result_reason==3)gap_count<=gap_count+1'b1;
     end
     if(result_error)state<=ST_IDLE;
     else if(TX_MODE && !invalidate)state<=ST_RESERVED;
     else state<=ST_WRITE;
    end
    ST_RESERVED:begin
     if(commit_valid)state<=ST_WRITE;
     else if(cancel_valid)begin cancel_count<=cancel_count+1'b1;state<=ST_IDLE;end
    end
    ST_WRITE:state<=ST_IDLE;
    default:state<=ST_INIT;
   endcase
  end
 end
endmodule
