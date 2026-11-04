// One-entry elastic stage. Transfers use pre-edge valid && ready.
module stream_stage #(
    parameter DATA_WIDTH = 8
) (
    input  wire                  clk,
    input  wire                  rst_n,
    input  wire [DATA_WIDTH-1:0] s_data,
    input  wire                  s_valid,
    output wire                  s_ready,
    output wire [DATA_WIDTH-1:0] m_data,
    output wire                  m_valid,
    input  wire                  m_ready
);
    reg full;
    reg [DATA_WIDTH-1:0] data_reg;

    assign s_ready = rst_n && (!full || m_ready);
    assign m_valid = rst_n && full;
    assign m_data = full ? data_reg : {DATA_WIDTH{1'b0}};

    always @(posedge clk) begin
        if (!rst_n) begin
            full <= 1'b0;
            data_reg <= {DATA_WIDTH{1'b0}};
        end else if (s_ready) begin
            full <= s_valid;
            if (s_valid)
                data_reg <= s_data;
        end
    end
endmodule
