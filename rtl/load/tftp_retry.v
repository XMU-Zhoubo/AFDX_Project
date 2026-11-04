// RFC1123 4.2.3.2 exponential adaptation. Each individual RTO <2^31 ticks.
// now is independent monotonic100MHz. A due result persists until taken.
module tftp_retry #(
 parameter [31:0] INITIAL_TICKS=32'd100000000,MAX_TICKS=32'd800000000,
 parameter [3:0] MAX_RETRIES=4'd5
) (
 input wire clk,rst_n,input wire [31:0] now,input wire restart,stop,sent,take,
 output wire due,exhausted,output reg armed,output reg [31:0] interval,
 output reg [3:0] attempts
);
 reg [31:0] start_tick;reg expired;
 wire [31:0] elapsed=now-start_tick;
 assign due=rst_n && armed && (expired || elapsed>=interval);
 assign exhausted=due && attempts>=MAX_RETRIES;
 always @(posedge clk)begin
  if(!rst_n)begin armed<=0;interval<=INITIAL_TICKS;attempts<=0;start_tick<=0;expired<=0;end
  else if(stop || restart)begin armed<=0;interval<=INITIAL_TICKS;attempts<=0;expired<=0;end
  else begin
   if(armed && elapsed>=interval)expired<=1;
   if(sent)begin start_tick<=now;armed<=1;expired<=0;end
   if(take && due)begin armed<=0;expired<=0;
    if(!exhausted)begin attempts<=attempts+1'b1;interval<=interval>=MAX_TICKS/2?MAX_TICKS:interval<<1;end
   end
  end
 end
endmodule
