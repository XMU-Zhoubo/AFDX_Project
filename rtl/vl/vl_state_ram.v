// C20 bounded synchronous per-entry state, one RMW update and one read client.
// All four words share a transaction boundary. Counters wrap modulo 2^32.
module vl_state_ram #(
    parameter ENTRY_COUNT=4096,
    parameter RX_MODE=1
) (
    input wire clk,rst_n,
    output reg init_done,
    input wire update_valid,
    output wire update_ready,
    input wire [12:0] update_index,
    input wire update_accepted,
    input wire [15:0] update_length,
    input wire [63:0] update_time,
    input wire [31:0] update_budget,
    input wire [7:0] update_sn,
    input wire update_checked,
    input wire q_valid,
    output wire q_ready,
    input wire [12:0] q_index,
    output reg result_valid,
    input wire result_ready,
    output reg result_error,
    output reg [127:0] result_data,
    output reg error_event
);
    localparam ADDR_BITS=ENTRY_COUNT<=2?1:ENTRY_COUNT<=4?2:ENTRY_COUNT<=8?3:
        ENTRY_COUNT<=16?4:ENTRY_COUNT<=32?5:ENTRY_COUNT<=64?6:ENTRY_COUNT<=128?7:
        ENTRY_COUNT<=256?8:ENTRY_COUNT<=512?9:ENTRY_COUNT<=1024?10:ENTRY_COUNT<=2048?11:12;
    (* ramstyle="M4K" *) reg [31:0] word0[0:ENTRY_COUNT-1],word1[0:ENTRY_COUNT-1];
    (* ramstyle="M4K" *) reg [31:0] word2[0:ENTRY_COUNT-1],word3[0:ENTRY_COUNT-1];
    reg [12:0] clear_index,write_index;
    reg updating,accepted_reg,read_pending,read_bad;
    reg [15:0] length_reg;
    reg [63:0] time_reg;
    reg [31:0] budget_reg,a,b,c,d;
    reg [7:0] sn_reg;
    reg checked_reg;
    // A one-cycle line event may arrive on the host query's response edge.
    // That edge consumes the OLD a/b/c/d into result_data and can safely
    // read the NEW event's RAM address for the following RMW write.
    assign update_ready=rst_n && init_done && !updating;
    assign q_ready=rst_n && init_done && !updating && !read_pending && !update_valid && (!result_valid || result_ready);
    wire update_fire=update_valid && update_ready;
    wire query_fire=q_valid && q_ready;
    wire ram_read=(update_fire && update_index<ENTRY_COUNT) || (query_fire && q_index<ENTRY_COUNT);
    wire [12:0] read_index=update_fire?update_index:q_index;
    wire ram_write=rst_n && (!init_done || updating);
    wire [12:0] write_address=init_done?write_index:clear_index;
    wire [ADDR_BITS-1:0] ram_read_address=read_index[ADDR_BITS-1:0];
    wire [ADDR_BITS-1:0] ram_write_address=write_address[ADDR_BITS-1:0];
    wire [31:0] next0=RX_MODE?a+(accepted_reg?32'd1:32'd0):time_reg[31:0];
    wire [31:0] next1=RX_MODE?b+(accepted_reg?{16'd0,length_reg}:32'd0):time_reg[63:32];
    wire [31:0] next2=RX_MODE?c+(accepted_reg?32'd0:32'd1):budget_reg;
    wire [31:0] next3=RX_MODE?{23'd0,checked_reg,sn_reg}:d+32'd1;
    // One canonical, unreset synchronous read port and one write port.
    // Control prevents a read/write collision; only validity is reset.
    always @(posedge clk)begin
        if(ram_write)begin
            word0[ram_write_address]<=init_done?next0:32'd0;
            word1[ram_write_address]<=init_done?next1:32'd0;
            word2[ram_write_address]<=init_done?next2:32'd0;
            word3[ram_write_address]<=init_done?next3:32'd0;
        end
        if(ram_read)begin a<=word0[ram_read_address];b<=word1[ram_read_address];c<=word2[ram_read_address];d<=word3[ram_read_address];end
    end
    always @(posedge clk) begin
        if(!rst_n)begin init_done<=0;clear_index<=0;updating<=0;read_pending<=0;read_bad<=0;result_valid<=0;result_error<=0;result_data<=0;error_event<=0;end
        else begin
            error_event<=0;
            if(result_valid && result_ready)result_valid<=0;
            if(!init_done)begin
                if(clear_index==ENTRY_COUNT-1)begin init_done<=1;clear_index<=0;end
                else clear_index<=clear_index+13'd1;
            end else begin
                if(updating)updating<=0;
                if(read_pending)begin
                    read_pending<=0;result_valid<=1;result_error<=read_bad;
                    result_data<=read_bad?128'd0:{d,c,b,a};
                end
                if(update_valid && update_ready)begin
                    if(update_index>=ENTRY_COUNT)error_event<=1;
                    else begin
                        write_index<=update_index;accepted_reg<=update_accepted;length_reg<=update_length;
                        time_reg<=update_time;budget_reg<=update_budget;sn_reg<=update_sn;checked_reg<=update_checked;updating<=1;
                    end
                end else if(q_valid && q_ready)begin
                    read_pending<=1;read_bad<=q_index>=ENTRY_COUNT;
                end
            end
        end
    end
endmodule
