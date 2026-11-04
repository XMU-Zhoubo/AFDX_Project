// Earliest COMPLETE protocol-valid candidate first, exact timestamp ties A.
// A one-entry request register prevents host-query backpressure or a newly
// arriving candidate from changing an already-valid core request.
module candidate_merge (
 input wire clk,rst_n,input wire [1:0] s_valid,output wire [1:0] s_ready,
 input wire [103:0] a_data,b_data,
 output wire m_valid,input wire m_ready,output reg [103:0] m_data,
 output reg network,input wire completed,output wire busy
);
 localparam IDLE=0,OFFER=1,WAIT=2;
 reg [1:0] state;
 wire choose=s_valid[1] && (!s_valid[0] || b_data[100:37]<a_data[100:37]);
 assign s_ready[0]=rst_n && state==IDLE && !choose;
 assign s_ready[1]=rst_n && state==IDLE && choose;
 assign m_valid=rst_n && state==OFFER;
 assign busy=rst_n && state!=IDLE;
 always @(posedge clk)begin
  if(!rst_n)begin state<=IDLE;m_data<=0;network<=0;end
  else case(state)
   IDLE:if(|s_valid)begin network<=choose;m_data<=choose?b_data:a_data;state<=OFFER;end
   OFFER:if(m_ready)state<=WAIT;
   WAIT:if(completed)state<=IDLE;
   default:state<=IDLE;
  endcase
 end
endmodule
