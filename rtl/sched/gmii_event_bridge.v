// Lossless toggle request/ack bridges for first TX_EN and falling TX_EN.
// Scheduler permits at most one owned frame until BOTH confirmations.
// Therefore every source event has a free mailbox; overrun is exposed.
// VL/config association stays in clk-domain owner registers until finish.
module gmii_event_bridge (
    input wire clk, rst_n, gtx_clk, tx_en,
    output reg start_confirmed, finish_confirmed,
    output wire idle,
    output reg overrun
);
    reg [1:0] tx_reset;
    reg previous_en, start_req, finish_req;
    reg start_ack, finish_ack;
    (* async_reg="true" *) reg [1:0] start_sync, finish_sync;
    (* async_reg="true" *) reg [1:0] start_ack_sync, finish_ack_sync;
    always @(posedge gtx_clk or negedge rst_n) begin
        if(!rst_n) tx_reset<=2'b11;
        else tx_reset<={tx_reset[0],1'b0};
    end
    always @(posedge gtx_clk or negedge rst_n) begin
        if(!rst_n) begin previous_en<=0;start_req<=0;finish_req<=0;start_ack_sync<=0;finish_ack_sync<=0;overrun<=0;end
        else if(tx_reset[1]) begin previous_en<=0;start_req<=0;finish_req<=0;start_ack_sync<=0;finish_ack_sync<=0;overrun<=0;end
        else begin
            previous_en<=tx_en;
            start_ack_sync<={start_ack_sync[0],start_ack};
            finish_ack_sync<={finish_ack_sync[0],finish_ack};
            if(tx_en && !previous_en) begin
                if(start_req!=start_ack_sync[1]) overrun<=1;
                else start_req<=!start_req;
            end
            if(!tx_en && previous_en) begin
                if(finish_req!=finish_ack_sync[1]) overrun<=1;
                else finish_req<=!finish_req;
            end
        end
    end
    always @(posedge clk) begin
        if(!rst_n) begin start_sync<=0;finish_sync<=0;start_ack<=0;finish_ack<=0;start_confirmed<=0;finish_confirmed<=0;end
        else begin
            start_sync<={start_sync[0],start_req};finish_sync<={finish_sync[0],finish_req};
            start_confirmed<=start_sync[1]!=start_ack;
            finish_confirmed<=finish_sync[1]!=finish_ack;
            if(start_sync[1]!=start_ack) start_ack<=start_sync[1];
            if(finish_sync[1]!=finish_ack) finish_ack<=finish_sync[1];
        end
    end
    assign idle=(start_sync[1]==start_ack && finish_sync[1]==finish_ack && !start_confirmed && !finish_confirmed);
endmodule
