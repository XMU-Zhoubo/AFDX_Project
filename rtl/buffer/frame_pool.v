`timescale 1ns/1ps
// Single fill context, queued descriptors and independently owned committed slots.
// Byte RAM is never reset. Only an accepted descriptor confers read ownership.
module frame_pool #(
    parameter SLOT_COUNT = 8,
    parameter SLOT_BYTES = 2048,
    parameter MAX_PAYLOAD = 1471,
    parameter META_WIDTH = 320,
    parameter SLOT_WIDTH = (SLOT_COUNT <= 2 ? 1 : SLOT_COUNT <= 4 ? 2 :
                            SLOT_COUNT <= 8 ? 3 : SLOT_COUNT <= 16 ? 4 :
                            SLOT_COUNT <= 32 ? 5 : SLOT_COUNT <= 64 ? 6 :
                            SLOT_COUNT <= 128 ? 7 : 8)
) (
    input wire clk, input wire rst_n,
    input wire alloc_valid, output wire alloc_ready,
    input wire [15:0] alloc_length,
    input wire [META_WIDTH-1:0] alloc_meta,
    output wire [SLOT_WIDTH-1:0] alloc_slot,
    input wire [7:0] s_data, input wire s_valid, output wire s_ready, input wire s_last,
    input wire final_valid, output wire final_ready,
    input wire final_pass, input wire final_cancel,
    input wire [META_WIDTH-1:0] final_meta,
    output wire desc_valid, input wire desc_ready,
    output wire [SLOT_WIDTH-1:0] desc_slot,
    output wire [15:0] desc_length, output wire [META_WIDTH-1:0] desc_meta,
    input wire rd_valid, output wire rd_ready,
    input wire [SLOT_WIDTH-1:0] rd_slot, input wire [15:0] rd_offset,
    output reg rsp_valid, input wire rsp_ready,
    output reg [7:0] rsp_data, output reg rsp_last,
    output reg [SLOT_WIDTH-1:0] rsp_slot,
    input wire release_valid, output wire release_ready,
    input wire [SLOT_WIDTH-1:0] release_slot,
    output reg allocated, output reg alloc_reject, output reg committed,
    output reg discarded, output reg released,
    output reg error_event, output reg [3:0] error_code,
    output reg [15:0] used_count, output wire [15:0] free_count,
    output reg [15:0] peak_count
);
    localparam FREE = 2'd0, FILL = 2'd1, QUEUED = 2'd2, OWNED = 2'd3;
    reg [1:0] state [0:SLOT_COUNT-1];
    reg [15:0] lengths [0:SLOT_COUNT-1];
    reg [META_WIDTH-1:0] metadata [0:SLOT_COUNT-1];
    reg [7:0] memory [0:SLOT_COUNT*SLOT_BYTES-1];
    reg [SLOT_WIDTH-1:0] queue [0:SLOT_COUNT-1];
    reg [SLOT_WIDTH-1:0] q_read, q_write;
    reg [15:0] q_count;
    reg filling, data_closed, fill_bad, final_seen;
    reg [SLOT_WIDTH-1:0] fill_slot;
    reg [15:0] fill_count, fill_length;
    reg [META_WIDTH-1:0] fill_meta;
    reg found_free;
    reg [SLOT_WIDTH-1:0] first_free;
    integer n;
    integer reset_index;

    wire release_blocked = rsp_valid && !rsp_ready && rsp_slot == release_slot;
    wire release_index_ok = release_slot < SLOT_COUNT;
    wire release_owned = release_index_ok && state[release_slot] == OWNED;
    assign release_ready = rst_n && !release_blocked;
    wire release_fire = release_valid && release_ready;
    wire release_good = release_fire && release_owned;
    wire legal_length = alloc_length != 0 && alloc_length <= MAX_PAYLOAD &&
                        alloc_length <= SLOT_BYTES;
    always @* begin
        found_free = 1'b0;
        first_free = {SLOT_WIDTH{1'b0}};
        for (n = 0; n < SLOT_COUNT; n = n+1) begin
            if (!found_free && state[n] == FREE) begin
                found_free = 1'b1;
                first_free = n;
            end
        end
    end
    assign alloc_ready = rst_n && !filling &&
                         (!legal_length || found_free || release_good);
    assign alloc_slot = found_free ? first_free : release_slot;
    wire alloc_fire = alloc_valid && alloc_ready;
    wire alloc_good = alloc_fire && legal_length;
    assign final_ready = rst_n && filling && (!final_seen || final_cancel || !final_pass);
    wire final_fire = final_valid && final_ready;
    wire cancel_now = final_fire && (!final_pass || final_cancel);
    assign s_ready = rst_n && filling && !data_closed && !cancel_now;
    wire input_fire = s_valid && s_ready;
    wire last_now = input_fire && s_last;
    wire byte_bad = input_fire && ((fill_count >= fill_length) ||
                    (s_last && fill_count + 16'd1 != fill_length) ||
                    (!s_last && fill_count + 16'd1 >= fill_length));
    wire closed_now = data_closed || last_now;
    wire accepted_final = final_seen || (final_fire && final_pass && !final_cancel);
    wire close_now = filling && closed_now && accepted_final;
    wire commit_now = close_now && !fill_bad && !byte_bad &&
                     ((last_now ? fill_count + 16'd1 : fill_count) == fill_length);
    wire discard_now = cancel_now || (close_now && !commit_now);
    assign desc_valid = rst_n && q_count != 0;
    assign desc_slot = queue[q_read];
    assign desc_length = lengths[queue[q_read]];
    assign desc_meta = metadata[queue[q_read]];
    wire desc_fire = desc_valid && desc_ready;
    wire read_index_ok = rd_slot < SLOT_COUNT;
    wire read_owned = read_index_ok && state[rd_slot] == OWNED;
    assign rd_ready = rst_n && (!rsp_valid || rsp_ready);
    wire rd_fire = rd_valid && rd_ready;
    wire rd_good = rd_fire && read_owned && rd_offset < lengths[rd_slot] &&
                   rd_offset < SLOT_BYTES && !(release_good && release_slot == rd_slot);
    wire [16:0] next_used = {1'b0,used_count} + (alloc_good ? 17'd1 : 17'd0) -
                           (release_good ? 17'd1 : 17'd0) -
                           (discard_now ? 17'd1 : 17'd0);
    assign free_count = SLOT_COUNT - used_count;

    // Inferred simple dual-port byte RAM, one write and one synchronous read.
    always @(posedge clk) begin
        if (rst_n && input_fire && fill_count < fill_length && fill_count < SLOT_BYTES)
            memory[fill_slot*SLOT_BYTES + fill_count] <= s_data;
        // RAM output has no reset. rsp_valid is reset separately, so stale
        // data is never observable as a transaction; this is the same
        // unreset synchronous-read template as accepted payload_buffer.
        if (rd_good)
            rsp_data <= memory[rd_slot*SLOT_BYTES + rd_offset];
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            for (reset_index = 0; reset_index < SLOT_COUNT; reset_index = reset_index+1) begin
                state[reset_index] <= FREE;
                lengths[reset_index] <= 0;
                metadata[reset_index] <= 0;
                queue[reset_index] <= 0;
            end
            filling <= 0; data_closed <= 0; fill_bad <= 0; final_seen <= 0;
            fill_slot <= 0; fill_count <= 0; fill_length <= 0; fill_meta <= 0;
            q_read <= 0; q_write <= 0; q_count <= 0;
            rsp_valid <= 0; rsp_last <= 0; rsp_slot <= 0;
            allocated <= 0; alloc_reject <= 0; committed <= 0; discarded <= 0;
            released <= 0; error_event <= 0; error_code <= 0;
            used_count <= 0; peak_count <= 0;
        end else begin
            allocated <= 0; alloc_reject <= 0; committed <= 0;
            discarded <= 0; released <= 0; error_event <= 0; error_code <= 0;
            if (rsp_valid && rsp_ready) rsp_valid <= 0;
            if (rd_fire) begin
                if (rd_good) begin
                    rsp_valid <= 1;
                    rsp_slot <= rd_slot;
                    rsp_last <= rd_offset + 16'd1 == lengths[rd_slot];
                end else begin
                    error_event <= 1; error_code <= 4'd4;
                end
            end
            if (release_fire) begin
                if (release_owned) begin
                    state[release_slot] <= FREE;
                    released <= 1;
                end else begin
                    error_event <= 1; error_code <= 4'd3;
                end
            end
            if (desc_fire) begin
                state[queue[q_read]] <= OWNED;
                q_read <= q_read == SLOT_COUNT-1 ? 0 : q_read + 1'b1;
            end
            if (input_fire) begin
                if (fill_count != 16'hffff) fill_count <= fill_count + 16'd1;
                if (byte_bad) fill_bad <= 1;
                if (s_last) data_closed <= 1;
            end
            if (final_fire) begin
                final_seen <= 1;
                fill_meta <= final_meta;
            end
            if (commit_now) begin
                filling <= 0;
                state[fill_slot] <= QUEUED;
                lengths[fill_slot] <= fill_length;
                metadata[fill_slot] <= final_fire ? final_meta : fill_meta;
                queue[q_write] <= fill_slot;
                q_write <= q_write == SLOT_COUNT-1 ? 0 : q_write + 1'b1;
                committed <= 1;
            end
            if (discard_now) begin
                filling <= 0;
                state[fill_slot] <= FREE;
                discarded <= 1;
                if (!cancel_now) begin error_event <= 1; error_code <= 4'd2; end
            end
            case ({commit_now,desc_fire})
                2'b10: q_count <= q_count + 16'd1;
                2'b01: q_count <= q_count - 16'd1;
                default: q_count <= q_count;
            endcase
            if (alloc_fire) begin
                if (legal_length) begin
                    state[alloc_slot] <= FILL;
                    filling <= 1;
                    fill_slot <= alloc_slot;
                    fill_length <= alloc_length;
                    fill_count <= 0; data_closed <= 0; fill_bad <= 0; final_seen <= 0;
                    fill_meta <= alloc_meta;
                    allocated <= 1;
                end else begin
                    alloc_reject <= 1; error_event <= 1; error_code <= 4'd1;
                end
            end
            used_count <= next_used[15:0];
            if (next_used > {1'b0,peak_count}) peak_count <= next_used[15:0];
        end
    end
endmodule
