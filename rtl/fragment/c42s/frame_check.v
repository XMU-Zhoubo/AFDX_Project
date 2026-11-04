// C14 single candidate, 100MHz. Received checksum fields are INCLUDED.
// Candidate data never means application commit: only the terminal result does.
module frame_check #(
    parameter ALLOW_ZERO_UDP_CHECKSUM = 1,
    parameter USE_CONFIG = 0,
    parameter [15:0] VL_ID = 16'h0001,
    parameter [31:0] SOURCE_IP = 32'h0a010201,
    parameter [31:0] DEST_IP = 32'he0e00001,
    parameter [15:0] SOURCE_PORT = 16'h1234,
    parameter [15:0] DEST_PORT = 16'h5678
) (
    input wire clk, rst_n,
    // Optional C17 path; ignored with default USE_CONFIG=0.
    input wire cfg_found,
    input wire [255:0] cfg_data,
    input wire [271:0] s_meta_data,
    input wire s_meta_valid,
    output wire s_meta_ready,
    input wire [7:0] s_tail_data,
    input wire s_tail_valid, s_tail_sop, s_tail_last, s_tail_error,
    output wire s_tail_ready,
    input wire s_status_valid,
    output wire s_status_ready,
    input wire [4:0] s_status_code,
    input wire s_status_cancel,
    output wire [63:0] m_meta_data,
    output wire m_meta_valid,
    input wire m_meta_ready,
    output wire [7:0] m_tail_data,
    output wire m_tail_valid, m_tail_sop, m_tail_last,
    input wire m_tail_ready,
    output wire result_valid,
    input wire result_ready,
    output reg result_pass,
    output reg [4:0] result_reason,
    output reg [4:0] result_parser_code,
    output reg result_cancel, result_udp_checked,
    output reg [15:0] result_payload_length,
    output reg [7:0] result_sn,
    output reg [15:0] result_ip_residue, result_udp_residue,
    output reg [31:0] accepted_count, dropped_count
);
    localparam IDLE=4'd0, IP_CMD=4'd1, IP_DATA=4'd2, IP_WAIT=4'd3,
        UDP_HEAD=4'd4, UDP_SETUP=4'd5, UDP_CMD=4'd6, META=4'd7,
        REPLAY=4'd8, STREAM=4'd9, DRAIN=4'd10, FINAL=4'd11,
        RESULT=4'd12, CLEAN=4'd13, FR_META=4'd14, FR_STREAM=4'd15;
    // Priority: parser terminal > IP bounds/address/protocol > IP checksum >
    // UDP bounds/IP-length/ports > actual tail length > zero policy > UDP checksum.
    localparam OK=5'd0, PARSER=5'd1, IP_RANGE=5'd2, DST_IP=5'd3,
        SRC_IP=5'd4, PROTOCOL=5'd5, IP_CHECKSUM=5'd6, UDP_RANGE=5'd7,
        EMPTY=5'd8, IP_UDP_LENGTH=5'd9, DST_PORT=5'd10, SRC_PORT=5'd11,
        TAIL_LENGTH=5'd12, ZERO_POLICY=5'd13, UDP_CHECKSUM=5'd14;
    reg [3:0] state;
    reg [255:0] config_reg;
    wire [15:0] selected_vl = USE_CONFIG ? config_reg[239:224] : VL_ID;
    wire [15:0] selected_src_port = USE_CONFIG ? config_reg[31:16] : SOURCE_PORT;
    wire [15:0] selected_dst_port = USE_CONFIG ? config_reg[15:0] : DEST_PORT;
    reg [159:0] header;
 wire fragment=header[109] || header[108:96]!=0;
    reg [159:0] ip_shift;
    reg [63:0] udp_header;
    reg [4:0] ip_index;
    reg [3:0] head_index, replay_index;
    reg [15:0] udp_length, payload_length, expected_tail, tail_count;
    reg [4:0] early_reason;
    reg udp_ok, udp_zero, udp_done;
    reg [15:0] ip_residue, udp_residue;
    reg terminal_seen, parser_bad, parser_cancel;
    reg [4:0] parser_code;
    reg end_seen, end_forwarded, length_bad;
    reg [7:0] sn;
    reg meta_pending, sum_pending, forward_pending;
    reg [7:0] byte_data;
    reg byte_sop, byte_last, byte_sum_last;
    wire byte_busy = sum_pending || forward_pending;
    wire core_rst_n = rst_n && state != IDLE && state != CLEAN && !parser_bad;
    wire ip_cmd_ready, ip_s_ready, ip_valid, ip_error, ip_check_ok;
    wire [15:0] ip_checksum;
    wire udp_cmd_ready, udp_s_ready, udp_valid, udp_error, udp_check_ok, udp_is_zero;
    wire [15:0] udp_checksum;
    wire [15:0] header_udp_length = udp_header[31:16];
    wire tail_fire = s_tail_valid && s_tail_ready;
    wire status_fire = s_status_valid && s_status_ready;
    wire [15:0] next_tail_count = tail_count < 16'd1481 ? tail_count+16'd1 : 16'd1481;
    reg [4:0] final_reason;
    function [7:0] udp_octet;
        input [3:0] index;
        begin
            case (index)
                0:udp_octet=udp_header[63:56];1:udp_octet=udp_header[55:48];
                2:udp_octet=udp_header[47:40];3:udp_octet=udp_header[39:32];
                4:udp_octet=udp_header[31:24];5:udp_octet=udp_header[23:16];
                6:udp_octet=udp_header[15:8];7:udp_octet=udp_header[7:0];
                default:udp_octet=8'd0;
            endcase
        end
    endfunction

    assign s_meta_ready = rst_n && state == IDLE && !s_status_valid;
    assign s_status_ready = rst_n && !terminal_seen && state != RESULT && state != CLEAN;
    assign s_tail_ready = rst_n && !parser_bad &&
        ((state == UDP_HEAD) || ((state == STREAM || state==FR_STREAM) && !byte_busy && !end_seen) ||
         (state == DRAIN && !end_seen));
    // Minimal C15 candidate descriptor: VL, P, received source/destination ports.
    assign m_meta_data = {selected_vl, payload_length, udp_header[63:32]};
    assign m_meta_valid = rst_n && meta_pending;
    assign m_tail_data = byte_data;
    assign m_tail_valid = rst_n && forward_pending;
    assign m_tail_sop = byte_sop;
    assign m_tail_last = byte_last;
    assign result_valid = rst_n && state == RESULT;

    checksum_ipv4 ip_check (
        .clk(clk),.rst_n(core_rst_n),.cmd_valid(state==IP_CMD),.cmd_ready(ip_cmd_ready),.cmd_verify(1'b1),
        .s_data(ip_shift[159:152]),.s_valid(state==IP_DATA),.s_ready(ip_s_ready),.s_last(ip_index==19),
        .m_checksum(ip_checksum),.m_valid(ip_valid),.m_ready(1'b1),.m_error(ip_error),
        .m_verify(),.m_check_ok(ip_check_ok)
    );
    checksum_udp #(.MAX_UDP_BYTES(1479)) udp_check (
        .clk(clk),.rst_n(core_rst_n),.cmd_valid(state==UDP_CMD),.cmd_ready(udp_cmd_ready),.cmd_verify(1'b1),
        .cmd_src_ip(header[63:32]),.cmd_dst_ip(header[31:0]),.cmd_udp_length(udp_length),
        .s_data(byte_data),.s_valid(sum_pending),.s_ready(udp_s_ready),.s_last(byte_sum_last),
        .m_checksum(udp_checksum),.m_valid(udp_valid),.m_ready(1'b1),.m_error(udp_error),
        .m_verify(),.m_check_ok(udp_check_ok),.m_udp_zero(udp_is_zero)
    );

    always @* begin
        final_reason = OK;
        if (parser_bad) final_reason = PARSER;
        else if (early_reason != OK) final_reason = early_reason;
        else if (length_bad || !end_seen || tail_count != expected_tail) final_reason = TAIL_LENGTH;
        // Actual MAC-client body = Ethernet14 + IPv4 header20 + accepted tail.
        // FCS was stripped by MAC; restore its four bytes for per-VL Lmax.
        else if (USE_CONFIG && ({1'b0,tail_count}+17'd38 > {1'b0,config_reg[223:208]})) final_reason = 5'd15;
        else if (fragment && ((header[109] && payload_length[2:0]!=0) || payload_length==0 || {1'b0,header[108:96],3'b0}+{1'b0,payload_length}>17'd4104)) final_reason=IP_RANGE;
        else if (!fragment && udp_zero && !ALLOW_ZERO_UDP_CHECKSUM) final_reason = ZERO_POLICY;
        else if (!fragment && (!udp_done || (!udp_zero && !udp_ok))) final_reason = UDP_CHECKSUM;
    end
    always @(posedge clk) begin
        if (!rst_n) begin
            state<=IDLE; config_reg<=0; header<=0; udp_header<=0; ip_index<=0; ip_shift<=0;
            head_index<=0; replay_index<=0; udp_length<=0; payload_length<=0; expected_tail<=0; tail_count<=0;
            early_reason<=OK; udp_ok<=0; udp_zero<=0; udp_done<=0;
            ip_residue<=0; udp_residue<=0; terminal_seen<=0; parser_bad<=0; parser_cancel<=0; parser_code<=0;
            end_seen<=0; end_forwarded<=0; length_bad<=0; sn<=0;
            meta_pending<=0; sum_pending<=0; forward_pending<=0; byte_data<=0; byte_sop<=0; byte_last<=0; byte_sum_last<=0;
            result_pass<=0; result_reason<=0; result_parser_code<=0; result_cancel<=0; result_udp_checked<=0;
            result_payload_length<=0; result_sn<=0; result_ip_residue<=0; result_udp_residue<=0;
            accepted_count<=0; dropped_count<=0;
        end else begin
            if (m_meta_valid && m_meta_ready) meta_pending<=0;
            if (sum_pending && udp_s_ready) begin sum_pending<=0; forward_pending<=1; end
            if (m_tail_valid && m_tail_ready) begin
                forward_pending<=0;
                if (byte_last) end_forwarded<=1;
            end
            if (udp_valid) begin
                udp_done<=1; udp_ok<=udp_check_ok && !udp_error; udp_zero<=udp_is_zero; udp_residue<=udp_checksum;
            end
            if (status_fire) begin
                terminal_seen<=1; parser_code<=s_status_code; parser_cancel<=s_status_cancel;
                if (s_status_code!=0 || s_status_cancel) parser_bad<=1;
            end
            if (parser_bad) sum_pending<=0;
            if (parser_bad && state!=IDLE && state!=DRAIN && state!=FINAL && state!=RESULT && state!=CLEAN) begin
                // Abort only local arithmetic. Keep an already valid candidate bundle stable.
                state<=DRAIN; sum_pending<=0;
            end else case (state)
                IDLE: begin
                    if (status_fire) begin
                        // A C13 header rejection can have no metadata/tail at all.
                        result_pass<=0; result_reason<=PARSER; result_parser_code<=s_status_code;
                        result_cancel<=s_status_cancel; result_udp_checked<=0; result_payload_length<=0;
                        result_sn<=0; result_ip_residue<=0; result_udp_residue<=0;
                        dropped_count<=dropped_count+32'd1; state<=RESULT;
                    end else if (s_meta_valid && s_meta_ready) begin
                        config_reg<=cfg_data;
                        header<=s_meta_data[159:0]; ip_shift<=s_meta_data[159:0]; udp_header<=0; ip_index<=0; head_index<=0; replay_index<=0;
                        payload_length<=0; udp_length<=0; expected_tail<=0; tail_count<=0;
                        udp_ok<=0; udp_done<=0; udp_zero<=0; ip_residue<=0; udp_residue<=0;
                        end_seen<=0; end_forwarded<=0; length_bad<=0; sn<=0; early_reason<=OK;
                        meta_pending<=0; sum_pending<=0; forward_pending<=0; state<=IP_CMD;
                        if (USE_CONFIG && !cfg_found) early_reason<=5'd16;
                        else if (s_meta_data[143:128]<(s_meta_data[109] || s_meta_data[108:96]!=0?21:28) || s_meta_data[143:128]>1499) early_reason<=IP_RANGE;
                        else if (s_meta_data[31:0]!=(USE_CONFIG ? cfg_data[63:32] : DEST_IP)) early_reason<=DST_IP;
                        else if (s_meta_data[63:32]!=(USE_CONFIG ? cfg_data[95:64] : SOURCE_IP)) early_reason<=SRC_IP;
                        else if (s_meta_data[87:80]!=8'd17) early_reason<=PROTOCOL;
                    end
                end
                IP_CMD: if (ip_cmd_ready) state<=IP_DATA;
                IP_DATA: if (ip_s_ready) begin
                    ip_shift<=ip_shift<<8;
                    if (ip_index==19) state<=IP_WAIT;
                    else ip_index<=ip_index+5'd1;
                end
                IP_WAIT: if (ip_valid) begin
                    ip_residue<=ip_checksum;
                    if (early_reason!=OK || !ip_check_ok || ip_error) begin
                        if (early_reason==OK) early_reason<=IP_CHECKSUM;
                        state<=DRAIN;
                    end else if(fragment)begin
                        payload_length<=header[143:128]-20;
                        expected_tail<=header[143:128]<45?26:header[143:128]-19;
                        meta_pending<=1;state<=FR_META;
                    end else state<=UDP_HEAD;
                end
                FR_META:if(m_meta_valid && m_meta_ready)state<=FR_STREAM;
                FR_STREAM:if(tail_fire)begin
                    byte_data<=s_tail_data;byte_sop<=tail_count==0;byte_last<=s_tail_last;forward_pending<=1;
                    tail_count<=next_tail_count;
                    if(s_tail_sop!=(tail_count==0) || s_tail_error)length_bad<=1;
                    if(s_tail_last)begin end_seen<=1;sn<=s_tail_data;state<=FINAL;end
                end
                UDP_HEAD: if (tail_fire) begin
                    udp_header<={udp_header[55:0],s_tail_data}; tail_count<=next_tail_count;
                    if (s_tail_sop!=(head_index==0) || s_tail_error) begin early_reason<=PARSER; state<=DRAIN; end
                    else if (s_tail_last) begin
                        end_seen<=1; sn<=s_tail_data; early_reason<=TAIL_LENGTH; state<=DRAIN;
                    end else if (head_index==7) state<=UDP_SETUP;
                    else head_index<=head_index+4'd1;
                end
                UDP_SETUP: begin
                    // Validate before subtracting length or creating a checksum command.
                    if (header_udp_length<8 || header_udp_length>1479) begin early_reason<=UDP_RANGE; state<=DRAIN; end
                    else if (header_udp_length==8) begin early_reason<=EMPTY; state<=DRAIN; end
                    else if ({1'b0,header[143:128]} != {1'b0,header_udp_length}+17'd20) begin early_reason<=IP_UDP_LENGTH; state<=DRAIN; end
                    else if (udp_header[47:32]!=selected_dst_port) begin early_reason<=DST_PORT; state<=DRAIN; end
                    else if (udp_header[63:48]!=selected_src_port) begin early_reason<=SRC_PORT; state<=DRAIN; end
                    else begin
                        udp_length<=header_udp_length; payload_length<=header_udp_length-16'd8;
                        expected_tail<=header_udp_length<25 ? 16'd26 : header_udp_length+16'd1;
                        state<=UDP_CMD;
                    end
                end
                UDP_CMD: if (udp_cmd_ready) begin meta_pending<=1; state<=META; end
                META: if (m_meta_valid && m_meta_ready) begin replay_index<=0; state<=REPLAY; end
                REPLAY: if (!byte_busy) begin
                    if (replay_index==8) state<=STREAM;
                    else begin
                        byte_data<=udp_octet(replay_index);
                        byte_sop<=replay_index==0; byte_last<=0; byte_sum_last<=0;
                        sum_pending<=1; replay_index<=replay_index+4'd1;
                    end
                end
                STREAM: if (tail_fire) begin
                    byte_data<=s_tail_data; byte_sop<=0; byte_last<=s_tail_last;
                    byte_sum_last<=s_tail_last || tail_count==udp_length-16'd1;
                    if (tail_count<udp_length) sum_pending<=1;
                    else forward_pending<=1;
                    tail_count<=next_tail_count;
                    if (s_tail_sop || s_tail_error) length_bad<=1;
                    if (s_tail_last) begin
                        end_seen<=1; sn<=s_tail_data;
                        if (next_tail_count!=expected_tail) length_bad<=1;
                        state<=FINAL;
                    end
                end
                DRAIN: begin
                    if (tail_fire) begin tail_count<=next_tail_count; if (s_tail_last) begin end_seen<=1; sn<=s_tail_data; end end
                    if (terminal_seen && !byte_busy && !meta_pending) state<=FINAL;
                end
                FINAL: if (terminal_seen && !byte_busy && !meta_pending &&
                    (parser_bad || early_reason!=OK || ((fragment || udp_done) && end_forwarded))) begin
                    result_pass<=final_reason==OK; result_reason<=final_reason;
                    result_parser_code<=parser_code; result_cancel<=parser_cancel;
                    result_udp_checked<=!fragment && udp_done && !udp_zero; result_payload_length<=payload_length;
                    result_sn<=sn; result_ip_residue<=ip_residue; result_udp_residue<=udp_residue;
                    if (final_reason==OK) accepted_count<=accepted_count+32'd1;
                    else dropped_count<=dropped_count+32'd1;
                    state<=RESULT;
                end
                RESULT: if (result_ready) state<=CLEAN;
                CLEAN: begin
                    terminal_seen<=0; parser_bad<=0; parser_cancel<=0; parser_code<=0;
                    sum_pending<=0; forward_pending<=0; meta_pending<=0; state<=IDLE;
                end
                default: state<=IDLE;
            endcase
        end
    end
endmodule
