// C34 engineering A4 LUS profile, pinned public source + user-frozen contract.
// D=0/N=0, BE integers; ratio is exactly three right-aligned ASCII digits.
// This bounded sender is not an arbitrary LUS parser or a completed upload.
module arinc615a_lus (
 input wire clk,rst_n,cancel,input wire cmd_valid,output wire cmd_ready,
 input wire [15:0] version,status,counter,input wire [7:0] ratio,
 output wire [7:0] m_data,output wire m_valid,m_last,input wire m_ready,
 output reg result_valid,input wire result_ready,output reg result_error
);
 reg active;reg [4:0] index;reg [15:0] code,serial;reg [7:0] value;
 reg [3:0] tens,ones;
 always @* begin
  if(value>=100)begin tens=0;ones=0;end
  else if(value>=90)begin tens=9;ones=value-90;end
  else if(value>=80)begin tens=8;ones=value-80;end
  else if(value>=70)begin tens=7;ones=value-70;end
  else if(value>=60)begin tens=6;ones=value-60;end
  else if(value>=50)begin tens=5;ones=value-50;end
  else if(value>=40)begin tens=4;ones=value-40;end
  else if(value>=30)begin tens=3;ones=value-30;end
  else if(value>=20)begin tens=2;ones=value-20;end
  else if(value>=10)begin tens=1;ones=value-10;end
  else begin tens=0;ones=value[3:0];end
 end
 assign cmd_ready=rst_n && !active && !result_valid;
 assign m_valid=rst_n && active;assign m_last=index==19;
 assign m_data=index==3?8'd20:index==4?8'h41:index==5?8'h34:
  index==6?code[15:8]:index==7?code[7:0]:index==9?serial[15:8]:index==10?serial[7:0]:
  index==15?(value==100?8'h31:8'h20):
  index==16?(value==100?8'h30:value>=10?8'h30+{4'd0,tens}:8'h20):
  index==17?8'h30+{4'd0,ones}:8'd0;
 always @(posedge clk)begin
  if(!rst_n)begin active<=0;index<=0;code<=0;serial<=0;value<=0;result_valid<=0;result_error<=0;end
  else begin
   if(result_valid && result_ready)result_valid<=0;
   if(cmd_valid && cmd_ready)begin
    index<=0;code<=status;serial<=counter;value<=ratio;
    if(version!=16'h4134 || ratio>100 || !(status==1 || status==2 || status==3 || status==16'h1000 || status==16'h1002))begin result_valid<=1;result_error<=1;end
    else begin active<=1;result_error<=0;end
   end
   if(m_valid && m_ready)begin if(m_last)begin active<=0;result_valid<=1;end else index<=index+1'b1;end
   if(cancel)begin active<=0;result_valid<=0;index<=0;end
  end
 end
endmodule
