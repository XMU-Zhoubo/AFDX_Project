// C20: one checked ingress context and a separate shared eight-slot RX pool.
// Raw is the MAC client (no preamble/SFD/FCS); PHY has no backpressure.
module redundancy_rx_path #(
    parameter SLOT_COUNT=8,
    parameter SLOT_BYTES=2048,
    parameter MAX_PAYLOAD=1480,
    parameter SLOT_WIDTH=(SLOT_COUNT<=2 ? 1 : SLOT_COUNT<=4 ? 2 : SLOT_COUNT<=8 ? 3 : 4),
    parameter ALLOW_ZERO_UDP_CHECKSUM=1
) (
    input wire clk,rst_n,
    input wire [63:0] monotonic_time,
    output wire integrity_valid,input wire integrity_ready,
    output wire [12:0] integrity_index,output wire [15:0] integrity_vl,
    output wire [7:0] integrity_sn,output wire [63:0] integrity_time,
    output wire integrity_rm_enable,output wire [1:0] integrity_select,
    input wire integrity_result_valid,output wire integrity_result_ready,
    input wire integrity_pass,integrity_ic_pass,integrity_error,
    input wire [3:0] integrity_reason,
    input wire [7:0] raw_data,
    input wire raw_valid,raw_sop,raw_last,raw_error,
    output wire raw_ready,
    input wire freeze,
    output wire query_valid,
    input wire query_ready,
    output wire [15:0] query_vl,
    input wire query_result_valid,
    output wire query_result_ready,
    input wire query_found,
    input wire [255:0] query_config,
    input wire [12:0] query_index,
    input wire [15:0] query_version,
    output wire app_desc_valid,
    input wire app_desc_ready,
    output wire [15:0] app_desc_length,app_desc_vl,app_desc_app_id,app_desc_version,
    output wire [7:0] app_desc_sn,
    output wire app_desc_udp_checked,
 output wire [127:0] app_desc_fragment,
    output wire [7:0] app_data,
    output wire app_valid,app_sop,app_last,
    input wire app_ready,
    output wire [15:0] used_count,free_count,peak_count,
    output wire idle,
    output wire accepted,
    output reg rejected,resource_drop,cancelled,overlength,
    output wire released,allocated,discarded,ownership_error,
    output reg [4:0] reason,
    output wire [12:0] event_index,
    output wire [15:0] event_length,
    output wire [7:0] event_sn,
    output wire event_checked,event_known
);
    reg inflight,ingress_done,result_done,resource_drain;
    reg [1:0] cooldown;
    reg [2:0] query_state;
    reg [255:0] context_config;
    reg [12:0] context_index;
    reg [15:0] context_version;
    reg context_found,context_match;
    reg [15:0] last_event_length;
    reg [7:0] last_event_sn;
    reg last_event_checked;
    reg [15:0] observed_ip_total,observed_udp_length;
    reg [3:0] observed_udp_index;
    wire parser_ready;
    wire context_available=!inflight && cooldown==0;
    // The parser may return to SEEK before C14 has produced its final result.
    // Once this raw LAST is accepted, keep the next frame in the MAC FIFO;
    // otherwise its SOP could be consumed under the previous frame context.
    wire ingress_to_parser=!resource_drain &&
        ((inflight && !ingress_done) || (context_available && raw_sop && !freeze));
    // Empty input gaps do not create frames. Orphan residual bytes after reset
    // are discarded until a fresh SOP; freeze only gates a NEW SOP.
    assign raw_ready=rst_n && (resource_drain ? 1'b1 :
        inflight ? (!ingress_done && parser_ready) : !raw_sop ? 1'b1 :
        (context_available && !freeze && parser_ready));
    wire raw_fire=raw_valid && raw_ready;
    wire [271:0] header;
    wire fragment=header[109] || header[108:96]!=0;
    wire header_valid,header_ready;
    wire [7:0] parser_tail;
    wire parser_tail_valid,parser_tail_ready,parser_tail_sop,parser_tail_last,parser_tail_error;
    wire parser_status_valid,parser_status_ready,parser_cancel;
    wire [4:0] parser_code;
    wire check_header_ready;
    assign query_valid=rst_n && header_valid && query_state==1;
    assign query_vl=header[239:224];
    assign query_result_ready=rst_n && query_state==2;
    assign header_ready=check_header_ready && query_state==3;
    wire [63:0] candidate_meta;
    wire candidate_meta_valid,candidate_meta_ready;
    wire [7:0] candidate_data;
    wire candidate_valid,candidate_ready,candidate_sop,candidate_last;
    wire result_valid,result_ready,result_pass,result_cancel,result_checked;
    wire [4:0] result_reason;
    wire [15:0] result_length;
    wire [7:0] result_sn;
    header_parser #(.CHECK_DEST_MAC(0)) parser (
        .clk(clk),.rst_n(rst_n),.s_data(raw_data),.s_valid(raw_valid&&ingress_to_parser),.s_ready(parser_ready),
        .s_sop(raw_sop),.s_last(raw_last),.s_error(raw_error),
        .m_meta_data(header),.m_meta_valid(header_valid),.m_meta_ready(header_ready),
        .m_tail_data(parser_tail),.m_tail_valid(parser_tail_valid),.m_tail_ready(parser_tail_ready),
        .m_tail_sop(parser_tail_sop),.m_tail_last(parser_tail_last),.m_tail_error(parser_tail_error),
        .status_valid(parser_status_valid),.status_ready(parser_status_ready),.status_code(parser_code),.status_cancel(parser_cancel));
    frame_check #(.USE_CONFIG(1),.ALLOW_ZERO_UDP_CHECKSUM(ALLOW_ZERO_UDP_CHECKSUM)) checker (
        .clk(clk),.rst_n(rst_n),.cfg_found(context_match),.cfg_data(context_config),
        .s_meta_data(header),.s_meta_valid(header_valid&&query_state==3),.s_meta_ready(check_header_ready),
        .s_tail_data(parser_tail),.s_tail_valid(parser_tail_valid),.s_tail_ready(parser_tail_ready),
        .s_tail_sop(parser_tail_sop),.s_tail_last(parser_tail_last),.s_tail_error(parser_tail_error),
        .s_status_valid(parser_status_valid),.s_status_ready(parser_status_ready),.s_status_code(parser_code),.s_status_cancel(parser_cancel),
        .m_meta_data(candidate_meta),.m_meta_valid(candidate_meta_valid),.m_meta_ready(candidate_meta_ready),
        .m_tail_data(candidate_data),.m_tail_valid(candidate_valid),.m_tail_ready(candidate_ready),.m_tail_sop(candidate_sop),.m_tail_last(candidate_last),
        .result_valid(result_valid),.result_ready(result_ready),.result_pass(result_pass),.result_reason(result_reason),.result_parser_code(),
        .result_cancel(result_cancel),.result_udp_checked(result_checked),.result_payload_length(result_length),.result_sn(result_sn),
        .result_ip_residue(),.result_udp_residue(),.accepted_count(),.dropped_count());

    reg pool_context,pool_allocated,drop_for_resource,local_bad,tail_complete;
    reg [15:0] payload_length,tail_offset,stored_count,expected_tail;
    reg [7:0] captured_sn;
    wire pool_alloc_ready,pool_final_ready,pool_write_ready;
    wire [SLOT_WIDTH-1:0] pool_alloc_slot;
    wire [351:0] initial_meta={32'd0,{26'd0,1'b0,8'd0,context_version,context_index,context_config}};
    wire [351:0] final_metadata={fragment?{header[127:112],header[111:96]}:32'd0,26'd0,result_checked,result_sn,context_version,context_index,context_config};
    wire alloc_fire=candidate_meta_valid && candidate_meta_ready;
    wire in_payload=fragment?tail_offset<payload_length:(tail_offset>=16'd8 && tail_offset<payload_length+16'd8);
    assign candidate_meta_ready=rst_n && !pool_context && (drop_for_resource || pool_alloc_ready);
    assign candidate_ready=rst_n && pool_context && (!in_payload || local_bad || !pool_allocated || pool_write_ready);
    wire candidate_fire=candidate_valid && candidate_ready;
    wire local_pass=!local_bad && tail_complete && stored_count==payload_length &&
        tail_offset==expected_tail && result_length==payload_length && result_sn==captured_sn;
    wire protocol_candidate=result_pass && !result_cancel && result_reason==0 && pool_context && local_pass && context_found;
    reg sequence_requested;
    wire sequence_ready=integrity_ready;
    wire sequence_valid=integrity_result_valid,sequence_pass=integrity_pass,sequence_error=integrity_error;
    reg stamp_valid;reg [63:0] stamp;
    assign integrity_index=context_index;assign integrity_vl=context_config[239:224];
    assign integrity_sn=result_sn;assign integrity_time=stamp;
    assign integrity_rm_enable=!context_config[246];assign integrity_select=context_config[245:244];

    wire [3:0] sequence_reason;
    wire [7:0] sequence_sn;
    wire sequence_required=result_valid && protocol_candidate;
    assign integrity_valid=sequence_required && stamp_valid && !sequence_requested;
    assign integrity_result_ready=result_valid && result_ready && sequence_required;
    wire final_available=!sequence_required || sequence_valid;
    assign result_ready=rst_n && (!pool_context || !pool_allocated || pool_final_ready) && final_available;
    always @(posedge clk)begin
     if(!rst_n)begin sequence_requested<=0;stamp_valid<=0;stamp<=0;end
     else begin
      if(sequence_required && !stamp_valid)begin stamp_valid<=1;stamp<=monotonic_time;end
      if(integrity_valid && integrity_ready)sequence_requested<=1;
      if(result_valid && result_ready)begin sequence_requested<=0;stamp_valid<=0;end
     end
    end
    wire result_fire=result_valid && result_ready;
    wire final_pass=protocol_candidate && sequence_valid && sequence_pass && !sequence_error && !drop_for_resource;
    wire pool_desc_valid,pool_desc_ready;
    wire [SLOT_WIDTH-1:0] pool_desc_slot;
    wire [15:0] pool_desc_length;
    wire [351:0] pool_desc_meta;
    reg reading,read_requested;
    reg [SLOT_WIDTH-1:0] read_slot;
    reg [15:0] read_offset;
    wire pool_read_ready,pool_rsp_valid,pool_rsp_last;
    wire [7:0] pool_rsp_data;
    wire [SLOT_WIDTH-1:0] pool_rsp_slot;
    wire pool_release_ready,pool_committed,pool_discarded,pool_error,pool_alloc_reject;
    wire [3:0] pool_error_code;
    wire application_fire=app_valid && app_ready;
    wire release_request=application_fire && app_last;
    assign app_desc_valid=pool_desc_valid && !reading;
    assign pool_desc_ready=app_desc_ready && !reading;
    assign app_desc_length=pool_desc_length;
    assign app_desc_vl=pool_desc_meta[239:224];
    assign app_desc_app_id=pool_desc_meta[207:192];
    assign app_desc_version=pool_desc_meta[284:269];
    assign app_desc_sn=pool_desc_meta[292:285];
    assign app_desc_udp_checked=pool_desc_meta[293];
    assign app_desc_fragment={pool_desc_meta[351:320],pool_desc_meta[95:0]};
    assign app_data=pool_rsp_data;
    assign app_valid=pool_rsp_valid && reading;
    assign app_sop=read_offset==0;
    assign app_last=pool_rsp_last;
    assign accepted=pool_committed;
    assign discarded=pool_discarded;
    assign ownership_error=pool_error || pool_alloc_reject;
    assign event_index=context_index;
    assign event_known=context_found;
    assign event_length=last_event_length;
    assign event_sn=last_event_sn;
    assign event_checked=last_event_checked;
    assign idle=rst_n && !inflight && !resource_drain && cooldown==0 &&
        query_state==0 && !pool_context && !reading && used_count==0;
    frame_pool #(.SLOT_COUNT(SLOT_COUNT),.SLOT_BYTES(SLOT_BYTES),.MAX_PAYLOAD(MAX_PAYLOAD),.META_WIDTH(352),.SLOT_WIDTH(SLOT_WIDTH)) pool (
        .clk(clk),.rst_n(rst_n),.alloc_valid(candidate_meta_valid&&!pool_context&&!drop_for_resource),.alloc_ready(pool_alloc_ready),
        .alloc_length(candidate_meta[47:32]),.alloc_meta(initial_meta),.alloc_slot(pool_alloc_slot),
        .s_data(candidate_data),.s_valid(candidate_valid&&pool_context&&pool_allocated&&in_payload&&!local_bad),.s_ready(pool_write_ready),
        .s_last(tail_offset==(fragment?payload_length-16'd1:payload_length+16'd7)),
        .final_valid(result_valid&&pool_context&&pool_allocated&&final_available),.final_ready(pool_final_ready),.final_pass(final_pass),.final_cancel(result_cancel),.final_meta(final_metadata),
        .desc_valid(pool_desc_valid),.desc_ready(pool_desc_ready),.desc_slot(pool_desc_slot),.desc_length(pool_desc_length),.desc_meta(pool_desc_meta),
        .rd_valid(reading&&!read_requested),.rd_ready(pool_read_ready),.rd_slot(read_slot),.rd_offset(read_offset),
        .rsp_valid(pool_rsp_valid),.rsp_ready(app_ready&&reading),.rsp_data(pool_rsp_data),.rsp_last(pool_rsp_last),.rsp_slot(pool_rsp_slot),
        .release_valid(release_request),.release_ready(pool_release_ready),.release_slot(read_slot),
        .allocated(allocated),.alloc_reject(pool_alloc_reject),.committed(pool_committed),.discarded(pool_discarded),.released(released),
        .error_event(pool_error),.error_code(pool_error_code),.used_count(used_count),.free_count(free_count),.peak_count(peak_count));

    always @(posedge clk) begin
        if(!rst_n)begin
            inflight<=0;ingress_done<=0;result_done<=0;resource_drain<=0;cooldown<=0;
            query_state<=0;context_config<=0;context_index<=0;context_version<=0;context_found<=0;context_match<=0;
            pool_context<=0;pool_allocated<=0;drop_for_resource<=0;local_bad<=0;tail_complete<=0;payload_length<=0;tail_offset<=0;stored_count<=0;expected_tail<=0;captured_sn<=0;
            reading<=0;read_requested<=0;read_slot<=0;read_offset<=0;
            rejected<=0;resource_drop<=0;cancelled<=0;reason<=0;
            last_event_length<=0;last_event_sn<=0;last_event_checked<=0;
            observed_ip_total<=0;observed_udp_length<=0;observed_udp_index<=0;overlength<=0;
        end else begin
            rejected<=0;resource_drop<=0;cancelled<=0;overlength<=0;
            if(cooldown!=0)cooldown<=cooldown-1'b1;
            if(raw_fire)begin
                if(resource_drain)begin
                    if(raw_last)begin resource_drain<=0;resource_drop<=1;reason<=5'd20;end
                end else if(!inflight && raw_sop)begin
                    context_found<=0;context_match<=0;context_config<=0;context_index<=0;context_version<=0;
                    last_event_length<=0;last_event_sn<=0;last_event_checked<=0;
                    // No app slot: still validate and observe SN, but never allocate or publish.
                    drop_for_resource<=free_count==0;
                    inflight<=1;ingress_done<=raw_last;result_done<=0;
                end else if(inflight && raw_last)ingress_done<=1;
            end
            if(inflight && (ingress_done || (raw_fire&&raw_last)) && (result_done || result_fire))begin
                inflight<=0;ingress_done<=0;result_done<=0;cooldown<=2;
            end
            if(header_valid && query_state==0)query_state<=1;
            if(query_valid && query_ready)query_state<=2;
            if(query_result_valid && query_result_ready)begin
                context_config<=query_config;context_index<=query_index;context_version<=query_version;
                context_found<=query_found && query_config[240] && query_config[239:224]==header[239:224];
                context_match<=query_found && query_config[240] &&
                    query_config[239:224]==header[239:224] && query_config[143:96]==header[271:224];
                query_state<=3;
            end
            if(header_valid && header_ready)begin
                query_state<=4;observed_ip_total<=header[143:128];
                observed_udp_length<=0;observed_udp_index<=0;
            end
            if(parser_tail_valid && parser_tail_ready)begin
                if(observed_udp_index<8)observed_udp_index<=observed_udp_index+1'b1;
                if(observed_udp_index==4)observed_udp_length[15:8]<=parser_tail;
                if(observed_udp_index==5)observed_udp_length[7:0]<=parser_tail;
            end
            if(alloc_fire)begin
                pool_context<=1;pool_allocated<=!drop_for_resource;payload_length<=candidate_meta[47:32];tail_offset<=0;stored_count<=0;
                expected_tail<=fragment?(candidate_meta[47:32]<25?16'd26:candidate_meta[47:32]+16'd1):(candidate_meta[47:32]<17?16'd26:candidate_meta[47:32]+16'd9);
                local_bad<=candidate_meta[47:32]<1 || candidate_meta[47:32]>MAX_PAYLOAD;
                tail_complete<=0;captured_sn<=0;
            end
            if(candidate_fire)begin
                if(tail_offset<16'd1481)tail_offset<=tail_offset+1'b1;
                if(in_payload && !local_bad)stored_count<=stored_count+1'b1;
                if(candidate_sop!=(tail_offset==0) || tail_offset>=expected_tail ||
                    candidate_last!=(tail_offset==expected_tail-1'b1))local_bad<=1;
                if(candidate_last)begin tail_complete<=1;captured_sn<=candidate_data;end
            end
            if(result_fire)begin
                result_done<=1;query_state<=0;
                last_event_length<=fragment && header[108:96]==0 ? (result_length>=8 ? result_length-16'd8:16'd0):result_length;last_event_sn<=result_sn;last_event_checked<=result_checked;
                overlength<=result_reason==15 || (result_reason==2 && observed_ip_total>1499) ||
                    (result_reason==7 && observed_udp_length>1479);
                if(!protocol_candidate)begin
                    rejected<=1;reason<=result_reason!=0 ? result_reason : 5'd21;cancelled<=result_cancel;
                end else if(!sequence_pass || sequence_error)begin rejected<=1;reason<=integrity_reason==5?5'd25:!integrity_ic_pass?5'd22:integrity_reason==1?5'd23:5'd24;end
                else if(drop_for_resource)begin resource_drop<=1;reason<=5'd20;end
                else reason<=0;
                pool_context<=0;pool_allocated<=0;
            end
            if(app_desc_valid && app_desc_ready)begin
                reading<=1;read_requested<=0;read_slot<=pool_desc_slot;read_offset<=0;
            end
            if(reading && !read_requested && pool_read_ready)read_requested<=1;
            if(application_fire)begin
                read_requested<=0;
                if(app_last)begin reading<=0;read_offset<=0;end
                else read_offset<=read_offset+1'b1;
            end
        end
    end
endmodule
