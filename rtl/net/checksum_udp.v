// IPv4 UDP adapter: emits its own 12-byte pseudo-header before the UDP stream.
// Input is precisely UDP header + application bytes, never Ethernet padding/SN.
module checksum_udp #(
    parameter MAX_UDP_BYTES = 65535
) (
    input wire clk,
    input wire rst_n,
    input wire cmd_valid,
    output wire cmd_ready,
    input wire cmd_verify,
    input wire [31:0] cmd_src_ip,
    input wire [31:0] cmd_dst_ip,
    input wire [15:0] cmd_udp_length,
    input wire [7:0] s_data,
    input wire s_valid,
    output wire s_ready,
    input wire s_last,
    output wire [15:0] m_checksum,
    output wire m_valid,
    input wire m_ready,
    output wire m_error,
    output wire m_verify,
    output wire m_check_ok,
    output wire m_udp_zero
);
    localparam IDLE = 2'd0, PSEUDO = 2'd1, DATA = 2'd2;
    reg [1:0] phase;
    reg verify_reg;
    reg [31:0] src_ip_reg, dst_ip_reg;
    reg [15:0] length_reg;
    reg [3:0] pseudo_index;
    reg [15:0] byte_index;
    reg [15:0] original_checksum;
    reg header_error;
    reg [7:0] pseudo_data;
    wire length_valid;
    wire [16:0] core_length;
    wire [7:0] core_data;
    wire core_valid, core_ready, core_last;
    wire [15:0] core_checksum;
    wire core_error;

    assign length_valid = (cmd_udp_length >= 8) && (cmd_udp_length <= MAX_UDP_BYTES);
    assign core_length = length_valid ? ({1'b0, cmd_udp_length} + 17'd12) : 17'h1ffff;
    assign core_data = phase == PSEUDO ? pseudo_data :
                       ((!verify_reg && (byte_index == 6 || byte_index == 7)) ? 8'h00 : s_data);
    assign core_valid = rst_n && ((phase == PSEUDO) || (phase == DATA && s_valid));
    assign core_last = phase == DATA && s_last;
    assign s_ready = rst_n && phase == DATA && core_ready;
    assign m_checksum = (!verify_reg && !m_error && core_checksum == 0) ? 16'hffff : core_checksum;
    assign m_error = core_error || header_error;
    assign m_verify = verify_reg;
    // Zero received checksum means 'not verified', not an AFDX acceptance decision.
    assign m_udp_zero = verify_reg && original_checksum == 16'h0000;
    assign m_check_ok = verify_reg && !m_error && !m_udp_zero && core_checksum == 0;

    always @* begin
        case (pseudo_index)
            0: pseudo_data = src_ip_reg[31:24];
            1: pseudo_data = src_ip_reg[23:16];
            2: pseudo_data = src_ip_reg[15:8];
            3: pseudo_data = src_ip_reg[7:0];
            4: pseudo_data = dst_ip_reg[31:24];
            5: pseudo_data = dst_ip_reg[23:16];
            6: pseudo_data = dst_ip_reg[15:8];
            7: pseudo_data = dst_ip_reg[7:0];
            8: pseudo_data = 8'h00;
            9: pseudo_data = 8'h11;
            10: pseudo_data = length_reg[15:8];
            11: pseudo_data = length_reg[7:0];
            default: pseudo_data = 8'h00;
        endcase
    end
    checksum_stream #(.MAX_BYTES(MAX_UDP_BYTES + 12)) core (
        .clk(clk), .rst_n(rst_n), .cmd_valid(cmd_valid), .cmd_ready(cmd_ready),
        .cmd_length(core_length), .s_data(core_data), .s_valid(core_valid),
        .s_ready(core_ready), .s_last(core_last), .m_checksum(core_checksum),
        .m_valid(m_valid), .m_ready(m_ready), .m_error(core_error)
    );
    always @(posedge clk) begin
        if (!rst_n) begin
            phase <= IDLE;
            verify_reg <= 1'b0;
            src_ip_reg <= 32'd0;
            dst_ip_reg <= 32'd0;
            length_reg <= 16'd0;
            pseudo_index <= 4'd0;
            byte_index <= 16'd0;
            original_checksum <= 16'h0000;
            header_error <= 1'b0;
        end else begin
            if (cmd_valid && cmd_ready) begin
                phase <= length_valid ? PSEUDO : IDLE;
                verify_reg <= cmd_verify;
                src_ip_reg <= cmd_src_ip;
                dst_ip_reg <= cmd_dst_ip;
                length_reg <= cmd_udp_length;
                pseudo_index <= 4'd0;
                byte_index <= 16'd0;
                original_checksum <= 16'h0000;
                header_error <= 1'b0;
            end
            if (phase == PSEUDO && core_valid && core_ready) begin
                if (pseudo_index == 11)
                    phase <= DATA;
                else
                    pseudo_index <= pseudo_index + 4'd1;
            end
            if (s_valid && s_ready) begin
                if ((byte_index == 4 && s_data != length_reg[15:8]) ||
                    (byte_index == 5 && s_data != length_reg[7:0]))
                    header_error <= 1'b1;
                if (byte_index == 6)
                    original_checksum[15:8] <= s_data;
                if (byte_index == 7)
                    original_checksum[7:0] <= s_data;
                if (s_last || byte_index == length_reg - 16'd1)
                    phase <= IDLE;
                else
                    byte_index <= byte_index + 16'd1;
            end
        end
    end
endmodule
