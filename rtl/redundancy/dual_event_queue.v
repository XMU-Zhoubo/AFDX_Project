// Two one-cycle result events can coincide; consume each exactly once at a
// single legacy RMW port. Four entries cover the two-frame burst; depth8 leaves
// margin. Overflow is a visible error, never silent event loss.
module dual_event_queue (
 input wire clk,rst_n,input wire a_valid,b_valid,input wire [47:0] a_data,b_data,
 output wire m_valid,input wire m_ready,output wire [47:0] m_data,output reg overflow
);
 reg [47:0] slots[0:7];reg [2:0] wr,rd;reg [3:0] count;
 wire pop=m_valid && m_ready;wire [1:0] pushes={1'b0,a_valid}+{1'b0,b_valid};
 wire [4:0] next_count={1'b0,count}+pushes-pop;
 assign m_valid=rst_n && count!=0;assign m_data=slots[rd];
 always @(posedge clk)begin
  if(!rst_n)begin wr<=0;rd<=0;count<=0;overflow<=0;end
  else begin
   overflow<=0;
   if(next_count>8)overflow<=1;
   else begin
    if(a_valid)slots[wr]<=a_data;
    if(b_valid)slots[(wr+{2'd0,a_valid})&3'b111]<=b_data;
    wr<=wr+pushes;count<=next_count[3:0];
   end
   if(pop)rd<=rd+1'b1;
  end
 end
endmodule
