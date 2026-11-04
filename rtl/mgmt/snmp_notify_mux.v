// C26 transaction lease. Host diagnostics remain readable during the lease.
// No agent SET ever writes the host's shadow VL table or budget registers.
module snmp_notify_mux(
 input wire clk,rst_n,
 input wire h_valid,h_write,input wire [1:0] h_kind,input wire h_bank,h_shadow,input wire [12:0] h_index,input wire [3:0] h_word,input wire [31:0] h_data,output wire h_ready,
 output wire h_result_valid,input wire h_result_ready,output wire h_result_error,output wire [31:0] h_result_data,
 input wire h_commit_valid,output wire h_commit_ready,output wire h_commit_result_valid,input wire h_commit_result_ready,output wire h_commit_result_ok,output wire [2:0] h_commit_result_code,
 input wire lock_valid,lock_write,output wire lock_ready,lock_error,input wire lock_release,
 input wire a_valid,a_write,input wire [1:0] a_kind,input wire a_bank,input wire [12:0] a_index,input wire [3:0] a_word,output wire a_ready,
 output wire a_result_valid,input wire a_result_ready,output wire a_result_error,output wire [31:0] a_result_data,
 input wire a_commit_valid,output wire a_commit_ready,output wire a_commit_result_valid,input wire a_commit_result_ready,output wire a_commit_result_ok,output wire [2:0] a_commit_result_code,
 output wire c_valid,c_write,output wire [1:0] c_kind,output wire c_bank,c_shadow,output wire [12:0] c_index,output wire [3:0] c_word,output wire [31:0] c_data,input wire c_ready,
 input wire c_result_valid,output wire c_result_ready,input wire c_result_error,input wire [31:0] c_result_data,
 output wire c_commit_valid,c_budget_only,input wire c_commit_ready,c_pending,c_applied,c_commit_result_valid,c_commit_result_ok,input wire [2:0] c_commit_result_code,output wire c_commit_result_ready,
 input wire [511:0] diagnostics,trap_diagnostics
);
 reg leased,bus_active,bus_owner,commit_active,commit_owner,applied_seen,host_dirty;
 reg local_valid,local_error;reg [31:0] local_data;
 wire diagnostic=h_kind==3 && (h_index==1 || h_index==2);
 wire host_bus_busy=bus_active && !bus_owner;
 assign lock_ready=rst_n && !leased && !bus_active && !commit_active && !c_pending && !c_commit_result_valid;
 assign lock_error=lock_write && host_dirty;
 assign c_valid=rst_n && !bus_active && !commit_active && (leased?a_valid:(!lock_valid && h_valid && !diagnostic));
 assign c_write=leased?a_write:h_write;assign c_kind=leased?a_kind:h_kind;assign c_bank=leased?a_bank:h_bank;
 assign c_shadow=leased?1'b0:h_shadow;assign c_index=leased?a_index:h_index;assign c_word=leased?a_word:h_word;assign c_data=leased?32'd0:h_data;
 assign h_ready=rst_n && (diagnostic?(!local_valid && !host_bus_busy):(!leased && !lock_valid && !bus_active && !commit_active && c_ready));
 assign a_ready=rst_n && leased && !bus_active && !commit_active && c_ready;
 assign h_result_valid=rst_n && (local_valid || (bus_active && !bus_owner && c_result_valid));
 assign h_result_data=local_valid?local_data:c_result_data;assign h_result_error=local_valid?local_error:c_result_error;
 assign a_result_valid=rst_n && bus_active && bus_owner && c_result_valid;assign a_result_data=c_result_data;assign a_result_error=c_result_error;
 assign c_result_ready=rst_n && bus_active && (bus_owner?a_result_ready:(h_result_ready && !local_valid));
 assign c_commit_valid=rst_n && !commit_active && !bus_active && (leased?a_commit_valid:(!lock_valid && h_commit_valid));
 assign c_budget_only=rst_n && leased && a_commit_valid && !commit_active && !bus_active;
 assign h_commit_ready=rst_n && !leased && !lock_valid && !commit_active && !bus_active && c_commit_ready;
 assign a_commit_ready=rst_n && leased && !commit_active && !bus_active && c_commit_ready;
 assign h_commit_result_valid=rst_n && commit_active && !commit_owner && c_commit_result_valid;
 assign a_commit_result_valid=rst_n && commit_active && commit_owner && c_commit_result_valid;
 assign h_commit_result_ok=c_commit_result_ok;assign h_commit_result_code=c_commit_result_code;
 assign a_commit_result_ok=c_commit_result_ok && (applied_seen || c_applied);assign a_commit_result_code=c_commit_result_code;
 assign c_commit_result_ready=rst_n && commit_active && (commit_owner?a_commit_result_ready:h_commit_result_ready);
 always @(posedge clk)begin
  if(!rst_n)begin leased<=0;bus_active<=0;bus_owner<=0;commit_active<=0;commit_owner<=0;applied_seen<=0;host_dirty<=0;local_valid<=0;local_error<=0;local_data<=0;end
  else begin
   if(lock_valid && lock_ready && !lock_error)leased<=1;
   if(lock_release)leased<=0;
   if(h_valid && h_ready && diagnostic)begin local_valid<=1;local_error<=h_write;local_data<=h_write?32'd0:(h_index==2?trap_diagnostics[h_word*32+:32]:diagnostics[h_word*32+:32]);end
   if(local_valid && h_result_ready)local_valid<=0;
   if(c_valid && c_ready)begin
    bus_active<=1;bus_owner<=leased;
    if(!leased && h_write && (h_kind==0 || (h_kind==3 && h_word<4)))host_dirty<=1;
   end
   if(c_result_valid && c_result_ready)bus_active<=0;
   if(c_commit_valid && c_commit_ready)begin commit_active<=1;commit_owner<=leased;applied_seen<=0;end
   if(commit_active && c_applied)applied_seen<=1;
   if(c_commit_result_valid && c_commit_result_ready)begin
    commit_active<=0;if(!commit_owner && c_commit_result_ok)host_dirty<=0;
   end
  end
 end
endmodule
