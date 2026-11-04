`timescale 1ns/1ps
// External byte device only. V2 original objects0..4; V3 high-bit operations
// for download objects5..10. No TFTP/615A interpretation or control decisions.
module storage_download_model(
 input wire clk,rst_n,cancel,input wire [7:0] s_data,input wire s_valid,s_last,output wire s_ready,
 output wire [7:0] m_data,output wire m_valid,m_last,input wire m_ready,
 input wire stall,hold_completion,fail_write,inject_stale,
 output reg [31:0] opens,writes,reads,cancelled,failed,
 output wire object_valid,object_complete,output wire [15:0] object_length,
 output reg event_valid,output reg [2:0] event_kind,output reg [15:0] event_length
);
 reg [3:0] bank;reg [10:0] valid_bank,complete_bank,writing_bank,locked_bank;reg [16:0] length_bank[0:10];
 reg [7:0] bytes[0:73764],staging[0:511];reg [103:0] header;reg [31:0] tag,old_tag;
 reg old_valid,wide;reg [2:0] response_pos;reg [3:0] state,pos;
 reg [16:0] offset;reg [15:0] length,index;reg [7:0] op,status,wait_count;reg final_block,writing;
 reg readable=1,writable=1;reg [31:0] read_bytes=0,write_bytes=0,metadata=0,locks=0,unlocks=0,data_read_bytes=0,data_read_requests=0;
 assign object_valid=valid_bank[0];assign object_complete=complete_bank[0];assign object_length=length_bank[0][15:0];
 wire [103:0] assembled={header[95:0],s_data};
 wire [7:0] parsed_bank=wide?assembled[95:88]:assembled[79:72];
 wire [7:0] parsed_op=wide?(assembled[103:96]&8'h7f):assembled[87:80];
 wire [31:0] parsed_offset=wide?assembled[87:56]:{16'd0,assembled[71:56]};
 wire [32:0] command_end={1'b0,parsed_offset}+{17'd0,assembled[55:40]};
 function integer base;input [3:0] b;begin base=b==0?0:b<=4?4096+(b-1)*512:b==5?6144:b==6?6181:71717+(b-7)*512;end endfunction
 function integer capacity;input [7:0] b;begin capacity=b==0?4096:b==5?37:b==6?65536:512;end endfunction
 wire [7:0] flags={4'd0,locked_bank[bank],writable && !(bank==5 || bank==6),readable,valid_bank[bank]};
 wire [31:0] meta_size={15'd0,length_bank[bank]};
 wire [7:0] meta_byte=index==0?flags:wide?meta_size[31-(index-1)*8-:8]:index==1?length_bank[bank][15:8]:length_bank[bank][7:0];
 assign s_ready=rst_n && !stall && (state==0 || state==1);
 assign m_valid=rst_n && (state==3 || state==4 || state==5 || state==6 || state==7);
 assign m_data=state==6?tag[31-response_pos*8-:8]:state==7?(response_pos==4?8'd0:old_tag[31-response_pos*8-:8]):state==3?status:state==5?meta_byte:bytes[base(bank)+offset+index];
 assign m_last=state==6?1'b0:state==7?response_pos==4:state==3?(status!=0 || (op!=3 && op!=4)):state==5?index==(wide?4:2):index+1'b1==length;
 task preload;input integer n,seed;integer j;begin
  for(j=0;j<n;j=j+1)bytes[j]=(j*73+(j>>8)*91+seed)&255;
  length_bank[0]=n;valid_bank[0]=1;complete_bank[0]=1;writing=0;writing_bank=0;readable=1;writable=1;
 end endtask
 task preload_catalog;integer j;begin
  if(locked_bank[5] || locked_bank[6])begin $display("STORAGE_PRELOAD_WHILE_LEASED");$stop;end
  for(j=0;j<37;j=j+1)bytes[6144+j]=(j*73+(j>>8)*91+(j>>15)*37+53)&255;
  for(j=0;j<65536;j=j+1)bytes[6181+j]=(j*73+(j>>8)*91+(j>>15)*37+197)&255;
  length_bank[5]=37;length_bank[6]=65536;valid_bank[5]=1;valid_bank[6]=1;complete_bank[5]=1;complete_bank[6]=1;
 end endtask
 integer k;
 always @(posedge clk)begin
  if(!rst_n)begin
   bank<=0;state<=0;pos<=0;header<=0;tag<=0;old_tag<=0;old_valid<=0;response_pos<=0;offset<=0;length<=0;index<=0;op<=0;status<=0;final_block<=0;wait_count<=0;writing<=0;wide<=0;
   opens<=0;writes<=0;reads<=0;cancelled<=0;failed<=0;valid_bank<=0;complete_bank<=0;writing_bank<=0;locked_bank<=0;
   for(k=0;k<11;k=k+1)length_bank[k]<=0;
   event_valid<=0;event_kind<=0;event_length<=0;read_bytes<=0;write_bytes<=0;metadata<=0;readable<=1;writable<=1;locks<=0;unlocks<=0;data_read_bytes<=0;data_read_requests<=0;
  end else begin
   event_valid<=0;
   case(state)
    0:if(s_valid && s_ready)begin
     header<=assembled;if(pos==0)wide<=s_data[7];
     if(pos==(wide?12:10))begin
      bank<=parsed_bank[3:0];pos<=0;tag<=assembled[31:0];op<=parsed_op;offset<=parsed_offset[16:0];length<=assembled[55:40];final_block<=assembled[32];index<=0;wait_count<=0;
      status<=0;event_valid<=1;event_kind<=1;event_length<=assembled[55:40];state<=2;
      if(parsed_bank>10 || command_end>capacity(parsed_bank) || parsed_op<1 || parsed_op>7 ||
       (!wide && parsed_bank>=5) || (wide && parsed_bank<5) || parsed_offset>65536 ||
       s_last!=!(parsed_op==2 && assembled[55:40]!=0))status<=1;
      else if(parsed_bank==5 || parsed_bank==6)begin
       if(parsed_op==6)begin
        if(locked_bank[parsed_bank] || !valid_bank[parsed_bank] || !complete_bank[parsed_bank])status<=1;
        else begin locked_bank[parsed_bank]<=1;locks<=locks+1'b1;end
       end else if(parsed_op==7)begin
        if(locked_bank[parsed_bank])unlocks<=unlocks+1'b1;locked_bank[parsed_bank]<=0;
       end else if(parsed_op==3)begin
        if(!locked_bank[parsed_bank] || !readable || assembled[55:40]==0 || command_end>length_bank[parsed_bank])status<=1;
        reads<=reads+1'b1;data_read_requests<=data_read_requests+1'b1;
       end else if(parsed_op==4)metadata<=metadata+1'b1;
       else status<=1;
      end else if(parsed_op==1)begin
       if(!writable)status<=1;else begin valid_bank[parsed_bank]<=0;complete_bank[parsed_bank]<=0;length_bank[parsed_bank]<=0;writing<=1;writing_bank[parsed_bank]<=1;opens<=opens+1'b1;end
      end else if(parsed_op==2)begin
       if(!writing_bank[parsed_bank] || !writable || parsed_offset!=length_bank[parsed_bank] || assembled[55:40]>512)status<=1;
       else if(assembled[55:40]!=0)state<=1;
      end else if(parsed_op==3)begin
       if(!valid_bank[parsed_bank] || !complete_bank[parsed_bank] || !readable || assembled[55:40]==0 || command_end>length_bank[parsed_bank])status<=1;
       reads<=reads+1'b1;
      end else if(parsed_op==5)begin valid_bank[parsed_bank]<=0;complete_bank[parsed_bank]<=0;length_bank[parsed_bank]<=0;writing_bank[parsed_bank]<=0;end
      else if(parsed_op==4)metadata<=metadata+1'b1;else status<=1;
      if(inject_stale && old_valid)begin state<=7;response_pos<=0;end
     end else pos<=pos+1'b1;
    end
    1:if(s_valid && s_ready)begin staging[index[8:0]]<=s_data;if(s_last!=(index+1'b1==length))status<=1;
     if(s_last || index+1'b1==length)begin state<=2;wait_count<=0;event_valid<=1;event_kind<=2;event_length<=length;end else index<=index+1'b1;
    end
    2:if(!hold_completion)begin if(wait_count==19)begin if(op==2 && fail_write)status<=1;response_pos<=0;state<=6;end else wait_count<=wait_count+1'b1;end
    3:if(m_valid && m_ready)begin
     event_valid<=1;event_length<=length;
     if(status!=0)begin failed<=failed+1'b1;event_kind<=4;state<=0;if(op==2)begin valid_bank[bank]<=0;complete_bank[bank]<=0;writing<=0;writing_bank[bank]<=0;end end
     else if(op==2)begin
      for(k=0;k<512;k=k+1)if(k<length)bytes[base(bank)+offset+k]<=staging[k];
      valid_bank[bank]<=final_block;complete_bank[bank]<=final_block;length_bank[bank]<=offset+length;writing<=!final_block;writing_bank[bank]<=!final_block;
      writes<=writes+1'b1;write_bytes<=write_bytes+length;event_kind<=3;state<=0;
     end else if(op==3)begin index<=0;state<=4;event_kind<=5;end
     else if(op==4)begin index<=0;state<=5;event_kind<=7;end
     else begin state<=0;event_kind<=6;end
    end
    4:if(m_valid && m_ready)begin read_bytes<=read_bytes+1'b1;if(bank==5 || bank==6)data_read_bytes<=data_read_bytes+1'b1;if(m_last)state<=0;else index<=index+1'b1;end
    5:if(m_valid && m_ready)begin if(m_last)state<=0;else index<=index+1'b1;end
    6:if(m_valid && m_ready)begin if(response_pos==3)state<=3;else response_pos<=response_pos+1'b1;end
    7:if(m_valid && m_ready)begin if(response_pos==4)begin old_valid<=0;response_pos<=0;state<=2;event_valid<=1;event_kind<=0;end else response_pos<=response_pos+1'b1;end
    default:state<=0;
   endcase
   if(cancel)begin
    if(state!=0 && pos==0)begin old_tag<=tag;old_valid<=1;end
    if(state!=0 || pos!=0 || writing)cancelled<=cancelled+1'b1;
    if(writing_bank[bank])begin valid_bank[bank]<=0;complete_bank[bank]<=0;writing<=0;writing_bank[bank]<=0;end
    state<=0;pos<=0;
   end
  end
 end
endmodule
