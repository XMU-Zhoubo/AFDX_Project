// One shared MAC owner, eight real committed slot candidates. All accesses
// are bounded; no combinational full-table admission or hardware /5 path.
module capacity_scheduler (
 input wire clk,rst_n,input wire dispatch_enable,config_applied,
 input wire [2:0] active_max_bag_exp,management_period,
 output wire [2:0] cand_slot,input wire cand_valid,
 input wire [255:0] cand_config,input wire [12:0] cand_index,
 input wire [31:0] candidate_epoch,
 input wire [15:0] cand_length,output wire rt_permit,
 output wire grant_valid,output wire [2:0] grant_slot,input wire grant_ready,
 input wire management_candidate,input wire [15:0] management_length,
 output wire management_launch,output reg management_release,
 input wire management_submitted,rt_submitted,rt_busy,
 input wire line_start,line_finish,
 output reg owner_busy,output reg owner_management,
 output reg rt_start,output reg rt_finish,output reg mgmt_grant,
 output reg [12:0] owner_index,output reg [2:0] owner_exp,
 output wire [31:0] now,output wire init_done,
 output wire [31:0] management_service,output reg [31:0] available_window,
 output reg ownership_error
);
 localparam SCAN=0,QUERY=1,DECIDE=2,OFFER=3;
 reg [1:0] state;
 // A full due-only RR sweep has priority. If none is due, prepare one frame
 // within its first payload-read pass; the independent deadline gate below
 // still prevents every MAC-client byte until BAG is actually satisfied.
 reg early_valid;reg [2:0] early_slot,early_exp;
 reg [12:0] early_index;reg [31:0] early_remaining,early_tick;
 reg [31:0] queried_lead,permit_remaining;
 wire [31:0] early_elapsed=now-early_tick;
 assign rt_permit=permit_remaining==0;
 reg [2:0] slot,rr;
 reg [3:0] visited;
 reg [31:0] scan_epoch,scan_time,min_window;
 reg [12:0] queried_index;
 reg [2:0] queried_exp;
 reg [2:0] queried_slot;
 reg seen_start,seen_done,finish_pending,start_pending;
 reg [5:0] cooldown;
 reg [31:0] global_age;
 reg global_seen,global_floor;
 reg [2:0] historic_max,floor_exp;
 wire [31:0] floor_cycles=32'd100000 << floor_exp;
 wire floor_due=!global_floor || global_age>=floor_cycles;
 wire bag_q_ready,bag_result_valid,bag_eligible,bag_start_ready;
 wire [31:0] bag_remaining;
 // C38: the epoch-refresh branch below does not enter QUERY. Do not let the
 // BAG RAM accept a request on that branch and leave its response orphaned.
 wire q_fire=rst_n && state==SCAN && cand_valid && !owner_busy && dispatch_enable && cooldown==0 &&
     !(visited==0 && scan_epoch!=candidate_epoch);
 wire result_due=bag_eligible && floor_due;
 wire [31:0] floor_remaining=floor_due?0:floor_cycles-global_age;
 wire [31:0] entry_remaining=bag_remaining>floor_remaining?bag_remaining:floor_remaining;
 wire [31:0] elapsed=now-scan_time;
 wire [31:0] current_window=min_window==32'hffffffff ? 32'hffffffff :
       (elapsed>=min_window?0:min_window-elapsed);
 timebase timer(.clk(clk),.rst_n(rst_n),.now(now));
 capacity_bag history(.clk(clk),.rst_n(rst_n),.now(now),.init_done(init_done),
  .start_valid(start_pending && !owner_management),.start_index(owner_index[6:0]),.start_exp(owner_exp),.start_ready(bag_start_ready),
  .q_valid(q_fire),.q_ready(bag_q_ready),.q_index(cand_index[6:0]),.q_exp(cand_config[243:241]),
  .result_valid(bag_result_valid),.result_ready(state==QUERY),.eligible(bag_eligible),.remaining(bag_remaining));
 wire [31:0] mgmt_age,mgmt_required;
 wire mgmt_due;
 bag mgmt_history(.clk(clk),.rst_n(rst_n),.now(now),.configured_exponent(management_period),
 .start_confirmed(line_start && owner_busy && owner_management),.transmitted_exponent(owner_exp),
 .rebase(1'b0),.rebase_seen(1'b0),.rebase_age(32'd0),.rebase_exponent(3'd0),
 .eligible(mgmt_due),.configured_cycles(),.required_cycles(mgmt_required),.age(mgmt_age),.seen());
 // Sixteen-clock, constant-5 long division, run once per candidate length.
 reg [15:0] cached_length,div_shift,div_quot,wire_cycles;
 reg [2:0] div_rem;
 reg [4:0] div_count;
 reg div_busy,service_valid;
 wire [15:0] wire_length=management_length<60?16'd64:management_length+16'd4;
 wire [3:0] rem_step={div_rem,div_shift[15]};
 wire [15:0] next_quot={div_quot[14:0],rem_step>=5};
 assign management_service=({16'd0,cached_length}<<1)+{16'd0,wire_cycles}+32'd640;
 assign cand_slot=slot;
 assign grant_slot=queried_slot;
 // Once offered, the selected slot/context is held until acceptance. New
 // candidate arrivals cannot revoke an already-valid downstream transfer.
 assign grant_valid=rst_n && state==OFFER && !owner_busy;
 assign management_launch=owner_busy && owner_management;
 always @(posedge clk)begin
  if(!rst_n)begin
   cached_length<=0;div_shift<=0;div_quot<=0;wire_cycles<=0;div_rem<=0;div_count<=0;div_busy<=0;service_valid<=0;
  end else begin
   if(!management_candidate)service_valid<=0;
   if(management_candidate && !div_busy && (!service_valid || cached_length!=management_length))begin
    cached_length<=management_length;div_shift<=(wire_length+16'd20)*16'd4+16'd4;
    div_quot<=0;div_rem<=0;div_count<=0;div_busy<=1;service_valid<=0;
   end else if(div_busy)begin
    div_shift<={div_shift[14:0],1'b0};div_quot<=next_quot;
    div_rem<=rem_step>=5?rem_step-5:rem_step;
    if(div_count==15)begin wire_cycles<=next_quot;div_busy<=0;service_valid<=1;end
    else div_count<=div_count+1'b1;
   end
  end
 end
 always @(posedge clk)begin
  if(!rst_n)begin
   early_valid<=0;early_slot<=0;early_exp<=0;early_index<=0;early_remaining<=0;early_tick<=0;queried_lead<=0;permit_remaining<=0;
   state<=SCAN;slot<=0;rr<=0;visited<=0;scan_epoch<=0;scan_time<=0;min_window<=32'hffffffff;
   queried_index<=0;queried_exp<=0;queried_slot<=0;owner_busy<=0;owner_management<=0;owner_index<=0;owner_exp<=0;
   seen_start<=0;seen_done<=0;finish_pending<=0;start_pending<=0;cooldown<=0;rt_start<=0;rt_finish<=0;mgmt_grant<=0;management_release<=0;
   global_age<=0;global_seen<=0;global_floor<=0;historic_max<=0;floor_exp<=0;available_window<=0;ownership_error<=0;
  end else begin
   rt_start<=0;rt_finish<=0;mgmt_grant<=0;management_release<=0;ownership_error<=0;
   if(permit_remaining!=0)permit_remaining<=permit_remaining-1;
   if(cooldown!=0)cooldown<=cooldown-1'b1;
   if(global_age<12800000)global_age<=global_age+1'b1;
   if(global_floor && global_age>=floor_cycles)global_floor<=0;
   if(config_applied)begin
    floor_exp<=historic_max>active_max_bag_exp?historic_max:active_max_bag_exp;
    global_floor<=global_seen;
    if(active_max_bag_exp>historic_max)historic_max<=active_max_bag_exp;
   end
   if(start_pending && (owner_management || bag_start_ready))start_pending<=0;
   if(line_start)begin
    if(!owner_busy || seen_start)ownership_error<=1;
    else begin
     seen_start<=1;
     if(!owner_management)begin
      rt_start<=1;start_pending<=1;global_age<=0;global_seen<=1;
      if(owner_exp>historic_max)historic_max<=owner_exp;
     end
    end
   end
   if(owner_busy && (owner_management?management_submitted:rt_submitted))seen_done<=1;
   if(line_finish)begin if(!owner_busy)ownership_error<=1;else finish_pending<=1;end
   if(owner_busy && finish_pending && seen_start && seen_done && !start_pending && !rt_busy)begin
    owner_busy<=0;owner_management<=0;finish_pending<=0;seen_done<=0;seen_start<=0;cooldown<=32;
    if(owner_management)management_release<=1;else begin rt_finish<=1;rr<=queried_slot+1'b1;end
    early_valid<=0;state<=SCAN;slot<=rr;visited<=0;scan_epoch<=candidate_epoch;scan_time<=now;min_window<=32'hffffffff;
   end
   if(!owner_busy && dispatch_enable && init_done && cooldown==0)case(state)
    SCAN:begin
     if(visited==0 && scan_epoch!=candidate_epoch)begin early_valid<=0;scan_epoch<=candidate_epoch;scan_time<=now;min_window<=32'hffffffff;end
     else if(cand_valid)begin
      if(q_fire && bag_q_ready)begin queried_index<=cand_index;queried_exp<=cand_config[243:241];queried_slot<=slot;queried_lead<={16'd0,cand_length}<<1;state<=QUERY;end
     end else if(visited==7)state<=DECIDE;
     else begin visited<=visited+1'b1;slot<=slot+1'b1;end
    end
    QUERY:if(bag_result_valid)begin
     if(result_due && candidate_epoch==scan_epoch)begin permit_remaining<=0;state<=OFFER;end
     else if(candidate_epoch!=scan_epoch)begin early_valid<=0;state<=SCAN;slot<=rr;visited<=0;scan_epoch<=candidate_epoch;scan_time<=now;min_window<=32'hffffffff;end
     else begin
      if(!early_valid && entry_remaining<=queried_lead)begin
       early_valid<=1;early_slot<=queried_slot;early_exp<=queried_exp;early_index<=queried_index;
       early_remaining<=entry_remaining;early_tick<=now;
      end
      if(entry_remaining<min_window)min_window<=entry_remaining;
      if(visited==7)state<=DECIDE;else begin visited<=visited+1'b1;slot<=slot+1'b1;state<=SCAN;end
     end
    end
    DECIDE:begin
     available_window<=current_window;
     if(candidate_epoch==scan_epoch && early_valid)begin
      queried_slot<=early_slot;queried_exp<=early_exp;queried_index<=early_index;
      permit_remaining<=early_elapsed>=early_remaining?0:early_remaining-early_elapsed;
      state<=OFFER;
     end else if(candidate_epoch==scan_epoch && management_candidate && mgmt_due && service_valid &&
         cached_length==management_length && management_service<=current_window)begin
      owner_busy<=1;owner_management<=1;owner_exp<=management_period;owner_index<=0;
      seen_start<=0;seen_done<=0;finish_pending<=0;start_pending<=0;mgmt_grant<=1;
     end
     early_valid<=0;if(!(candidate_epoch==scan_epoch && early_valid))state<=SCAN;slot<=rr;visited<=0;scan_epoch<=candidate_epoch;scan_time<=now;min_window<=32'hffffffff;
    end
    OFFER:if(grant_ready)begin
     owner_busy<=1;owner_management<=0;owner_index<=queried_index;owner_exp<=queried_exp;
     seen_start<=0;seen_done<=0;finish_pending<=0;start_pending<=0;state<=SCAN;
    end
   endcase
  end
 end
endmodule
