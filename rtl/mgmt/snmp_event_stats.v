// C20 coherent snapshot counters. Live counters wrap modulo 2^32.
// A snapshot copies the complete vector on one clk edge; reads never mix epochs.
module snmp_event_stats #(
    parameter COUNT=28
) (
    input wire clk,rst_n,output wire [31:0] live_resource_count,
    input wire [COUNT*32-1:0] increments,
    input wire snapshot_valid,
    output wire snapshot_ready,
    output reg [31:0] snapshot_epoch,
    input wire read_valid,
    output wire read_ready,
    input wire [5:0] read_index,
    output reg result_valid,
    input wire result_ready,
    output reg result_error,
    output reg [31:0] result_data,
    input wire [15:0] tx_used,tx_free,tx_peak,rx_used,rx_free,rx_peak
);
    reg [31:0] live[0:COUNT-1],snap[0:COUNT+3];
    integer i;assign live_resource_count=live[7];
    assign snapshot_ready=rst_n;
    assign read_ready=rst_n && (!result_valid || result_ready);
    always @(posedge clk)begin
        if(!rst_n)begin
            for(i=0;i<COUNT;i=i+1)begin live[i]<=0;snap[i]<=0;end
            for(i=COUNT;i<COUNT+4;i=i+1)snap[i]<=0;
            snapshot_epoch<=0;result_valid<=0;result_error<=0;result_data<=0;
        end else begin
            for(i=0;i<COUNT;i=i+1)live[i]<=live[i]+increments[i*32+:32];
            if(snapshot_valid && snapshot_ready)begin
                for(i=0;i<COUNT;i=i+1)snap[i]<=live[i];
                snap[COUNT]<={tx_free,tx_used};snap[COUNT+1]<={rx_free,rx_used};
                snap[COUNT+2]<={rx_peak,tx_peak};snap[COUNT+3]<=snapshot_epoch+32'd1;
                snapshot_epoch<=snapshot_epoch+32'd1;
            end
            if(result_valid && result_ready)result_valid<=0;
            if(read_valid && read_ready)begin
                result_valid<=1;result_error<=read_index>=COUNT+4;
                result_data<=read_index<COUNT+4?snap[read_index]:32'd0;
            end
        end
    end
endmodule
