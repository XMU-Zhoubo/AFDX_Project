// Select one complete-frame producer. Network choice is frozen at command
// acceptance and held even AFTER commit while the existing queue waits/sends.
module time_management_mux (
 input wire clk,rst_n,
 input wire [1:0] h_network,input wire h_cmd_valid,input wire [15:0] h_length,output wire h_cmd_ready,
 input wire [7:0] h_data,input wire h_valid,h_last,h_commit,h_abort,output wire h_ready,h_commit_ready,
 output wire h_error_valid,input wire h_error_ready,output wire [2:0] h_error_code,
 input wire a_cmd_valid,input wire [15:0] a_length,input wire [1:0] a_network,output wire a_cmd_ready,
 input wire [7:0] a_data,input wire a_valid,a_last,a_commit,a_abort,output wire a_ready,a_commit_ready,
 output wire a_error_valid,input wire a_error_ready,
 output wire c_cmd_valid,output wire [15:0] c_length,input wire c_cmd_ready,
 output wire [7:0] c_data,output wire c_valid,c_last,c_commit,c_abort,input wire c_ready,c_commit_ready,
 input wire c_error_valid,output wire c_error_ready,input wire [2:0] c_error_code,
 output wire [1:0] c_network
);
 reg active,owner,rr,command_locked,command_owner;reg [1:0] saved_network;
 wire select_agent=command_locked?command_owner:(a_cmd_valid && (!h_cmd_valid || rr));
 assign c_network=c_cmd_valid?(select_agent?a_network:h_network):saved_network;
 assign c_cmd_valid=rst_n && !active && (select_agent?a_cmd_valid:h_cmd_valid);
 assign c_length=select_agent?a_length:h_length;
 assign h_cmd_ready=rst_n && !active && !select_agent && c_cmd_ready;
 assign a_cmd_ready=rst_n && !active && select_agent && c_cmd_ready;
 assign c_data=owner?a_data:h_data;assign c_valid=rst_n && active && (owner?a_valid:h_valid);
 assign c_last=owner?a_last:h_last;assign c_commit=rst_n && active && (owner?a_commit:h_commit);
 assign c_abort=rst_n && (owner?a_abort:h_abort);
 assign h_ready=rst_n && active && !owner && c_ready;assign a_ready=rst_n && active && owner && c_ready;
 assign h_commit_ready=rst_n && active && !owner && c_commit_ready;assign a_commit_ready=rst_n && active && owner && c_commit_ready;
 assign h_error_valid=rst_n && !owner && c_error_valid;assign a_error_valid=rst_n && owner && c_error_valid;
 assign h_error_code=c_error_code;assign c_error_ready=owner?a_error_ready:h_error_ready;
 always @(posedge clk)begin
  if(!rst_n)begin active<=0;owner<=0;rr<=0;saved_network<=0;command_locked<=0;command_owner<=0;end
  else begin
   if(!active && c_cmd_valid && !command_locked)begin command_locked<=1;command_owner<=select_agent;end
   if(c_cmd_valid && c_cmd_ready)begin active<=1;owner<=select_agent;rr<=!select_agent;saved_network<=select_agent?a_network:h_network;command_locked<=0;end
   if(active && ((c_commit && c_commit_ready) || c_abort || (c_error_valid && c_error_ready)))active<=0;
  end
 end
endmodule
