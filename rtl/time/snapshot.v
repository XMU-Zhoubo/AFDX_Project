// One response slot. Capture the complete PRE-update RTC at request handshake.
module snapshot (
 input wire clk,rst_n,
 input wire request_valid,output wire request_ready,
 output wire response_valid,input wire response_ready,
 input wire [63:0] rtc_seconds,input wire [31:0] rtc_nanoseconds,
 input wire rtc_valid,rtc_loaded,rtc_wrapped,rtc_synchronized,
 output reg [63:0] response_seconds,output reg [31:0] response_nanoseconds,
 output reg response_time_valid,response_loaded,response_wrapped,response_synchronized
);
 reg pending;
 assign request_ready=rst_n && (!pending || response_ready);
 assign response_valid=rst_n && pending;
 always @(posedge clk)begin
  if(!rst_n)begin
   pending<=0;response_seconds<=0;response_nanoseconds<=0;
   response_time_valid<=0;response_loaded<=0;response_wrapped<=0;response_synchronized<=0;
  end else if(request_valid && request_ready)begin
   pending<=1;response_seconds<=rtc_seconds;response_nanoseconds<=rtc_nanoseconds;
   response_time_valid<=rtc_valid;response_loaded<=rtc_loaded;
   response_wrapped<=rtc_wrapped;response_synchronized<=rtc_synchronized;
  end else if(response_valid && response_ready)pending<=0;
 end
endmodule
