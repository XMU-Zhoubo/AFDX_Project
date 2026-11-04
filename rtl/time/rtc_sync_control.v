// C30 exclusive RTC load owner and one-sample discipline. All deadlines use
// this independent 64-bit tick, never the adjustable RTC. Defaults: poll64s,
// retry1/2/4s, fresh192s, RATE32s floor. Test register overrides are explicit.
module rtc_sync_control #(parameter [63:0] INITIAL_TICK=64'd0)(
 input wire clk,rst_n,input wire h_valid,h_write,input wire [7:0] h_address,input wire [31:0] h_data,
 output wire h_ready,h_result_valid,input wire h_result_ready,output reg h_error,output reg [31:0] h_result,
 output wire [63:0] rtc_seconds,output wire [31:0] rtc_nanoseconds,
 output wire [31:0] now,output reg [31:0] generation,output wire basis_changed,coarse_valid,
 output wire start,input wire start_ready,output reg [31:0] transaction,output wire cancel,rearm,
 input wire sample_valid,output wire sample_take,output reg [4:0] sample_index,input wire [31:0] sample_word,
 input wire client_idle,input wire [31:0] ignored_count,timeout_count,sample_count,commit_count,
 input wire [31:0] rx_bad_count,rx_good_count,rx_busy_count,input wire [3:0] rx_reason,
 output reg [31:0] timeout_cycles,rate_cycles
);
 reg [63:0] tick,poll_cycles,retry_cycles,fresh_cycles,last_success,next_delay,wait_age,rate_backoff,success_age;
 reg [63:0] shadow_seconds;reg [31:0] shadow_ns;
 reg [3:0] host;reg [3:0] phase;
 reg enabled,blocked,have_success,record_valid,manual_start,cancel_pulse,rearm_pulse;
 reg [31:0] failures,corrections,rejects,last_reason,last_id,last_generation,last_ignored;
 reg [31:0] saved[0:31],record[0:31];reg [31:0] capture_tick,record_overflow;reg [2:0] retry_count;
 wire record_release=host==0 && h_valid && h_write && h_address==6;
 wire cancel_request=host==0 && h_valid && h_write && h_address==5;
 wire manual_request=host==0 && h_valid && h_write && h_address==3 && shadow_ns<1000000000;
 reg [63:0] target_seconds;reg [31:0] target_ns;
 reg [63:0] frac_product,frac_factor;reg [31:0] frac_bits;reg [5:0] bit_count;
 reg signed [32:0] offset_seconds;reg signed [64:0] theta;
 reg [31:0] max_offset_seconds,max_sample_cycles,hold_cycles,max_delay_q32;
 reg [63:0] corrected_at;reg [63:0] last_target_seconds;reg [31:0] last_target_ns;
 wire synchronized=have_success && success_age<fresh_cycles && !blocked && coarse_valid;
 wire [2:0] sync_state=!coarse_valid?3'd0:blocked?3'd4:!have_success?(failures!=0?3'd5:3'd1):synchronized?3'd2:3'd3;
 assign now=tick[31:0];
 wire load_ready,load_response,load_error,rtc_valid,rtc_loaded,rtc_wrapped;
 wire manual_load=host==2 && phase==0;
 wire auto_load=phase==6;
 wire load_valid=manual_load || auto_load;
 wire [63:0] load_seconds=auto_load?target_seconds:shadow_seconds;
 wire [31:0] load_ns=auto_load?target_ns:shadow_ns;
 assign basis_changed=load_valid && load_ready && load_ns<1000000000;
 assign coarse_valid=rtc_loaded && !rtc_wrapped && rtc_seconds<=64'd4294967295;
 assign h_ready=rst_n && host==0;assign h_result_valid=rst_n && host==1;
 assign start=rst_n && phase==1;
 assign cancel=cancel_pulse;assign rearm=rearm_pulse;
 assign sample_take=rst_n && phase==3;
 wire snapshot_ready,snapshot_valid;wire [63:0] snap_seconds;wire [31:0] snap_ns;
 wire snap_valid,snap_loaded,snap_wrap,snap_sync;
 reg [63:0] snap_tick;
 rtc_counter counter(.clk(clk),.rst_n(rst_n),.load_valid(load_valid),.load_ready(load_ready),.load_seconds(load_seconds),.load_nanoseconds(load_ns),
  .load_result_valid(load_response),.load_result_ready(1'b1),.load_result_error(load_error),.seconds(rtc_seconds),.nanoseconds(rtc_nanoseconds),
  .time_valid(rtc_valid),.loaded(rtc_loaded),.seconds_wrapped(rtc_wrapped),.synchronized());
 snapshot reader(.clk(clk),.rst_n(rst_n),.request_valid(host==8),.request_ready(snapshot_ready),.response_valid(snapshot_valid),.response_ready(host==10),
  .rtc_seconds(rtc_seconds),.rtc_nanoseconds(rtc_nanoseconds),.rtc_valid(rtc_valid),.rtc_loaded(rtc_loaded),.rtc_wrapped(rtc_wrapped),.rtc_synchronized(synchronized),
  .response_seconds(snap_seconds),.response_nanoseconds(snap_ns),.response_time_valid(snap_valid),.response_loaded(snap_loaded),.response_wrapped(snap_wrap),.response_synchronized(snap_sync));
 // The fractional multiplication is 32 bounded shift/add steps, no divider.
 wire [63:0] product_next=frac_product+(frac_bits[0]?frac_factor:64'd0);
 wire signed [65:0] sum_seconds=$signed({2'b00,rtc_seconds})+$signed({{33{offset_seconds[32]}},offset_seconds});
 wire [32:0] sum_ns={1'b0,rtc_nanoseconds}+{1'b0,frac_product[63:32]}+33'd20;
 wire [1:0] seconds_carry=sum_ns>=33'd2000000000 ? 2'd2 : sum_ns>=33'd1000000000 ? 2'd1 : 2'd0;
 wire signed [65:0] normalized_seconds=sum_seconds+$signed({64'd0,seconds_carry});
 wire [32:0] normalized_ns=sum_ns>=33'd2000000000 ? sum_ns-33'd2000000000 : sum_ns>=33'd1000000000 ? sum_ns-33'd1000000000 : sum_ns;
 wire [31:0] sample_age=now-saved[20];
 wire stale=sample_age>max_sample_cycles || saved[21]!=generation;
 wire rate_guard=rate_backoff!=0 && wait_age<rate_backoff;
 wire [63:0] effective_delay=next_delay>rate_backoff?next_delay:rate_backoff;
 integer i;
 always @(posedge clk)begin
  if(!rst_n)begin
   tick<=INITIAL_TICK;generation<=0;host<=0;phase<=0;h_error<=0;h_result<=0;shadow_seconds<=0;shadow_ns<=0;
   enabled<=0;blocked<=0;have_success<=0;record_valid<=0;manual_start<=0;cancel_pulse<=0;rearm_pulse<=0;
   poll_cycles<=64'd6400000000;retry_cycles<=64'd100000000;fresh_cycles<=64'd19200000000;
   timeout_cycles<=500000;rate_cycles<=32'd3200000000;max_offset_seconds<=1;max_sample_cycles<=1000000;hold_cycles<=0;max_delay_q32<=4294968;
   last_success<=0;next_delay<=0;wait_age<=0;rate_backoff<=0;success_age<=0;retry_count<=0;transaction<=0;failures<=0;corrections<=0;rejects<=0;last_reason<=0;
   last_id<=0;last_generation<=0;last_ignored<=0;sample_index<=0;capture_tick<=0;record_overflow<=0;frac_product<=0;frac_factor<=0;frac_bits<=0;bit_count<=0;offset_seconds<=0;theta<=0;
   target_seconds<=0;target_ns<=0;corrected_at<=0;last_target_seconds<=0;last_target_ns<=0;snap_tick<=0;
   for(i=0;i<32;i=i+1)begin saved[i]<=0;record[i]<=0;end
  end else begin
   tick<=tick+1'b1;cancel_pulse<=0;rearm_pulse<=0;
   if(wait_age!=64'hffffffffffffffff)wait_age<=wait_age+1'b1;
   if(have_success && success_age!=64'hffffffffffffffff)success_age<=success_age+1'b1;
   if(basis_changed)generation<=generation+1'b1;
   if(ignored_count!=last_ignored)begin last_ignored<=ignored_count;last_reason<=9;end
   case(host)
    0:if(h_valid)begin
     h_error<=0;h_result<=0;host<=1;
     if(h_write && h_address>=65 && h_address<=76 && (enabled || !client_idle || phase!=0))h_error<=1;
     else if(h_write)case(h_address)
      0:shadow_seconds[31:0]<=h_data;1:shadow_seconds[63:32]<=h_data;2:shadow_ns<=h_data;
      3:if(shadow_ns<1000000000)begin host<=2;cancel_pulse<=1;enabled<=0;manual_start<=0;end else h_error<=1;
      4:if(client_idle && phase==0 && !blocked && !rate_guard)begin transaction<=h_data;manual_start<=1;end else h_error<=1;
      5:begin cancel_pulse<=1;manual_start<=0;enabled<=0;generation<=generation+1'b1;if(phase!=6 && phase!=7)phase<=0;h_result<=(phase==6 || phase==7)?32'd1:32'd0;last_reason<=8;end
      6:record_valid<=0;7:host<=10;
      8:begin rearm_pulse<=1;blocked<=0;failures<=0;retry_count<=0;rate_backoff<=0;next_delay<=0;wait_age<=0;end
      64:if(!h_data[0] || poll_cycles!=0 && retry_cycles!=0 && fresh_cycles!=0)begin enabled<=h_data[0];if(h_data[0])begin next_delay<=0;wait_age<=0;end end else h_error<=1;
      65:poll_cycles[31:0]<=h_data;66:poll_cycles[63:32]<=h_data;
      67:retry_cycles[31:0]<=h_data;68:retry_cycles[63:32]<=h_data;
      69:fresh_cycles[31:0]<=h_data;70:fresh_cycles[63:32]<=h_data;
      71:if(h_data!=0 && h_data<32'h80000000)timeout_cycles<=h_data;else h_error<=1;
      72:if(h_data!=0)rate_cycles<=h_data;else h_error<=1;
      73:if(h_data<=86400 && h_data!=0)max_offset_seconds<=h_data;else h_error<=1;
      74:if(h_data<32'h80000000 && h_data!=0)max_sample_cycles<=h_data;else h_error<=1;
      75:hold_cycles<=h_data; // Controlled processing hold, also used for stale-sample tests.
      76:if(h_data!=0)max_delay_q32<=h_data;else h_error<=1;
      default:h_error<=1;
     endcase
     else if(h_address>=16 && h_address<=47)begin h_result<=record[(h_address-8'd16)&8'd31];h_error<=!record_valid;end
     else case(h_address)
      8:h_result<={25'd0,synchronized,rtc_wrapped,rtc_loaded,rtc_valid,coarse_valid,client_idle,record_valid};
      9:h_result<=now;10:h_result<=generation;11:h_result<=ignored_count;12:h_result<=timeout_count;13:h_result<=sample_count;14:h_result<=commit_count;
      48:h_result<=snap_seconds[31:0];49:h_result<=snap_seconds[63:32];50:h_result<=snap_ns;
      51:h_result<={28'd0,snap_sync,snap_wrap,snap_loaded,snap_valid};
      52:h_result<=rx_bad_count;53:h_result<={28'd0,rx_reason};54:h_result<=rx_busy_count;55:h_result<=rx_good_count;
      56:h_result<=snap_tick[31:0];57:h_result<=snap_tick[63:32];
      64:h_result<={26'd0,blocked,enabled,1'b0,sync_state};
      65:h_result<=poll_cycles[31:0];66:h_result<=poll_cycles[63:32];67:h_result<=retry_cycles[31:0];68:h_result<=retry_cycles[63:32];
      69:h_result<=fresh_cycles[31:0];70:h_result<=fresh_cycles[63:32];71:h_result<=timeout_cycles;72:h_result<=rate_cycles;
      73:h_result<=max_offset_seconds;74:h_result<=max_sample_cycles;75:h_result<=hold_cycles;
      76:h_result<=max_delay_q32;
      80:h_result<=corrections;81:h_result<=failures;82:h_result<=last_reason;83:h_result<=rejects;
      84:h_result<=last_success[31:0];85:h_result<=last_success[63:32];86:h_result<=success_age[31:0];87:h_result<=success_age[63:32];
      88:h_result<=last_target_seconds[31:0];89:h_result<=last_target_seconds[63:32];90:h_result<=last_target_ns;
      91:h_result<=corrected_at[31:0];92:h_result<=corrected_at[63:32];93:h_result<=effective_delay[31:0];94:h_result<=effective_delay[63:32];
      95:h_result<={24'd0,phase,host};96:h_result<=tick[63:32];
      97:h_result<=record_overflow;
      default:h_error<=1;
     endcase
    end
    1:if(h_result_ready)host<=0;
    2:if(manual_load && load_ready)begin host<=3;record_valid<=0;end
    3:if(load_response)begin h_error<=load_error;host<=1;end
    8:if(snapshot_ready)begin snap_tick<=tick;host<=9;end
    9:if(snapshot_valid)host<=1;
    10:host<=8;
    default:host<=0;
   endcase
   case(phase)
    0:begin
     if(sample_valid)begin sample_index<=0;phase<=2;end
     else if(host!=2 && coarse_valid && !blocked && !rate_guard && (manual_start || enabled && wait_age>=next_delay) && client_idle)begin
      if(!manual_start)transaction<=transaction+1'b1;manual_start<=0;phase<=1;
     end
    end
    1:if(start_ready)begin phase<=0;wait_age<=0;next_delay<=64'hffffffffffffffff;end
    2:begin saved[sample_index]<=sample_word;if(sample_index==31)begin phase<=3;capture_tick<=now;end else sample_index<=sample_index+1'b1;end
    3:begin
     // A separate one-deep host record never backpressures calibration.
     // Consume+replace is atomic; otherwise retain the old complete record
     // and diagnose a dropped diagnostic, not a dropped correction sample.
     if(!record_valid || record_release)begin
      for(i=0;i<32;i=i+1)record[i]<=saved[i];record_valid<=1;
     end else if(record_overflow!=32'hffffffff)record_overflow<=record_overflow+1'b1;
     phase<=4;
    end
    4:if(now-capture_tick>=hold_cycles)begin
     if(saved[1][3:0]==1)begin
      theta<=$signed({saved[12][0],saved[11],saved[10]});
      if(stale || saved[0]==last_id && saved[21]==last_generation)begin rejects<=rejects+1'b1;last_reason<=10;phase<=0;next_delay<=poll_cycles;wait_age<=0;end
      else if(saved[15][0] || saved[14]!=0 || saved[13]>max_delay_q32)begin rejects<=rejects+1'b1;last_reason<=13;phase<=0;next_delay<=poll_cycles;wait_age<=0;end
      else if($signed({saved[12][0],saved[11],saved[10]})>$signed({1'b0,max_offset_seconds,32'd0}) || $signed({saved[12][0],saved[11],saved[10]})<-$signed({1'b0,max_offset_seconds,32'd0}))begin
       rejects<=rejects+1'b1;last_reason<=11;phase<=0;next_delay<=poll_cycles;wait_age<=0;
      end else begin frac_bits<=saved[10];frac_product<=0;frac_factor<=64'd1000000000;bit_count<=0;offset_seconds<=$signed({saved[12][0],saved[11]});phase<=5;end
     end else begin
      if(failures!=32'hffffffff)failures<=failures+1'b1;last_reason<={28'd0,saved[1][3:0]};wait_age<=0;phase<=0;
      if(saved[1][3:0]==2 && (saved[22]==32'h44454e59 || saved[22]==32'h52535452))begin blocked<=1;next_delay<=64'hffffffffffffffff;end
      else if(saved[1][3:0]==2 && saved[22]==32'h52415445)begin
       if(rate_backoff>=64'd102400000000)begin blocked<=1;next_delay<=64'hffffffffffffffff;end
       else if(rate_backoff!=0)begin rate_backoff<=rate_backoff<<1;next_delay<=rate_backoff<<1;end
       else begin rate_backoff<=(poll_cycles<<1)>{32'd0,rate_cycles}?(poll_cycles<<1):{32'd0,rate_cycles};next_delay<=(poll_cycles<<1)>{32'd0,rate_cycles}?(poll_cycles<<1):{32'd0,rate_cycles};end
      end
      else if(retry_count<3)begin next_delay<=retry_cycles<<retry_count;retry_count<=retry_count+1'b1;end else begin next_delay<=poll_cycles;retry_count<=0;end
     end
    end
    5:begin
     frac_product<=product_next;frac_bits<=frac_bits>>1;frac_factor<=frac_factor<<1;
     if(bit_count==31)phase<=8;else bit_count<=bit_count+1'b1;
    end
    8:begin
     // Load port is exclusively owned and its result is always drained. Thus
     // ready is guaranteed across this preparation/acceptance pair. +20ns
     // compensates the preparation edge and replaces the accept edge tick.
     if(stale || host==2 || !coarse_valid || normalized_seconds<0 || normalized_seconds>66'd4294967295)begin rejects<=rejects+1'b1;last_reason<=10;phase<=0;wait_age<=0;next_delay<=poll_cycles;end
     else if(load_ready)begin
      target_seconds<=normalized_seconds[63:0];target_ns<=normalized_ns[31:0];
      phase<=6;
     end
    end
    6:if(load_ready)begin corrected_at<=tick;last_target_seconds<=target_seconds;last_target_ns<=target_ns;phase<=7;end
    7:if(load_response)begin
     if(load_error)begin rejects<=rejects+1'b1;last_reason<=12;end
     else begin corrections<=corrections+1'b1;last_success<=corrected_at;success_age<=tick-corrected_at;have_success<=1;failures<=0;retry_count<=0;rate_backoff<=0;last_reason<=0;last_id<=saved[0];last_generation<=saved[21];end
     phase<=0;wait_age<=0;next_delay<=poll_cycles;
    end
    default:phase<=0;
   endcase
   // Manual load/cancel wins over an unoffered correction. An already offered
   // physical load completes first; its result is never reported as canceled.
   if(host==2 && phase!=6 && phase!=7 && phase!=0)phase<=0;
   // This priority also covers a cancel/manual request on the preparation
   // edge itself. A physical load already offered in phase6 wins, explicitly
   // returned as h_result=1 by cancel; it is never reported as unapplied.
   if((cancel_request || manual_request) && phase!=6 && phase!=7)phase<=0;
   if(manual_load && load_ready)begin have_success<=0;success_age<=0;last_reason<=14;end
  end
 end
endmodule
