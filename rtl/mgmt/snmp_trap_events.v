// True RX resource faults. One immutable pending snapshot + one active agent.
// Cooldown starts at accepted event, never at query or eventual line completion.
module snmp_trap_events #(
 parameter TICK_CYCLES=1000000, RATE_CYCLES=100000
)(
 input wire clk,rst_n,input wire [1:0] faults,input wire [31:0] fault_total,
 input wire [15:0] used,input wire generated_ready,output wire pending_valid,
 output reg [31:0] snapshot_count,output reg [15:0] snapshot_used,
 output wire [31:0] generation_ticks,
 input wire result_valid,result_error,line_complete,input wire [3:0] result_reason,
 output wire [511:0] diagnostics
);
 reg pending;reg [19:0] divider;reg [31:0] ticks,cooldown;
 reg [63:0] cycles,event_cycles,last_event_cycles,last_generation_cycles,last_queue_cycles,last_line_cycles;
 reg [31:0] event_ticks,last_event_ticks,last_generation_ticks;
 reg [31:0] accepted,suppressed,merged,generated,queued,failed,completed;reg [3:0] last_failure;
 wire [1:0] pushes={1'b0,faults[0]}+{1'b0,faults[1]};
 assign pending_valid=rst_n && pending;assign generation_ticks=ticks;
 assign diagnostics={last_line_cycles[31:0],last_queue_cycles[31:0],last_generation_cycles[31:0],last_event_cycles[31:0],last_generation_ticks,last_event_ticks,ticks,{last_failure,11'd0,pending,snapshot_used},completed,failed,queued,generated,merged,suppressed,accepted,fault_total};
 always @(posedge clk)begin
  if(!rst_n)begin
   pending<=0;divider<=0;ticks<=0;cooldown<=0;cycles<=0;event_cycles<=0;event_ticks<=0;
   snapshot_count<=0;snapshot_used<=0;last_event_cycles<=0;last_generation_cycles<=0;last_queue_cycles<=0;last_line_cycles<=0;last_event_ticks<=0;last_generation_ticks<=0;
   accepted<=0;suppressed<=0;merged<=0;generated<=0;queued<=0;failed<=0;completed<=0;last_failure<=0;
  end else begin
   cycles<=cycles+1'b1;
   if(divider==TICK_CYCLES-1)begin divider<=0;ticks<=ticks+1'b1;end else divider<=divider+1'b1;
   if(cooldown!=0)cooldown<=cooldown-1'b1;
   if(pending_valid && generated_ready)begin
    pending<=0;generated<=generated+1'b1;last_event_cycles<=event_cycles;last_event_ticks<=event_ticks;last_generation_cycles<=cycles;last_generation_ticks<=ticks;
   end
   if(pushes!=0)begin
    if(pending)merged<=merged+{30'd0,pushes};
    else if(cooldown!=0)suppressed<=suppressed+{30'd0,pushes};
    else begin
     pending<=1;snapshot_count<=fault_total+{30'd0,pushes};snapshot_used<=used;
     event_cycles<=cycles;event_ticks<=ticks;accepted<=accepted+1'b1;cooldown<=RATE_CYCLES-1;
     // Two simultaneous physical faults form one snapshot; extra occurrence
     // is recorded, and fault_total itself still increases by BOTH events.
     if(pushes==2)merged<=merged+1'b1;
    end
   end
   if(result_valid)begin if(result_error)begin failed<=failed+1'b1;last_failure<=result_reason;end else begin queued<=queued+1'b1;last_queue_cycles<=cycles;end end
   if(line_complete)begin completed<=completed+1'b1;last_line_cycles<=cycles;end
  end
 end
endmodule
