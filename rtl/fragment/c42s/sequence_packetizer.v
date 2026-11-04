// C11 fixed-VL, unfragmented sender. C09 RTL computes both checksums.
// The C10 cache is read twice; only the SN client handshake permits release.
module sequence_packetizer #(
    parameter [15:0] VL_ID = 16'h0001,
    parameter CHECK_FIXED_VL = 1,
    parameter [15:0] IP_ID = 16'h1a2b,
    parameter [7:0] IP_TTL = 8'd1,
    parameter [7:0] SN_VALUE = 8'h01
) (
    input wire clk, rst_n, abort,
    input wire desc_valid,
    output wire desc_ready,
    input wire [7:0] desc_sn,
 input wire desc_fragment,input wire [15:0] desc_ip_id,desc_ip_flags,
    input wire desc_buffer_id,
    input wire [10:0] desc_start_addr,
    input wire [15:0] desc_length, desc_vl,
    input wire [47:0] desc_src_mac, desc_dst_mac,
    input wire [31:0] desc_src_ip, desc_dst_ip,
    input wire [15:0] desc_src_port, desc_dst_port,
    output wire read_valid,
    input wire read_ready,
    input wire [7:0] payload_data,
    input wire payload_valid,
    output wire payload_ready,
    input wire payload_last,
    input wire [10:0] payload_addr,
    output wire release_valid,
    input wire release_ready,
    output wire [7:0] m_data,
    output wire m_valid,
    input wire m_ready,
    output wire m_sop, m_last, m_error,
    output wire busy,
    output reg frame_submitted,
    output reg [15:0] ipv4_checksum, udp_checksum,
    output reg ipv4_done, udp_done,
    output wire error_valid,
    input wire error_ready,
    output wire [2:0] error_code,
    output wire cancel_task
);
    reg [7:0] sn_latched;
 reg fragment;reg [15:0] message_id,ip_flags;
    localparam [3:0] ST_IDLE = 4'd0, ST_IP_CMD = 4'd1, ST_IP_DATA = 4'd2,
        ST_IP_RESULT = 4'd3, ST_UDP_CMD = 4'd4, ST_UDP_HEADER = 4'd5,
        ST_UDP_READ = 4'd6, ST_UDP_PAYLOAD = 4'd7, ST_UDP_RESULT = 4'd8,
        ST_SEND_READ = 4'd9, ST_HEADER = 4'd10, ST_PAYLOAD = 4'd11,
        ST_PADDING = 4'd12, ST_SN = 4'd13, ST_RELEASE = 4'd14, ST_ERROR = 4'd15;
    reg [3:0] state;
    reg [2:0] error_reg;
    reg [15:0] length_reg, ip_length_reg, udp_length_reg;
    reg [47:0] src_mac_reg, dst_mac_reg;
    reg [31:0] src_ip_reg, dst_ip_reg;
    reg [15:0] src_port_reg, dst_port_reg;
    reg [5:0] byte_index;
    reg [10:0] payload_index;
    reg [4:0] padding_count, padding_left;
    reg [7:0] frame_data;
    wire enabled = rst_n && !abort && state != ST_ERROR;
    wire checksum_rst_n = rst_n && !abort && state != ST_ERROR;
    wire ip_cmd_ready, ip_s_ready, ip_result_valid, ip_result_error;
    wire [15:0] ip_result;
    wire udp_cmd_ready, udp_s_ready, udp_result_valid, udp_result_error;
    wire [15:0] udp_result;
    wire udp_input_valid, udp_input_last;
    wire [7:0] udp_input_data;
    wire [15:0] descriptor_padding = 16'd17 - desc_length;
    wire [5:0] ip_send_index = byte_index - 6'd14;
    wire [5:0] udp_send_index = byte_index - 6'd34;

    function [7:0] ip_byte;
        input [4:0] index;
        input [15:0] check_value;
        begin
            case (index)
                0: ip_byte = 8'h45;
                1: ip_byte = 8'h00;
                2: ip_byte = ip_length_reg[15:8];
                3: ip_byte = ip_length_reg[7:0];
                4: ip_byte = message_id[15:8];
                5: ip_byte = message_id[7:0];
                6: ip_byte = ip_flags[15:8];
                7: ip_byte = ip_flags[7:0];
                8: ip_byte = IP_TTL;
                9: ip_byte = 8'h11;
                10: ip_byte = check_value[15:8];
                11: ip_byte = check_value[7:0];
                12: ip_byte = src_ip_reg[31:24];
                13: ip_byte = src_ip_reg[23:16];
                14: ip_byte = src_ip_reg[15:8];
                15: ip_byte = src_ip_reg[7:0];
                16: ip_byte = dst_ip_reg[31:24];
                17: ip_byte = dst_ip_reg[23:16];
                18: ip_byte = dst_ip_reg[15:8];
                19: ip_byte = dst_ip_reg[7:0];
                default: ip_byte = 8'h00;
            endcase
        end
    endfunction
    function [7:0] udp_byte;
        input [2:0] index;
        input [15:0] check_value;
        begin
            case (index)
                0: udp_byte = src_port_reg[15:8];
                1: udp_byte = src_port_reg[7:0];
                2: udp_byte = dst_port_reg[15:8];
                3: udp_byte = dst_port_reg[7:0];
                4: udp_byte = udp_length_reg[15:8];
                5: udp_byte = udp_length_reg[7:0];
                6: udp_byte = check_value[15:8];
                7: udp_byte = check_value[7:0];
            endcase
        end
    endfunction

    assign desc_ready = enabled && state == ST_IDLE;
    assign read_valid = enabled && (state == ST_UDP_READ || state == ST_SEND_READ);
    assign release_valid = enabled && state == ST_RELEASE;
    assign payload_ready = enabled && ((state == ST_UDP_PAYLOAD && udp_s_ready) ||
                                      (state == ST_PAYLOAD && m_ready));
    assign busy = state != ST_IDLE;
    assign cancel_task = rst_n && state == ST_ERROR;
    assign error_valid = rst_n && !abort && state == ST_ERROR;
    assign error_code = error_reg;
    assign m_valid = enabled && (state == ST_HEADER || state == ST_PADDING ||
                                state == ST_SN || (state == ST_PAYLOAD && payload_valid));
    assign m_data = frame_data;
    assign m_sop = state == ST_HEADER && byte_index == 0;
    assign m_last = state == ST_SN;
    assign m_error = 1'b0;
    assign udp_input_valid = enabled && (state == ST_UDP_HEADER ||
                                       (state == ST_UDP_PAYLOAD && payload_valid));
    assign udp_input_data = state == ST_UDP_HEADER ? udp_byte(byte_index[2:0], 16'h0000) : payload_data;
    assign udp_input_last = state == ST_UDP_PAYLOAD && payload_last;

    checksum_ipv4 ipv4_unit (
        .clk(clk), .rst_n(checksum_rst_n), .cmd_valid(enabled && state == ST_IP_CMD),
        .cmd_ready(ip_cmd_ready), .cmd_verify(1'b0),
        .s_data(ip_byte(byte_index[4:0], 16'h0000)), .s_valid(enabled && state == ST_IP_DATA),
        .s_ready(ip_s_ready), .s_last(byte_index == 19), .m_checksum(ip_result),
        .m_valid(ip_result_valid), .m_ready(enabled && state == ST_IP_RESULT), .m_error(ip_result_error),
        .m_verify(), .m_check_ok()
    );
    checksum_udp #(.MAX_UDP_BYTES(1479)) udp_unit (
        .clk(clk), .rst_n(checksum_rst_n), .cmd_valid(enabled && state == ST_UDP_CMD),
        .cmd_ready(udp_cmd_ready), .cmd_verify(1'b0), .cmd_src_ip(src_ip_reg), .cmd_dst_ip(dst_ip_reg),
        .cmd_udp_length(udp_length_reg), .s_data(udp_input_data), .s_valid(udp_input_valid),
        .s_ready(udp_s_ready), .s_last(udp_input_last), .m_checksum(udp_result),
        .m_valid(udp_result_valid), .m_ready(enabled && state == ST_UDP_RESULT), .m_error(udp_result_error),
        .m_verify(), .m_check_ok(), .m_udp_zero()
    );

    always @* begin
        frame_data = 8'h00;
        if (state == ST_HEADER) begin
            if (byte_index >= 14 && byte_index < 34)
                frame_data = ip_byte(ip_send_index[4:0], ipv4_checksum);
            else if (byte_index >= 34)
                frame_data = udp_byte(udp_send_index[2:0], udp_checksum);
            else begin
                case (byte_index)
                    0: frame_data = dst_mac_reg[47:40];
                    1: frame_data = dst_mac_reg[39:32];
                    2: frame_data = dst_mac_reg[31:24];
                    3: frame_data = dst_mac_reg[23:16];
                    4: frame_data = dst_mac_reg[15:8];
                    5: frame_data = dst_mac_reg[7:0];
                    6: frame_data = src_mac_reg[47:40];
                    7: frame_data = src_mac_reg[39:32];
                    8: frame_data = src_mac_reg[31:24];
                    9: frame_data = src_mac_reg[23:16];
                    10: frame_data = src_mac_reg[15:8];
                    11: frame_data = src_mac_reg[7:0];
                    12: frame_data = 8'h08;
                    13: frame_data = 8'h00;
                    default: frame_data = 8'h00;
                endcase
            end
        end else if (state == ST_PAYLOAD) frame_data = payload_data;
        else if (state == ST_SN) frame_data = sn_latched;
    end

    always @(posedge clk) begin
        if (!rst_n || abort) begin
            state <= ST_IDLE; sn_latched <= 0;fragment<=0;message_id<=0;ip_flags<=0;
            error_reg <= 3'd0;
            length_reg <= 16'd0; ip_length_reg <= 16'd0; udp_length_reg <= 16'd0;
            src_mac_reg <= 48'd0; dst_mac_reg <= 48'd0;
            src_ip_reg <= 32'd0; dst_ip_reg <= 32'd0;
            src_port_reg <= 16'd0; dst_port_reg <= 16'd0;
            byte_index <= 6'd0; payload_index <= 11'd0;
            padding_count <= 5'd0; padding_left <= 5'd0;
            ipv4_checksum <= 16'd0; udp_checksum <= 16'd0;
            frame_submitted <= 1'b0; ipv4_done <= 1'b0; udp_done <= 1'b0;
        end else begin
            frame_submitted <= 1'b0; ipv4_done <= 1'b0; udp_done <= 1'b0;
            case (state)
                ST_IDLE: if (desc_valid && desc_ready) begin
                    if (desc_buffer_id || desc_start_addr != 0 || (CHECK_FIXED_VL && desc_vl != VL_ID) ||
                        desc_length == 0 || desc_length > (desc_fragment?1480:1471)) begin
                        state <= ST_ERROR; error_reg <= 3'd1;
                    end else begin
                        sn_latched <= desc_sn;fragment<=desc_fragment;message_id<=desc_fragment?desc_ip_id:IP_ID;ip_flags<=desc_fragment?desc_ip_flags:16'h4000;
                        length_reg <= desc_length;
                        ip_length_reg <= desc_length + (desc_fragment?16'd20:16'd28);
                        udp_length_reg <= desc_length + 16'd8;
                        src_mac_reg <= desc_src_mac; dst_mac_reg <= desc_dst_mac;
                        src_ip_reg <= desc_src_ip; dst_ip_reg <= desc_dst_ip;
                        src_port_reg <= desc_src_port; dst_port_reg <= desc_dst_port;
                        // Only lengths1..16 use this proven 0..16 slice.
                        padding_count <= desc_fragment?(desc_length<25?25-desc_length:0):(desc_length<17?descriptor_padding[4:0]:0);
                        byte_index <= 6'd0; payload_index <= 11'd0;
                        state <= ST_IP_CMD;
                    end
                end
                ST_IP_CMD: if (ip_cmd_ready) begin byte_index <= 0; state <= ST_IP_DATA; end
                ST_IP_DATA: if (ip_s_ready) begin
                    if (byte_index == 19) state <= ST_IP_RESULT;
                    else byte_index <= byte_index + 6'd1;
                end
                ST_IP_RESULT: if (ip_result_valid) begin
                    if (ip_result_error) begin state <= ST_ERROR; error_reg <= 3'd2; end
                    else begin ipv4_checksum <= ip_result; ipv4_done <= 1'b1; state <= fragment?ST_SEND_READ:ST_UDP_CMD; end
                end
                ST_UDP_CMD: if (udp_cmd_ready) begin byte_index <= 0; state <= ST_UDP_HEADER; end
                ST_UDP_HEADER: if (udp_s_ready) begin
                    if (byte_index == 7) state <= ST_UDP_READ;
                    else byte_index <= byte_index + 6'd1;
                end
                ST_UDP_READ: if (read_ready) begin payload_index <= 0; state <= ST_UDP_PAYLOAD; end
                ST_UDP_PAYLOAD: if (payload_valid && payload_ready) begin
                    if (payload_addr != payload_index ||
                        payload_last != ({5'd0, payload_index} + 16'd1 == length_reg)) begin
                        state <= ST_ERROR; error_reg <= 3'd4;
                    end else if (payload_last) state <= ST_UDP_RESULT;
                    else payload_index <= payload_index + 11'd1;
                end
                ST_UDP_RESULT: if (udp_result_valid) begin
                    if (udp_result_error) begin state <= ST_ERROR; error_reg <= 3'd3; end
                    else begin udp_checksum <= udp_result; udp_done <= 1'b1; state <= ST_SEND_READ; end
                end
                ST_SEND_READ: if (read_ready) begin
                    byte_index <= 0; payload_index <= 0; state <= ST_HEADER;
                end
                ST_HEADER: if (m_valid && m_ready) begin
                    if (byte_index == (fragment?33:41)) state <= ST_PAYLOAD;
                    else byte_index <= byte_index + 6'd1;
                end
                ST_PAYLOAD: if (payload_valid && payload_ready) begin
                    if (payload_addr != payload_index ||
                        payload_last != ({5'd0, payload_index} + 16'd1 == length_reg)) begin
                        state <= ST_ERROR; error_reg <= 3'd4;
                    end else if (payload_last) begin
                        padding_left <= padding_count;
                        state <= padding_count == 0 ? ST_SN : ST_PADDING;
                    end else payload_index <= payload_index + 11'd1;
                end
                ST_PADDING: if (m_valid && m_ready) begin
                    if (padding_left == 1) state <= ST_SN;
                    else padding_left <= padding_left - 5'd1;
                end
                ST_SN: if (m_valid && m_ready) begin frame_submitted <= 1'b1; state <= ST_RELEASE; end
                ST_RELEASE: if (release_ready) state <= ST_IDLE;
                ST_ERROR: if (error_ready) state <= ST_IDLE;
                default: begin state <= ST_ERROR; error_reg <= 3'd7; end
            endcase
        end
    end
endmodule
