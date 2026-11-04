// floor(ns * 2^32 / 1e9), one quotient bit per clock. No runtime divider.
module ntp_fraction (
 input wire clk,rst_n,input wire s_valid,output wire s_ready,input wire [31:0] s_nanoseconds,
 output wire m_valid,input wire m_ready,output wire [31:0] m_fraction
);
 reg busy,pending;reg [5:0] remaining;reg [31:0] remainder,quotient;
 wire [32:0] doubled={remainder,1'b0};
 wire bit_value=doubled>=33'd1000000000;
 assign s_ready=rst_n && !busy && (!pending || m_ready);
 assign m_valid=rst_n && pending;assign m_fraction=quotient;
 always @(posedge clk)begin
  if(!rst_n)begin busy<=0;pending<=0;remaining<=0;remainder<=0;quotient<=0;end
  else begin
   if(m_valid && m_ready)pending<=0;
   if(s_valid && s_ready)begin busy<=1;pending<=0;remaining<=32;remainder<=s_nanoseconds;quotient<=0;end
   else if(busy)begin
    remainder<=bit_value?doubled-33'd1000000000:doubled;
    quotient<={quotient[30:0],bit_value};remaining<=remaining-1'b1;
    if(remaining==1)begin busy<=0;pending<=1;end
   end
  end
 end
endmodule
