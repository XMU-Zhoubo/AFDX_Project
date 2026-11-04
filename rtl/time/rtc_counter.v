// C28: 100 MHz local RTC. Load is a mechanism, never proof of UTC sync.
module rtc_counter (
 input wire clk,rst_n,
 input wire load_valid,output wire load_ready,
 input wire [63:0] load_seconds,input wire [31:0] load_nanoseconds,
 output wire load_result_valid,input wire load_result_ready,
 output wire load_result_error,
 output reg [63:0] seconds,output reg [31:0] nanoseconds,
 output reg time_valid,loaded,seconds_wrapped,
 output wire synchronized
);
 reg result_pending,result_error;
 wire load_fire=load_valid && load_ready;
 wire load_legal=load_nanoseconds<32'd1000000000;
 assign load_ready=rst_n && (!result_pending || load_result_ready);
 assign load_result_valid=rst_n && result_pending;
 assign load_result_error=result_error;
 assign synchronized=1'b0;
 always @(posedge clk)begin
  if(!rst_n)begin
   seconds<=64'd0;nanoseconds<=32'd0;time_valid<=0;loaded<=0;seconds_wrapped<=0;
   result_pending<=0;result_error<=0;
  end else begin
   time_valid<=1;
   if(load_result_valid && load_result_ready)result_pending<=0;
   if(load_fire)begin result_pending<=1;result_error<=!load_legal;end
   if(load_fire && load_legal)begin
    seconds<=load_seconds;nanoseconds<=load_nanoseconds;loaded<=1;seconds_wrapped<=0;
   end else if(nanoseconds>=32'd999999990)begin
    // For arbitrary legal initial ns, new ns is 0..9, including 999999999->9.
    nanoseconds<=nanoseconds-32'd999999990;
    seconds<=seconds+64'd1;
    if(seconds==64'hffffffffffffffff)seconds_wrapped<=1;
   end else nanoseconds<=nanoseconds+32'd10;
  end
 end
endmodule
