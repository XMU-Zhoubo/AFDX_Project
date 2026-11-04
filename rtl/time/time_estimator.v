// RFC5905 section8 signed first differences, then widened second differences.
// Result unit is 2^-32 seconds. /2 rounds toward minus infinity, explicitly.
module time_estimator (
 input wire clk,rst_n,input wire s_valid,output wire s_ready,
 input wire [63:0] t1,t2,t3,t4,
 output wire m_valid,input wire m_ready,output reg signed [64:0] theta,delta,
 output reg [2:0] error
);
 reg [1:0] state;reg signed [63:0] d21,d34,d41,d32;
 reg signed [64:0] sum,difference;
 localparam signed [64:0] MAX_OFFSET=65'sd371085174374400; // 86400 seconds
 localparam signed [64:0] MAX_DELAY=65'sd42949673; // ceil(.010 * 2^32)
 wire signed [64:0] x21={d21[63],d21},x34={d34[63],d34};
 wire signed [64:0] x41={d41[63],d41},x32={d32[63],d32};
 assign s_ready=rst_n && state==0;
 assign m_valid=rst_n && state==3;
 always @(posedge clk)begin
  if(!rst_n)begin state<=0;theta<=0;delta<=0;error<=0;d21<=0;d34<=0;d41<=0;d32<=0;sum<=0;difference<=0;end
  else case(state)
   0:if(s_valid)begin d21<=t2-t1;d34<=t3-t4;d41<=t4-t1;d32<=t3-t2;state<=1;end
   1:begin sum<=x21+x34;difference<=x41-x32;error<=0;
    if(x21>MAX_OFFSET || x21< -MAX_OFFSET || x34>MAX_OFFSET || x34< -MAX_OFFSET)error<=1;
    else if(d41<0 || d32<0)error<=2;
    state<=2;
   end
   2:begin theta<=sum >>> 1;delta<=difference;
    if(error==0)begin if(difference<0)error<=3;else if(difference>MAX_DELAY)error<=4;end
    state<=3;
   end
   3:if(m_ready)state<=0;
   default:state<=0;
  endcase
 end
endmodule
