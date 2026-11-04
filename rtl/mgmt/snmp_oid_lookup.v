// Numerical OID comparison, bounded16 candidates x at most10 common arcs.
module snmp_oid_lookup(
 input wire clk,rst_n,input wire start_valid,output wire start_ready,input wire successor,
 input wire [5:0] name_count,input wire [1023:0] name_arcs,
 output wire result_valid,input wire result_ready,output reg [4:0] number
);
 localparam IDLE=0,SCAN=1,RESULT=2;reg [1:0] state;reg [4:0] candidate;reg [5:0] position;
 function [31:0] arc;input [4:0] n;input [5:0] p;begin
 case(p)0:arc=1;1:arc=3;2:arc=6;3:arc=1;4:arc=3;5:arc=664;6:arc=2026;7:arc=1;8:arc={27'd0,n};default:arc=0;endcase
 end endfunction
 wire [31:0] current=name_arcs[position[4:0]*32+:32];wire [31:0] target=arc(candidate,position);
 assign start_ready=rst_n && state==IDLE;assign result_valid=rst_n && state==RESULT;
 task next_candidate;begin if(candidate==16)begin number<=0;state<=RESULT;end else begin candidate<=candidate+1'b1;position<=0;end end endtask
 always @(posedge clk)begin
  if(!rst_n)begin state<=IDLE;candidate<=1;position<=0;number<=0;end
  else case(state)
   IDLE:if(start_valid)begin state<=SCAN;candidate<=1;position<=0;number<=0;end
   SCAN:if(position==name_count || position==10)begin
    if((successor && name_count<10) || (!successor && name_count==10))begin number<=candidate;state<=RESULT;end else next_candidate;
   end else if(current==target)position<=position+1'b1;
    else if(successor && current<target)begin number<=candidate;state<=RESULT;end else next_candidate;
   RESULT:if(result_ready)state<=IDLE;
   default:state<=IDLE;
  endcase
 end
endmodule
