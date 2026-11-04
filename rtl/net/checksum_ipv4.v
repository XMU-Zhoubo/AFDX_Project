// Fixed 20-byte IPv4 header adapter; options and fragments are outside C09.
// Generation zeroes bytes 10/11. Verification retains the received checksum.
module checksum_ipv4 (
    input wire clk,
    input wire rst_n,
    input wire cmd_valid,
    output wire cmd_ready,
    input wire cmd_verify,
    input wire [7:0] s_data,
    input wire s_valid,
    output wire s_ready,
    input wire s_last,
    output wire [15:0] m_checksum,
    output wire m_valid,
    input wire m_ready,
    output wire m_error,
    output wire m_verify,
    output wire m_check_ok
);
    reg verify_reg;
    reg [4:0] byte_index;
    reg header_error;
    wire [7:0] core_data;
    wire core_error;
    assign core_data = (!verify_reg && (byte_index == 10 || byte_index == 11))
                       ? 8'h00 : s_data;
    assign m_error = core_error || header_error;
    assign m_verify = verify_reg;
    assign m_check_ok = verify_reg && !m_error && (m_checksum == 16'h0000);

    checksum_stream #(.MAX_BYTES(20)) core (
        .clk(clk), .rst_n(rst_n), .cmd_valid(cmd_valid), .cmd_ready(cmd_ready),
        .cmd_length(17'd20), .s_data(core_data), .s_valid(s_valid),
        .s_ready(s_ready), .s_last(s_last), .m_checksum(m_checksum),
        .m_valid(m_valid), .m_ready(m_ready), .m_error(core_error)
    );
    always @(posedge clk) begin
        if (!rst_n) begin
            verify_reg <= 1'b0;
            byte_index <= 5'd0;
            header_error <= 1'b0;
        end else begin
            if (cmd_valid && cmd_ready) begin
                verify_reg <= cmd_verify;
                byte_index <= 5'd0;
                header_error <= 1'b0;
            end
            if (s_valid && s_ready) begin
                if (byte_index == 0 && s_data != 8'h45)
                    header_error <= 1'b1;
                if (byte_index < 19)
                    byte_index <= byte_index + 5'd1;
            end
        end
    end
endmodule
