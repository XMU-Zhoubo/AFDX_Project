// Team byte-stream contract. SOP is generated from accepted LAST boundaries.
// This module is synchronous; it is NOT a clock-domain crossing bridge.
module mac_stream_adapter (
    input  wire       clk,
    input  wire       rst_n,
    input  wire [7:0] s_data,
    input  wire       s_valid,
    output wire       s_ready,
    input  wire       s_last,
    input  wire       s_error,
    output wire [7:0] m_data,
    output wire       m_valid,
    input  wire       m_ready,
    output wire       m_sop,
    output wire       m_last,
    output wire       m_error
);
    reg in_frame;
    wire [10:0] packed_in;
    wire [10:0] packed_out;

    assign packed_in = {!in_frame, s_last, s_error, s_data};
    assign {m_sop, m_last, m_error, m_data} = packed_out;

    always @(posedge clk) begin
        if (!rst_n)
            in_frame <= 1'b0;
        else if (s_valid && s_ready)
            in_frame <= !s_last;
    end

    stream_stage #(.DATA_WIDTH(11)) byte_stage (
        .clk(clk), .rst_n(rst_n),
        .s_data(packed_in), .s_valid(s_valid), .s_ready(s_ready),
        .m_data(packed_out), .m_valid(m_valid), .m_ready(m_ready)
    );
endmodule
