// C42-S: one complete message buffer. IP data slices, never private wire headers.
module message_tx(
 input wire clk,rst_n,abort,
 input wire seed_valid,input wire [15:0] seed,output wire seed_ready,
 input wire start_valid,output wire start_ready,input wire [15:0] length,
 input wire [95:0] endpoints,
 input wire [7:0] s_data,input wire s_valid,s_last,output wire s_ready,
 input wire commit_valid,output wire commit_ready,
 output wire fragment_valid,input wire fragment_ready,
 output wire [15:0] fragment_length,fragment_id,fragment_flags,
 output wire [7:0] m_data,output wire m_valid,m_last,input wire m_ready,
 input wire fragment_committed,
 output wire idle,output reg error_event,output reg [31:0] accepted_count,completed_count,cancel_count
);
 localparam IDLE=0,FILL=1,CHECK=2,READ=3,ACCUM=4,FOLD=5,OFFER=6,STREAM=7,WAIT=8;
 reg [3:0] state;
 reg [12:0] count,pos,offset,total,part;
 reg [95:0] ep;
 reg [15:0] next_id,id,check_value;
 reg exhausted,initialized;reg [32:0] reuse_age;
 reg [31:0] sum;
 wire [7:0] q;reg [7:0] high;
 reg pending;
 wire [15:0] udp_len={3'd0,total};
 wire [12:0] remain=total-offset;
 wire [12:0] absolute=offset+pos;
 wire input_fire=s_valid && s_ready;
 wire read_enable=state==READ || (state==STREAM && !pending && absolute>=8);
 wire [11:0] transmit_address=absolute-13'd8;
 wire [11:0] read_address=state==READ ? pos[11:0]:transmit_address;
 payload_buffer #(.CAPACITY(4096),.ADDR_WIDTH(12)) storage(
  .clk(clk),.write_enable(input_fire),.write_addr(count[11:0]),.write_data(s_data),
  .read_enable(read_enable),.read_addr(read_address),.read_data(q));
 wire [31:0] folded={16'd0,sum[15:0]}+{16'd0,sum[31:16]};
 assign seed_ready=rst_n && state==IDLE && !initialized;
 assign start_ready=rst_n && state==IDLE && !exhausted && initialized;
 assign s_ready=rst_n && state==FILL && count<total-8 && !abort;
 assign commit_ready=rst_n && state==FILL && count==total-8 && !abort;
 assign idle=state==IDLE;
 assign fragment_valid=rst_n && state==OFFER;
 assign fragment_length={3'd0,part};
 assign fragment_id=id;
 assign fragment_flags={2'b00,(offset+part<total),3'b000,offset[12:3]};
 assign m_valid=rst_n && state==STREAM && pending;
 assign m_last=pos==part-1;
 reg [7:0] output_byte;
 assign m_data=output_byte;
 always @* begin
  if(absolute>=8)output_byte=q;
  else case(absolute)
   0:output_byte=ep[31:24];1:output_byte=ep[23:16];2:output_byte=ep[15:8];3:output_byte=ep[7:0];
   4:output_byte=udp_len[15:8];5:output_byte=udp_len[7:0];6:output_byte=check_value[15:8];7:output_byte=check_value[7:0];
   default:output_byte=0;
  endcase
 end
 always @(posedge clk)begin
  if(!rst_n)begin state<=IDLE;count<=0;pos<=0;offset<=0;total<=0;part<=0;ep<=0;next_id<=0;id<=0;
   exhausted<=0;initialized<=0;reuse_age<=0;sum<=0;high<=0;check_value<=0;pending<=0;error_event<=0;accepted_count<=0;completed_count<=0;cancel_count<=0;end
  else begin
   error_event<=0;
   if(seed_valid && seed_ready && seed!=0)begin next_id<=seed;initialized<=1;end
   if(exhausted)begin
    if(reuse_age==33'd6000000000)begin exhausted<=0;reuse_age<=0;end else reuse_age<=reuse_age+1'b1;
   end
   // Explicit commit transfers ownership. Later app aborts cannot revoke it.
   if(abort && state==FILL)begin
    state<=IDLE;cancel_count<=cancel_count+1;pending<=0;
   end else case(state)
    IDLE:if(start_valid && start_ready)begin
     total<=length+8;ep<=endpoints;count<=0;state<=FILL;id<=next_id;
     next_id<=next_id+1'b1;if(next_id==65535)begin exhausted<=1;reuse_age<=0;end
    end
    FILL:begin
     if(input_fire)begin
      count<=count+1;
      if(s_last!=(count==total-9))begin state<=IDLE;error_event<=1;cancel_count<=cancel_count+1;end
     end
     if(commit_valid && commit_ready)begin accepted_count<=accepted_count+1;state<=CHECK;end
    end
    CHECK:begin
     sum<= {16'd0,ep[95:80]}+{16'd0,ep[79:64]}+{16'd0,ep[63:48]}+{16'd0,ep[47:32]}+
       {16'd0,ep[31:16]}+{16'd0,ep[15:0]}+{16'd0,udp_len}+{16'd0,udp_len}+32'd17;
     pos<=0;state<=READ;
    end
    READ:state<=ACCUM;
    ACCUM:begin
     if(!pos[0])high<=q;
     if(pos[0])sum<=sum+{16'd0,high,q};
     else if(pos==total-9)sum<=sum+{16'd0,q,8'd0};
     if(pos==total-9)state<=FOLD;else begin pos<=pos+1;state<=READ;end
    end
    FOLD:if(sum[31:16]!=0)sum<=folded;else begin
     check_value<=sum[15:0]==16'hffff ? 16'hffff:~sum[15:0];
     offset<=0;pos<=0;part<=total>1472 ? 1472:total;state<=OFFER;
    end
    OFFER:if(fragment_ready)begin pos<=0;pending<=0;state<=STREAM;end
    STREAM:begin
     if(!pending)pending<=1;
     if(m_valid && m_ready)begin
      pending<=0;
      if(m_last)state<=WAIT;else pos<=pos+1;
     end
    end
    WAIT:if(fragment_committed)begin
     if(offset+part==total)begin completed_count<=completed_count+1;state<=IDLE;end
     else begin offset<=offset+part;part<=total-offset-part>1472 ? 1472:total-offset-part;state<=OFFER;end
    end
    default:state<=IDLE;
   endcase
  end
 end
endmodule
