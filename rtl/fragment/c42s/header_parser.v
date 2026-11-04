// C13: one fixed Ethernet-II / IPv4 header, followed by an unverified tail.
// meta_data = {Ethernet header[111:0], IPv4 header[159:0]}, wire byte order.
// All ports are in clk; status is a held per-frame result, NOT application commit.
module header_parser #(
    parameter [47:0] DEST_MAC = 48'h030000000001,
    parameter CHECK_DEST_MAC = 1,
    parameter REQUIRE_DF = 0
) (
    input wire clk, rst_n,
    input wire [7:0] s_data,
    input wire s_valid, s_sop, s_last, s_error,
    output wire s_ready,
    output wire [271:0] m_meta_data,
    output wire m_meta_valid,
    input wire m_meta_ready,
    output wire [7:0] m_tail_data,
    output wire m_tail_valid, m_tail_sop, m_tail_last, m_tail_error,
    input wire m_tail_ready,
    output wire status_valid,
    input wire status_ready,
    output reg [4:0] status_code,
    output reg status_cancel
);
    localparam SEEK = 3'd0, HEADER = 3'd1, META = 3'd2,
               TAIL = 3'd3, FINISH = 3'd4, DRAIN = 3'd5;
    localparam OK = 5'd0, STREAM_ERROR = 5'd1, ETH_TRUNC = 5'd2,
               IP_TRUNC = 5'd3, DEST_ERROR = 5'd4, TYPE_ERROR = 5'd5,
               VERSION_ERROR = 5'd6, IHL_SHORT = 5'd7, OPTIONS = 5'd8,
               FRAGMENT = 5'd9, DF_POLICY = 5'd10, RESERVED = 5'd11,
               BOUNDARY = 5'd12, NO_TAIL = 5'd13, UNFRAMED = 5'd14;
    reg [2:0] state;
    reg [5:0] header_index;
    reg [111:0] eth_header;
    reg [159:0] ip_header;
    reg meta_valid, tail_valid, event_valid;
    reg [7:0] tail_data;
    reg tail_sop, tail_last, first_tail, candidate, orphan_reported;
    wire [111:0] next_eth = {eth_header[103:0], s_data};
    wire [159:0] next_ip = {ip_header[151:0], s_data};
    reg [4:0] reject_code;

    assign m_meta_data = {eth_header, ip_header};
    assign m_meta_valid = rst_n && meta_valid;
    assign m_tail_data = tail_data;
    assign m_tail_valid = rst_n && tail_valid;
    assign m_tail_sop = tail_sop;
    assign m_tail_last = tail_last;
    assign m_tail_error = 1'b0; // errors use status; erroneous bytes are suppressed
    assign status_valid = rst_n && event_valid;
    assign s_ready = rst_n && !event_valid &&
        ((state == SEEK) || (state == HEADER) || (state == DRAIN) ||
         ((state == TAIL) && (!tail_valid || m_tail_ready)));

    // Priority is explicit. Length/checksum/ports are deliberately left to C14.
    always @* begin
        reject_code = OK;
        if (s_error) reject_code = STREAM_ERROR;
        else if (s_sop) reject_code = BOUNDARY;
        else if (s_last && header_index < 6'd13) reject_code = ETH_TRUNC;
        else if (CHECK_DEST_MAC && header_index == 6'd13 && next_eth[111:64] != DEST_MAC) reject_code = DEST_ERROR;
        else if (header_index == 6'd13 && next_eth[15:0] != 16'h0800) reject_code = TYPE_ERROR;
        else if (s_last && header_index < 6'd33) reject_code = IP_TRUNC;
        else if (header_index == 6'd33) begin
            if (next_ip[159:156] != 4'd4) reject_code = VERSION_ERROR;
            else if (next_ip[155:152] < 4'd5) reject_code = IHL_SHORT;
            else if (next_ip[155:152] > 4'd5) reject_code = OPTIONS;
            else if (next_ip[110] && (next_ip[109] || next_ip[108:96]!=0)) reject_code = FRAGMENT;
            else if (next_ip[111]) reject_code = RESERVED;
            else if (REQUIRE_DF && !next_ip[110]) reject_code = DF_POLICY;
            else if (s_last) reject_code = NO_TAIL;
        end
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            state <= SEEK; header_index <= 6'd0;
            eth_header <= 112'd0; ip_header <= 160'd0;
            meta_valid <= 1'b0; tail_valid <= 1'b0; event_valid <= 1'b0;
            tail_data <= 8'd0; tail_sop <= 1'b0; tail_last <= 1'b0;
            first_tail <= 1'b1; candidate <= 1'b0; orphan_reported <= 1'b0;
            status_code <= OK; status_cancel <= 1'b0;
        end else begin
            if (event_valid && status_ready) event_valid <= 1'b0;
            if (tail_valid && m_tail_ready) begin
                tail_valid <= 1'b0;
                if (state == FINISH && tail_last) begin
                    event_valid <= 1'b1; status_code <= OK; status_cancel <= 1'b0;
                    state <= SEEK; candidate <= 1'b0;
                end
            end
            if (meta_valid && m_meta_ready) begin
                meta_valid <= 1'b0; candidate <= 1'b1;
                first_tail <= 1'b1; state <= TAIL;
            end
            if (s_valid && s_ready) begin
                case (state)
                    SEEK: begin
                        if (s_sop) begin
                            orphan_reported <= 1'b0;
                            candidate <= 1'b0;
                            eth_header <= {104'd0, s_data}; ip_header <= 160'd0;
                            header_index <= 6'd1;
                            if (s_error || s_last) begin
                                event_valid <= 1'b1;
                                status_code <= s_error ? STREAM_ERROR : ETH_TRUNC;
                                status_cancel <= 1'b0; state <= s_last ? SEEK : DRAIN;
                            end else state <= HEADER;
                        end else begin
                            // After reset, residual bytes cannot become a new header.
                            if (!orphan_reported) begin
                                event_valid <= 1'b1; status_code <= UNFRAMED; status_cancel <= 1'b0;
                            end
                            orphan_reported <= !s_last;
                        end
                    end
                    HEADER: begin
                        if (header_index < 6'd14) eth_header <= next_eth;
                        else ip_header <= next_ip;
                        if (reject_code != OK) begin
                            event_valid <= 1'b1; status_code <= reject_code; status_cancel <= 1'b0;
                            state <= s_last ? SEEK : DRAIN;
                        end else if (header_index == 6'd33) begin
                            meta_valid <= 1'b1; state <= META;
                        end else header_index <= header_index + 6'd1;
                    end
                    TAIL: begin
                        if (s_error || s_sop) begin
                            // Ready required space: an older held byte is accepted before cancellation.
                            event_valid <= 1'b1;
                            status_code <= s_error ? STREAM_ERROR : BOUNDARY;
                            status_cancel <= candidate; state <= s_last ? SEEK : DRAIN;
                            candidate <= 1'b0;
                        end else begin
                            tail_data <= s_data; tail_sop <= first_tail; tail_last <= s_last;
                            tail_valid <= 1'b1; first_tail <= 1'b0;
                            if (s_last) state <= FINISH;
                        end
                    end
                    DRAIN: if (s_last) state <= SEEK;
                    default: state <= state;
                endcase
            end
        end
    end
endmodule
