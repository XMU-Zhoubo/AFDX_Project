// RFC 1071 one's-complement checksum.  Byte stream, network byte order.
// A command declares the byte count; s_last must mark exactly that last byte.
// The odd trailing byte is padded ONLY in arithmetic, never in the stream.
module checksum_stream #(
    parameter MAX_BYTES = 65547
) (
    input wire clk,
    input wire rst_n,
    input wire cmd_valid,
    output wire cmd_ready,
    input wire [16:0] cmd_length,
    input wire [7:0] s_data,
    input wire s_valid,
    output wire s_ready,
    input wire s_last,
    output wire [15:0] m_checksum,
    output wire m_valid,
    input wire m_ready,
    output wire m_error
);
    reg active;
    reg [16:0] remaining;
    reg [15:0] sum_reg;
    reg high_pending;
    reg [7:0] high_byte;
    reg [15:0] result_checksum;
    reg result_valid;
    reg result_error;

    wire [15:0] next_word;
    wire [16:0] extended_sum;
    wire [15:0] folded_sum;
    assign next_word = high_pending ? {high_byte, s_data} : {s_data, 8'h00};
    assign extended_sum = {1'b0, sum_reg} + {1'b0, next_word};
    // Two 16-bit operands sum to at most 1FFFE, hence this fold cannot overflow.
    assign folded_sum = extended_sum[15:0] + {15'b0, extended_sum[16]};
    assign cmd_ready = rst_n && !active && (!result_valid || m_ready);
    assign s_ready = rst_n && active;
    assign m_checksum = result_checksum;
    assign m_valid = rst_n && result_valid;
    assign m_error = result_error;

    always @(posedge clk) begin
        if (!rst_n) begin
            active <= 1'b0;
            remaining <= 17'd0;
            sum_reg <= 16'h0000;
            high_pending <= 1'b0;
            high_byte <= 8'h00;
            result_checksum <= 16'h0000;
            result_valid <= 1'b0;
            result_error <= 1'b0;
        end else begin
            if (result_valid && m_ready)
                result_valid <= 1'b0;
            if (cmd_valid && cmd_ready) begin
                sum_reg <= 16'h0000;
                high_pending <= 1'b0;
                high_byte <= 8'h00;
                remaining <= cmd_length;
                result_error <= 1'b0;
                if (cmd_length > MAX_BYTES) begin
                    active <= 1'b0;
                    result_checksum <= 16'h0000;
                    result_error <= 1'b1;
                    result_valid <= 1'b1;
                end else if (cmd_length == 0) begin
                    active <= 1'b0;
                    result_checksum <= 16'hffff;
                    result_valid <= 1'b1;
                end else begin
                    active <= 1'b1;
                end
            end
            if (s_valid && s_ready) begin
                if (s_last != (remaining == 1)) begin
                    // An early or absent LAST ends an erroneous transaction.
                    active <= 1'b0;
                    high_pending <= 1'b0;
                    result_checksum <= 16'h0000;
                    result_error <= 1'b1;
                    result_valid <= 1'b1;
                end else if (remaining == 1) begin
                    result_checksum <= ~folded_sum;
                    result_error <= 1'b0;
                    result_valid <= 1'b1;
                    active <= 1'b0;
                    high_pending <= 1'b0;
                    sum_reg <= 16'h0000;
                    remaining <= 17'd0;
                end else begin
                    remaining <= remaining - 17'd1;
                    if (high_pending) begin
                        sum_reg <= folded_sum;
                        high_pending <= 1'b0;
                    end else begin
                        high_byte <= s_data;
                        high_pending <= 1'b1;
                    end
                end
            end
        end
    end
endmodule
