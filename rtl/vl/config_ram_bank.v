// C20 configuration storage: bounded synchronous RAM, no memory/data reset.
// Control validity/ownership is handled by capacity_table. Write collisions
// during reset clear/copy are not consumed as read transactions.
module config_ram_bank (
    input wire clk,
    input wire read_enable,
    input wire write_enable,
    input wire [10:0] address,
    input wire [31:0] write_data,
    output reg [31:0] read_data
);
    (* ramstyle = "M4K" *) reg [31:0] cfg_mem[0:2047];
    always @(posedge clk)begin
        if(read_enable)read_data<=cfg_mem[address];
        if(write_enable)cfg_mem[address]<=write_data;
    end
endmodule
