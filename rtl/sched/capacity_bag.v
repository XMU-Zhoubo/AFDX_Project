// C20 shared RAM shaper. Background visits keep saturated ages wrap-safe.
// A scan finishes in <= 3*128 clocks absent requests. A query/update also
// refreshes an entry; the controller bounds foreground use to eight slots.
module capacity_bag #(parameter ENTRIES=128) (
 input wire clk,rst_n,input wire [31:0] now,
 output reg init_done,
 input wire start_valid,input wire [6:0] start_index,input wire [2:0] start_exp,
 output wire start_ready,
 input wire q_valid,output wire q_ready,input wire [6:0] q_index,input wire [2:0] q_exp,
 output reg result_valid,input wire result_ready,
 output reg eligible,output reg [31:0] remaining
);
 localparam MAX_AGE=12800000;
 (* ramstyle="M4K" *) reg [31:0] age_mem[0:ENTRIES-1],tick_mem[0:ENTRIES-1];
 (* ramstyle="M4K" *) reg [3:0] flags_mem[0:ENTRIES-1]; // seen, historic exponent
 reg [6:0] clear_index,scan_index,index_reg;
 reg [31:0] age_q,tick_q;
 reg [3:0] flags_q;
 reg [2:0] exp_reg;
 reg [1:0] state,operation;
 reg [1:0] foreground;
 wire [31:0] delta=now-tick_q;
 wire [32:0] advanced={1'b0,age_q}+{1'b0,delta};
 wire [31:0] actual_age=advanced>=MAX_AGE?MAX_AGE:advanced[31:0];
 wire [2:0] required_exp=flags_q[2:0]>exp_reg?flags_q[2:0]:exp_reg;
 wire [31:0] required=32'd100000 << required_exp;
 // At most three foreground accesses before an obligatory background visit.
 assign start_ready=rst_n && init_done && state==0 && foreground!=3;
 assign q_ready=start_ready && !start_valid && (!result_valid || result_ready);
 wire [6:0] read_index=start_valid && start_ready ? start_index :
     q_valid && q_ready ? q_index : scan_index;
 wire ram_write=rst_n && (!init_done || state==1);
 wire [6:0] write_index=init_done?index_reg:clear_index;
 always @(posedge clk)begin
  if(ram_write)begin
   age_mem[write_index]<=!init_done?MAX_AGE:operation==2?32'd0:actual_age;
   tick_mem[write_index]<=now;
   flags_mem[write_index]<=!init_done?4'd0:operation==2?{1'b1,exp_reg}:flags_q;
  end
  if(rst_n && init_done && state==0)begin
   age_q<=age_mem[read_index];tick_q<=tick_mem[read_index];flags_q<=flags_mem[read_index];
  end
 end
 always @(posedge clk)begin
  if(!rst_n)begin init_done<=0;clear_index<=0;scan_index<=0;state<=0;operation<=0;foreground<=0;result_valid<=0;eligible<=0;remaining<=0;index_reg<=0;exp_reg<=0;end
  else begin
   if(result_valid && result_ready)result_valid<=0;
   if(!init_done)begin
    if(clear_index==ENTRIES-1)begin init_done<=1;clear_index<=0;end else clear_index<=clear_index+1'b1;
   end else case(state)
    0:begin
      if(start_valid && start_ready)begin
       index_reg<=start_index;exp_reg<=start_exp;operation<=2;foreground<=foreground+1'b1;
       state<=1;
      end else if(q_valid && q_ready)begin
       index_reg<=q_index;exp_reg<=q_exp;operation<=1;foreground<=foreground+1'b1;
       state<=1;
      end else begin
       index_reg<=scan_index;exp_reg<=0;operation<=0;foreground<=0;
       scan_index<=scan_index==ENTRIES-1?0:scan_index+1'b1;state<=1;
      end
    end
    1:begin
      if(operation!=2)begin
       if(operation==1)begin
        result_valid<=1;eligible<=!flags_q[3] || actual_age>=required;
        remaining<=!flags_q[3] || actual_age>=required?0:required-actual_age;
       end
      end
      state<=0;
    end
   endcase
  end
 end
endmodule
