// Single-clock, byte-wide synchronous RAM. Ownership/validity is external.
// No reset of RAM contents: unread/uncommitted bytes are never made valid.
module payload_buffer #(
    parameter CAPACITY = 1471,
    parameter ADDR_WIDTH = 11
) (
    input  wire                  clk,
    input  wire                  write_enable,
    input  wire [ADDR_WIDTH-1:0] write_addr,
    input  wire [7:0]            write_data,
    input  wire                  read_enable,
    input  wire [ADDR_WIDTH-1:0] read_addr,
    output reg  [7:0]            read_data
);
    (* ramstyle = "M4K" *)
    reg [7:0] mem [0:CAPACITY-1];

    always @(posedge clk) begin
        if (write_enable)
            mem[write_addr] <= write_data;
        if (read_enable)
            read_data <= mem[read_addr];
    end
endmodule
