// Broadcast one logical byte with independent per-consumer acknowledgement.
// A consumer that has accepted it never sees valid for that byte again.
module tx_replicator (
 input wire clk,rst_n,input wire [1:0] select_net,input wire management,
 input wire [7:0] s_data,input wire s_valid,s_sop,s_last,s_error,output wire s_ready,
 output wire [7:0] a_data,b_data,output wire a_valid,b_valid,a_last,b_last,a_error,b_error,
 input wire a_ready,b_ready,
 output wire [1:0] active_mask,output wire idle
);
 reg active;reg [1:0] mask,accepted;reg [15:0] offset;reg is_management;
 wire [1:0] requested=select_net==1?2'b01:select_net==2?2'b10:2'b11;
 wire [1:0] current_mask=active?mask:requested;
 wire mgmt=active?is_management:management;
 wire [15:0] position=active?offset:0;
 assign active_mask=current_mask;
 assign a_valid=rst_n && s_valid && current_mask[0] && !accepted[0];
 assign b_valid=rst_n && s_valid && current_mask[1] && !accepted[1];
 assign s_ready=rst_n && (!current_mask[0] || accepted[0] || a_ready) &&
                      (!current_mask[1] || accepted[1] || b_ready);
 // AIM2010 p32: Interface ID is THREE bits followed by five reserved zeros.
 // C22 canonical configuration stores the A source; derive this octet per net.
 assign a_data=(!mgmt && position==11)?8'h20:s_data;
 assign b_data=(!mgmt && position==11)?8'h40:s_data;
 assign a_last=s_last;assign b_last=s_last;assign a_error=s_error;assign b_error=s_error;
 assign idle=rst_n && !active;
 always @(posedge clk)begin
  if(!rst_n)begin active<=0;mask<=0;accepted<=0;offset<=0;is_management<=0;end
  else begin
   if(s_valid && !active)begin active<=1;mask<=requested;is_management<=management;end
   if(a_valid && a_ready)accepted[0]<=1;
   if(b_valid && b_ready)accepted[1]<=1;
   if(s_valid && s_ready)begin
    accepted<=0;
    if(s_last)begin active<=0;offset<=0;end else offset<=position+1'b1;
   end
  end
 end
endmodule
