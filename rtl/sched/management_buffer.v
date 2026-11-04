// Ordinary Ethernet-II/IPv4/UDP client frame store. No preamble/SFD/FCS.
// Complete data + explicit commit before any candidate; synchronous1514x8RAM.
module management_buffer (
    input wire clk,rst_n,abort,freeze,
    input wire [15:0] configured_max,
    input wire cmd_valid,
    output wire cmd_ready,
    input wire [15:0] cmd_length,
    input wire [7:0] s_data,
    input wire s_valid,s_last,
    output wire s_ready,
    input wire commit_valid,
    output wire commit_ready,
    input wire launch,release_frame,
    output wire candidate,busy,
    output reg released,submitted,error_valid,
    input wire error_ready,
    output reg [2:0] error_code,
    output wire [15:0] length,
    output wire [7:0] m_data,
    output wire m_valid,m_sop,m_last,
    input wire m_ready
);
    localparam IDLE=0,FILL=1,COMPLETE=2,QUEUED=3,FETCH=4,SEND=5,OWNED=6;
    reg [2:0] state;
    reg [15:0] count,frame_length;
    reg [10:0] read_addr;
    wire write_fire=s_valid && s_ready;
    wire [7:0] ram_data;
    payload_buffer #(.CAPACITY(1514)) ram (.clk(clk),.write_enable(write_fire),.write_addr(count[10:0]),.write_data(s_data),.read_enable(state==FETCH && rst_n),.read_addr(read_addr),.read_data(ram_data));
    assign cmd_ready=rst_n && !freeze && state==IDLE && (!error_valid || error_ready);
    assign s_ready=rst_n && state==FILL && count<frame_length && count<1514;
    assign commit_ready=rst_n && state==COMPLETE;
    assign candidate=rst_n && state==QUEUED;
    assign busy=state!=IDLE;
    assign length=frame_length;
    assign m_valid=rst_n && state==SEND;
    assign m_data=ram_data;
    assign m_sop=read_addr==0;
    assign m_last={5'd0,read_addr}+16'd1==frame_length;
    always @(posedge clk) begin
        if(!rst_n)begin state<=IDLE;count<=0;frame_length<=0;read_addr<=0;released<=0;submitted<=0;error_valid<=0;error_code<=0;end
        else begin
            released<=0;submitted<=0;
            if(error_valid && error_ready)error_valid<=0;
            if(abort)begin state<=IDLE;count<=0;frame_length<=0;read_addr<=0;error_valid<=0;end
            else case(state)
              IDLE:if(cmd_valid && cmd_ready)begin
                count<=0;read_addr<=0;
                if(cmd_length<43 || cmd_length>1514 || cmd_length>configured_max)begin error_valid<=1;error_code<=1;end
                else begin frame_length<=cmd_length;state<=FILL;end
              end
              FILL:if(write_fire)begin
                count<=count+16'd1;
                if(s_last != (count+16'd1==frame_length))begin state<=IDLE;error_valid<=1;error_code<=s_last?2:3;end
                else if(s_last)state<=COMPLETE;
              end
              COMPLETE:if(commit_valid && commit_ready)state<=QUEUED;
              QUEUED:if(launch)begin state<=FETCH;read_addr<=0;end
              FETCH:state<=SEND;
              SEND:if(m_valid && m_ready)begin
                if(m_last)begin state<=OWNED;submitted<=1;end
                else begin read_addr<=read_addr+11'd1;state<=FETCH;end
              end
              OWNED:if(release_frame)begin state<=IDLE;released<=1;frame_length<=0;end
              default:state<=IDLE;
            endcase
        end
    end
endmodule
