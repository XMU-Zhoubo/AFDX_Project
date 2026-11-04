// C29 single-server SNTPv4. Manual ONE sample; no periodic poll/RTC discipline.
// t1 = request command ACCEPTANCE at UDP encapsulator (pre-queue software-like
// transmit timestamp); t4 = first dest-MAC byte at common management ingress.
// Their physical-wire displacements are measured, never assumed zero.
module sync_time_client #(
 parameter [31:0] TIMEOUT_CYCLES=32'd500000
)(
 input wire clk,rst_n,input wire [31:0] timeout_cycles,rate_cycles,input wire [31:0] now,input wire [63:0] rtc_seconds,input wire [31:0] rtc_nanoseconds,
 input wire coarse_valid,basis_changed,input wire [31:0] generation,
 input wire start_valid,output wire start_ready,input wire [31:0] transaction,input wire cancel,rearm,
 output wire tx_cmd_valid,input wire tx_cmd_ready,output wire [7:0] tx_data,output wire tx_valid,tx_last,input wire tx_ready,tx_done,tx_error,
 input wire rx_context_valid,output wire rx_context_ready,input wire rx_network,
 input wire [47:0] rx_mac,input wire [31:0] rx_ip,input wire [15:0] rx_port,input wire [9:0] rx_length,
 input wire [63:0] rx_seconds,input wire [31:0] rx_nanoseconds,rx_tick,rx_generation,
 input wire [7:0] rx_data,input wire rx_valid,rx_last,output wire rx_ready,output reg rx_release,
 output wire sample_valid,input wire sample_ready,input wire [4:0] sample_index,output reg [31:0] sample_word,output wire idle,
 output reg trace_valid,output reg [2:0] trace_kind,output reg [31:0] trace_tick,
 output reg [31:0] ignored_count,timeout_count,sample_count,commit_count
);
 reg active,pending,result_wait,have_t1,blocked,rate_limited;reg [31:0] started,rate_since,id,request_generation;
 reg [2:0] tx_phase;reg [3:0] rx_phase;reg [5:0] tx_index;reg [9:0] rx_count;
 reg [63:0] local_seconds,arrival_seconds,t1,t2,t3,t4,last_server_tx;
 reg [31:0] local_ns,arrival_ns,t1_tick,t4_tick,sample_generation,ref_id;
 reg [383:0] packet;reg wanted;reg [3:0] status;reg [1:0] leap;reg [7:0] stratum;
 reg signed [64:0] result_theta,result_delta;
 wire tx_fraction_ready,tx_fraction_valid;wire [31:0] tx_fraction;
 wire rx_fraction_ready,rx_fraction_valid;wire [31:0] rx_fraction;
 wire estimate_ready,estimate_valid;wire signed [64:0] estimate_theta,estimate_delta;wire [2:0] estimate_error;
 wire [63:0] local_ntp_seconds=local_seconds+64'd2208988800;
 wire [63:0] arrival_ntp_seconds=arrival_seconds+64'd2208988800;
 wire [31:0] elapsed=now-started,rate_age=now-rate_since;
 ntp_fraction transmit_fraction(.clk(clk),.rst_n(rst_n),.s_valid(tx_phase==2),.s_ready(tx_fraction_ready),.s_nanoseconds(local_ns),.m_valid(tx_fraction_valid),.m_ready(tx_phase==3),.m_fraction(tx_fraction));
 ntp_fraction receive_fraction(.clk(clk),.rst_n(rst_n),.s_valid(rx_phase==3),.s_ready(rx_fraction_ready),.s_nanoseconds(arrival_ns),.m_valid(rx_fraction_valid),.m_ready(rx_phase==4),.m_fraction(rx_fraction));
 time_estimator estimator(.clk(clk),.rst_n(rst_n),.s_valid(rx_phase==5),.s_ready(estimate_ready),.t1(t1),.t2(t2),.t3(t3),.t4(t4),.m_valid(estimate_valid),.m_ready(rx_phase==6),.theta(estimate_theta),.delta(estimate_delta),.error(estimate_error));
 assign start_ready=rst_n && !active && !pending && !result_wait && tx_phase==0 && rx_phase==0;
 assign tx_cmd_valid=rst_n && tx_phase==1;
 assign tx_valid=rst_n && tx_phase==4;assign tx_last=tx_index==47;
 // Network byte order. LI0/VN4/mode3, poll exponent4, precision -27.
 assign tx_data=tx_index==0?8'h23:tx_index==2?8'd6:tx_index==3?8'he5:
                tx_index>=40?t1[63-(tx_index-40)*8-:8]:8'd0;
 assign rx_context_ready=rst_n && rx_phase==0;
 assign rx_ready=rst_n && rx_phase==1;
 assign sample_valid=rst_n && pending;
 assign idle=rst_n && !active && tx_phase==0 && rx_phase==0;
 always @*begin
  sample_word=0;
  case(sample_index)
   0:sample_word=id;1:sample_word={16'd0,stratum,2'd0,leap,status};
   2:sample_word=t1[31:0];3:sample_word=t1[63:32];4:sample_word=t2[31:0];5:sample_word=t2[63:32];
   6:sample_word=t3[31:0];7:sample_word=t3[63:32];8:sample_word=t4[31:0];9:sample_word=t4[63:32];
   10:sample_word=result_theta[31:0];11:sample_word=result_theta[63:32];12:sample_word={31'd0,result_theta[64]};
   13:sample_word=result_delta[31:0];14:sample_word=result_delta[63:32];15:sample_word={31'd0,result_delta[64]};
   16:sample_word=arrival_seconds[31:0];17:sample_word=arrival_seconds[63:32];18:sample_word=arrival_ns;
   19:sample_word=t1_tick;20:sample_word=t4_tick;21:sample_word=sample_generation;22:sample_word=ref_id;
   23:sample_word=32'h00010101; // format/point identifiers, NOT accuracy or synchronized
   24:sample_word=0; // no live diagnostics in the immutable result bundle
   25:sample_word=32'hc0000214;26:sample_word=32'h00001003;27:sample_word=32'h00000200;
   28:sample_word={16'd123,15'd0,1'b0}; // fixed checked server/source networkA
   default:sample_word=0;
  endcase
 end
 always @(posedge clk)begin
  if(!rst_n)begin
   active<=0;pending<=0;result_wait<=0;have_t1<=0;blocked<=0;rate_limited<=0;rate_since<=0;started<=0;id<=0;request_generation<=0;
   tx_phase<=0;rx_phase<=0;tx_index<=0;rx_count<=0;local_seconds<=0;local_ns<=0;arrival_seconds<=0;arrival_ns<=0;
   t1<=0;t2<=0;t3<=0;t4<=0;last_server_tx<=0;t1_tick<=0;t4_tick<=0;sample_generation<=0;ref_id<=0;packet<=0;wanted<=0;
   status<=0;leap<=0;stratum<=0;result_theta<=0;result_delta<=0;rx_release<=0;trace_valid<=0;trace_kind<=0;trace_tick<=0;
   ignored_count<=0;timeout_count<=0;sample_count<=0;commit_count<=0;
  end else begin
   trace_valid<=0;rx_release<=0;
   if(sample_valid && sample_ready)pending<=0;
   // Cancellation/timeout cannot expose a changing bundle while a previously
   // offered request or conversion still drains. Publish only when both are
   // quiescent; the network association itself ended at the cancel edge.
   if(result_wait && tx_phase==0 && rx_phase==0)begin pending<=1;result_wait<=0;end
   if(rate_limited && rate_age>=rate_cycles)rate_limited<=0; // RATE: 16s requested ->32s minimum; no automatic poll
   if(rearm)begin blocked<=0;rate_limited<=0;last_server_tx<=0;end
   if(start_valid && start_ready)begin
    id<=transaction;status<=0;have_t1<=0;t1<=0;t2<=0;t3<=0;t4<=0;result_theta<=0;result_delta<=0;stratum<=0;leap<=0;ref_id<=0;
    arrival_seconds<=0;arrival_ns<=0;t1_tick<=0;t4_tick<=0;sample_generation<=generation;request_generation<=generation;
    if(!coarse_valid)begin pending<=1;status<=6;end
    else if(blocked || rate_limited)begin pending<=1;status<=7;end
    else begin active<=1;started<=now;tx_phase<=1;end
   end
   // Transmit ownership continues through a cancel once command was offered.
   // Finish that bounded request; NEVER strand the shared frame producer.
   case(tx_phase)
    1:if(tx_cmd_ready)begin local_seconds<=rtc_seconds;local_ns<=rtc_nanoseconds;t1_tick<=now;tx_phase<=2;
      trace_valid<=1;trace_kind<=0;trace_tick<=now;end
    2:if(tx_fraction_ready)tx_phase<=3;
    3:if(tx_fraction_valid)begin t1<={local_ntp_seconds[31:0],tx_fraction};have_t1<=1;tx_index<=0;tx_phase<=4;end
    4:if(tx_valid && tx_ready)begin if(tx_last)tx_phase<=5;else tx_index<=tx_index+1'b1;end
    5:if(tx_done)begin tx_phase<=0;commit_count<=commit_count+1'b1;trace_valid<=1;trace_kind<=2;trace_tick<=now;
      if(tx_error && active)begin active<=0;result_wait<=1;status<=5;end
     end
    default:begin end
   endcase
   case(rx_phase)
    0:if(rx_context_valid)begin
     wanted<=active && have_t1 && rx_network==0 && rx_mac==48'h020000001003 && rx_ip==32'hc0000214 && rx_port==123 && rx_length==48 && rx_generation==request_generation;
     packet<=0;rx_count<=0;rx_phase<=1;
     // The immutable timestamp travels with this context, not a later frame.
     if(active)begin arrival_seconds<=rx_seconds;arrival_ns<=rx_nanoseconds;t4_tick<=rx_tick;sample_generation<=rx_generation;end
     trace_valid<=1;trace_kind<=1;trace_tick<=rx_tick;
    end
    1:if(rx_valid && rx_ready)begin if(rx_count<48)packet<={packet[375:0],rx_data};rx_count<=rx_count+1'b1;
     if(rx_last)rx_phase<=2;end
    2:begin
     rx_release<=1;rx_phase<=0;
     if(wanted && active && elapsed<timeout_cycles && !basis_changed && !cancel && rx_count==48 && packet[191:128]==t1 && packet[381:379]==4 && packet[378:376]==4)begin
      if(packet[375:368]==0)begin
       if(packet[287:256]==32'h44454e59 || packet[287:256]==32'h52535452 || packet[287:256]==32'h52415445)begin
        active<=0;result_wait<=1;status<=2;ref_id<=packet[287:256];stratum<=0;leap<=packet[383:382];
        if(packet[287:256]==32'h52415445)begin rate_limited<=1;rate_since<=now;end else blocked<=1;
       end else ignored_count<=ignored_count+1'b1;
      end else if(packet[383:382]!=3 && packet[375:368]<=15 && packet[63:0]!=0 && packet[127:64]!=0 && packet[63:0]!=last_server_tx)begin
       t2<=packet[127:64];t3<=packet[63:0];stratum<=packet[375:368];leap<=packet[383:382];ref_id<=packet[287:256];rx_phase<=3;
      end else ignored_count<=ignored_count+1'b1;
     end else ignored_count<=ignored_count+1'b1;
    end
    3:if(rx_fraction_ready)rx_phase<=4;
    4:if(rx_fraction_valid)begin t4<={arrival_ntp_seconds[31:0],rx_fraction};rx_phase<=5;end
    5:if(estimate_ready)rx_phase<=6;
    6:if(estimate_valid)begin
     rx_phase<=0;
     if(active && elapsed<timeout_cycles && !basis_changed && !cancel)begin
      if(estimate_error==0)begin result_theta<=estimate_theta;result_delta<=estimate_delta;active<=0;result_wait<=1;status<=1;sample_count<=sample_count+1'b1;last_server_tx<=t3;trace_valid<=1;trace_kind<=4;trace_tick<=now;end
      else ignored_count<=ignored_count+1'b1;
     end
    end
    default:rx_phase<=0;
   endcase
   if(active && elapsed>=timeout_cycles)begin active<=0;result_wait<=1;status<=3;timeout_count<=timeout_count+1'b1;end
   if(active && (cancel || basis_changed))begin active<=0;result_wait<=1;status<=basis_changed?4'd4:4'd8;end
   if(basis_changed)begin last_server_tx<=0;trace_valid<=1;trace_kind<=3;trace_tick<=now;end
  end
 end
endmodule
