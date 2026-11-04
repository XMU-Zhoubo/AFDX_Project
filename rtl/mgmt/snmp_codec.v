// C24 standalone codec boundary. No counters/UDP agent/SET executor is hidden here.
module snmp_codec (
 input wire clk,rst_n,dec_cancel,enc_cancel,
 input wire [7:0] s_data,input wire s_valid,s_last,output wire s_ready,
 output wire request_valid,input wire request_ready,output wire [3:0] request_error,
 output wire [9:0] request_length,output wire [7:0] request_pdu,output wire [3:0] request_count,
 input wire request_release,
 input wire q_valid,output wire q_ready,input wire [11:0] q_address,
 output wire q_result_valid,input wire q_result_ready,output wire [31:0] q_data,
 input wire w_valid,output wire w_ready,input wire [11:0] w_address,input wire [31:0] w_data,
 input wire encode_valid,output wire encode_ready,
 output wire [7:0] m_data,output wire m_valid,input wire m_ready,output wire m_last,
 output wire encode_result_valid,input wire encode_result_ready,output wire [3:0] encode_error,
 output wire [9:0] encode_length
);
 snmp_decoder decoder(.clk(clk),.rst_n(rst_n),.cancel(dec_cancel),.s_data(s_data),.s_valid(s_valid),.s_last(s_last),.s_ready(s_ready),
  .m_valid(request_valid),.m_ready(request_ready),.m_error(request_error),.m_length(request_length),.m_pdu(request_pdu),.m_count(request_count),
  .release_valid(request_release),.q_valid(q_valid),.q_ready(q_ready),.q_address(q_address),.q_result_valid(q_result_valid),.q_result_ready(q_result_ready),.q_data(q_data));
 snmp_encoder encoder(.clk(clk),.rst_n(rst_n),.cancel(enc_cancel),.w_valid(w_valid),.w_ready(w_ready),.w_address(w_address),.w_data(w_data),
  .start_valid(encode_valid),.start_ready(encode_ready),.m_data(m_data),.m_valid(m_valid),.m_ready(m_ready),.m_last(m_last),
  .result_valid(encode_result_valid),.result_ready(encode_result_ready),.result_error(encode_error),.result_length(encode_length));
endmodule
