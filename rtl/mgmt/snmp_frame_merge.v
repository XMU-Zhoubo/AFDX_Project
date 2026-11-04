// Management-only frame arbiter. Ordinary UDP requests have no IC/RM copies.
module snmp_frame_merge (
 input wire clk,rst_n,
 input wire [7:0] a_data,b_data,input wire a_valid,b_valid,a_sop,b_sop,a_last,b_last,a_error,b_error,
 output wire a_ready,b_ready,
 output wire [7:0] m_data,output wire m_valid,m_sop,m_last,m_error,m_network,input wire m_ready
);
 reg active,owner,rr;
 wire select_b=active?owner:(b_valid && (!a_valid || rr));
 assign m_data=select_b?b_data:a_data;assign m_valid=rst_n && (select_b?b_valid:a_valid);
 assign m_sop=select_b?b_sop:a_sop;assign m_last=select_b?b_last:a_last;
 assign m_error=select_b?b_error:a_error;assign m_network=select_b;
 assign a_ready=rst_n && !select_b && m_ready;assign b_ready=rst_n && select_b && m_ready;
 always @(posedge clk)begin
  if(!rst_n)begin active<=0;owner<=0;rr<=0;end
  else begin
   if(!active && m_valid)begin active<=1;owner<=select_b;end
   if(m_valid && m_ready && m_last)begin active<=0;rr<=!select_b;end
  end
 end
endmodule
