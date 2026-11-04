// C20: eight shared payload slots, one fill transaction, independently owned
// committed candidates, and one genuine C09/C11 packetizer. No MAC or BAG here.
module sequence_tx_path #(parameter TX_ENTRIES=128) (
    input wire clk,rst_n,freeze,
 input wire message_seed_valid,input wire [15:0] message_seed,output wire message_seed_ready,
    output wire seq_init,
    input wire seq_q_valid,output wire seq_q_ready,input wire [12:0] seq_q_index,
    output wire seq_q_result_valid,input wire seq_q_result_ready,
    output wire seq_q_error,output wire [31:0] seq_q_data,
    output wire [191:0] seq_counts,
    input wire app_cmd_valid,
    output wire app_cmd_ready,
    input wire [12:0] app_cmd_index,
    input wire [15:0] app_cmd_length,
    input wire [7:0] app_data,
    input wire app_valid,
    output wire app_ready,
    input wire app_last,
    input wire commit_valid,
    output wire commit_ready,
    input wire abort,
    output reg error_valid,
    input wire error_ready,
    output reg [3:0] error_code,
    output wire query_valid,
    input wire query_ready,
    output wire [12:0] query_index,
    input wire query_result_valid,
    output wire query_result_ready,
    input wire query_found,
    input wire [255:0] query_config,
    input wire [12:0] query_result_index,
    input wire [15:0] query_version,
    input wire [2:0] cand_index,
    output wire cand_valid,
    output wire [255:0] cand_config,
    output wire [12:0] cand_index_out,
    output wire [15:0] cand_version,cand_length,
    input wire grant_valid,
    input wire [2:0] grant_slot,
    output wire grant_ready,
    output wire [7:0] m_data,
    output wire m_valid,
    input wire m_ready,
    output wire m_sop,m_last,m_error,
    output wire submitted,released,allocated,discarded,ownership_error,
    output wire [15:0] used_count,free_count,peak_count,
    output wire idle,busy,setup_busy,
    output reg [12:0] current_index,
    output reg [255:0] current_config,
    output wire [15:0] current_payload_length,
    output reg [15:0] current_length,
    output reg [31:0] candidate_epoch,
    output reg [7:0] pending_mask
);
    localparam C_IDLE=0,C_QUERY=1,C_WAIT_QUERY=2,C_ALLOC=3,C_FILL=4,C_FINAL=5;
    localparam L_START=6,L_FEED=7,L_WAIT=8,L_FILL=9,L_FINAL=10;
 reg [3:0] command_state;
    reg [12:0] command_index;
    reg [15:0] command_length;
    reg [351:0] fill_meta;
    reg fill_closed,query_cancelled;
    reg [15:0] fill_count;
 wire pool_alloc_ready,pool_s_ready,pool_committed;
 wire long_idle,long_start_ready,long_ready,long_commit_ready,long_valid,long_last,long_offer,long_error;
 wire [7:0] long_data;wire [15:0] long_length,long_id,long_flags;
 wire lf=command_state==L_FILL;
 wire filling=command_state==C_FILL || lf;
 wire [7:0] fill_data=lf?long_data:app_data;
 wire fill_valid=lf?long_valid:app_valid;
 wire fill_last=lf?long_last:app_last;
 message_tx message_source(.clk(clk),.rst_n(rst_n),.abort(abort),.seed_valid(message_seed_valid),.seed(message_seed),.seed_ready(message_seed_ready),
  .start_valid(command_state==L_START),.start_ready(long_start_ready),.length(command_length),.endpoints(fill_meta[95:0]),
  .s_data(app_data),.s_valid(command_state==L_FEED && app_valid),.s_last(app_last),.s_ready(long_ready),
  .commit_valid(command_state==L_FEED && commit_valid),.commit_ready(long_commit_ready),
  .fragment_valid(long_offer),.fragment_ready(command_state==L_WAIT && long_offer && pool_alloc_ready),
  .fragment_length(long_length),.fragment_id(long_id),.fragment_flags(long_flags),
  .m_data(long_data),.m_valid(long_valid),.m_last(long_last),.m_ready(lf && pool_s_ready),
  .fragment_committed(command_state==L_FINAL && pool_committed),.idle(long_idle),.error_event(long_error),
  .accepted_count(),.completed_count(),.cancel_count());
    reg [351:0] contexts[0:7];
    reg [15:0] candidate_lengths[0:7];
    // Relative ownership order, not a wrapping sequence counter. A reused
    // slot records older pending slots of the SAME VL. Other VLs remain RR.
    reg [7:0] older_same_vl[0:7];
    reg [7:0] new_older;
    integer order_slot;
    reg owner,owner_started,cancel_worker;reg current_fragment;reg [15:0] current_id,current_flags;
    reg [2:0] owner_slot;
    assign current_payload_length=current_fragment && current_flags[12:0]!=0 ? current_length+16'd8:current_length;
    integer reset_slot;
    wire pool_final_ready,pool_desc_valid;
    wire [2:0] pool_alloc_slot,pool_desc_slot;
    wire [15:0] pool_desc_length;
    wire [351:0] pool_desc_meta;
    wire pool_alloc_reject,pool_error;
    wire [3:0] pool_error_code;
    wire pool_rd_ready,pool_rsp_valid,pool_rsp_last;
    wire [7:0] pool_rsp_data;
    wire [2:0] pool_rsp_slot;
    wire pool_release_ready;
    wire packet_desc_ready,packet_read_valid,packet_payload_ready,packet_release_valid;
    wire packet_error_valid,packet_cancel;
    wire [2:0] packet_error_code;
    wire packet_busy;
    wire release_fire;
    reg sequence_assigned,sequence_consumed;
    reg [7:0] sequence_sn;
    wire sequence_request_ready,sequence_result_valid,sequence_result_pass,sequence_result_error,sequence_finish_ready;
    wire [3:0] sequence_reason;
    wire [7:0] sequence_result_sn;
    sequence_core #(.ENTRY_COUNT(TX_ENTRIES),.TX_MODE(1)) sequencer(
     .clk(clk),.rst_n(rst_n),.init_done(seq_init),
     .s_valid(owner && !sequence_assigned),.s_ready(sequence_request_ready),
     .s_index(current_index),.s_vl(current_config[239:224]),.s_sn(8'd0),.s_invalidate(1'b0),.s_enable(1'b1),
     .result_valid(sequence_result_valid),.result_ready(owner && !sequence_assigned),
     .result_pass(sequence_result_pass),.result_error(sequence_result_error),.result_reason(sequence_reason),.result_sn(sequence_result_sn),
     .commit_valid(submitted),.cancel_valid(release_fire && !sequence_consumed && !submitted),.finish_ready(sequence_finish_ready),
     .q_valid(seq_q_valid),.q_ready(seq_q_ready),.q_index(seq_q_index),.q_result_valid(seq_q_result_valid),.q_result_ready(seq_q_result_ready),.q_error(seq_q_error),.q_data(seq_q_data),
     .checked_count(seq_counts[31:0]),.accepted_count(seq_counts[63:32]),.rejected_count(seq_counts[95:64]),
     .zero_count(seq_counts[127:96]),.gap_count(seq_counts[159:128]),.cancel_count(seq_counts[191:160]),.idle());
    reg read_active,read_inflight;
    reg [15:0] read_next,response_offset;
    wire read_command_ready=owner && !read_active && !read_inflight && !pool_rsp_valid;
    wire pool_read_valid=owner && read_active && !read_inflight && !pool_rsp_valid && !cancel_worker;
    wire pool_rsp_ready=cancel_worker || (owner && read_active && packet_payload_ready);
    wire pool_desc_ready=rst_n && !pending_mask[pool_desc_slot] && !(owner && owner_slot==pool_desc_slot);
    wire desc_fire=pool_desc_valid && pool_desc_ready;
    wire grant_fire=grant_valid && grant_ready;
    wire pool_release_valid=owner && (packet_release_valid || cancel_worker) && !read_active && !read_inflight && !pool_rsp_valid;
    assign release_fire=pool_release_valid && pool_release_ready;
    wire pool_final_valid=(command_state==C_FILL && (abort || (commit_valid && fill_closed))) || (lf && fill_closed);
    wire pool_final_cancel=command_state==C_FILL && abort;
    always @* begin
      new_older=0;
      for(order_slot=0;order_slot<8;order_slot=order_slot+1)
        if(pending_mask[order_slot] && contexts[order_slot][239:224]==pool_desc_meta[239:224])
          new_older[order_slot]=1;
      if(grant_fire)new_older[grant_slot]=0;
    end
    assign app_cmd_ready=rst_n && !freeze && command_state==C_IDLE && !error_valid;
    assign query_valid=rst_n && command_state==C_QUERY && !abort;
    assign query_index=command_index;
    assign query_result_ready=rst_n && command_state==C_WAIT_QUERY;
    assign app_ready=rst_n && !abort && ((command_state==C_FILL && pool_s_ready) || (command_state==L_FEED && long_ready));
    assign commit_ready=rst_n && !abort && ((command_state==C_FILL && fill_closed && pool_final_ready) || (command_state==L_FEED && long_commit_ready));
    assign setup_busy=command_state!=C_IDLE;
    assign busy=owner;
    assign idle=rst_n && command_state==C_IDLE && used_count==0 && !owner && pending_mask==0;
    assign cand_valid=rst_n && pending_mask[cand_index] && !(|(older_same_vl[cand_index]&pending_mask));
    assign cand_config=contexts[cand_index][255:0];
    assign cand_index_out=contexts[cand_index][268:256];
    assign cand_version=contexts[cand_index][284:269];
    assign cand_length=contexts[cand_index][335:320]!=0?candidate_lengths[cand_index]-8:candidate_lengths[cand_index];
    assign grant_ready=rst_n && !owner && packet_desc_ready && pending_mask[grant_slot] && !(|(older_same_vl[grant_slot]&pending_mask));
    assign ownership_error=(pool_error && (pool_error_code==3 || pool_error_code==4)) ||
         (pool_desc_valid && !pool_desc_ready) ||
         (pool_rsp_valid && owner && pool_rsp_slot!=owner_slot);

    frame_pool #(.SLOT_COUNT(8),.SLOT_BYTES(2048),.MAX_PAYLOAD(1480),.META_WIDTH(352)) pool(
      .clk(clk),.rst_n(rst_n),
      .alloc_valid((command_state==C_ALLOC && !abort) || (command_state==L_WAIT && long_offer)),.alloc_ready(pool_alloc_ready),
      .alloc_length(command_state==L_WAIT?long_length:command_length),.alloc_meta(command_state==L_WAIT?{long_id,long_flags,fill_meta[319:0]}:fill_meta),.alloc_slot(pool_alloc_slot),
      .s_data(fill_data),.s_valid(filling && fill_valid && (!abort || lf)),.s_ready(pool_s_ready),.s_last(fill_last),
      .final_valid(pool_final_valid),.final_ready(pool_final_ready),.final_pass(!pool_final_cancel),.final_cancel(pool_final_cancel),.final_meta(fill_meta),
      .desc_valid(pool_desc_valid),.desc_ready(pool_desc_ready),.desc_slot(pool_desc_slot),.desc_length(pool_desc_length),.desc_meta(pool_desc_meta),
      .rd_valid(pool_read_valid),.rd_ready(pool_rd_ready),.rd_slot(owner_slot),.rd_offset(read_next),
      .rsp_valid(pool_rsp_valid),.rsp_ready(pool_rsp_ready),.rsp_data(pool_rsp_data),.rsp_last(pool_rsp_last),.rsp_slot(pool_rsp_slot),
      .release_valid(pool_release_valid),.release_ready(pool_release_ready),.release_slot(owner_slot),
      .allocated(allocated),.alloc_reject(pool_alloc_reject),.committed(pool_committed),.discarded(discarded),.released(released),
      .error_event(pool_error),.error_code(pool_error_code),.used_count(used_count),.free_count(free_count),.peak_count(peak_count));
    sequence_packetizer #(.CHECK_FIXED_VL(0)) encapsulator(
      .clk(clk),.rst_n(rst_n),.abort(cancel_worker),
      .desc_valid(owner && !owner_started && sequence_assigned),.desc_ready(packet_desc_ready),.desc_sn(sequence_sn),.desc_fragment(current_fragment),.desc_ip_id(current_id),.desc_ip_flags(current_flags),
      .desc_buffer_id(1'b0),.desc_start_addr(11'd0),.desc_length(current_fragment?current_length+16'd8:current_length),.desc_vl(current_config[239:224]),
      .desc_src_mac(current_config[191:144]),.desc_dst_mac(current_config[143:96]),
      .desc_src_ip(current_config[95:64]),.desc_dst_ip(current_config[63:32]),
      .desc_src_port(current_config[31:16]),.desc_dst_port(current_config[15:0]),
      .read_valid(packet_read_valid),.read_ready(read_command_ready),
      .payload_data(pool_rsp_data),.payload_valid(pool_rsp_valid && read_active && !cancel_worker),
      .payload_ready(packet_payload_ready),.payload_last(pool_rsp_last),.payload_addr(response_offset[10:0]),
      .release_valid(packet_release_valid),.release_ready(pool_release_ready && !read_active && !read_inflight && !pool_rsp_valid),
      .m_data(m_data),.m_valid(m_valid),.m_ready(m_ready),.m_sop(m_sop),.m_last(m_last),.m_error(m_error),
      .busy(packet_busy),.frame_submitted(submitted),.ipv4_checksum(),.udp_checksum(),.ipv4_done(),.udp_done(),
      .error_valid(packet_error_valid),.error_ready(1'b1),.error_code(packet_error_code),.cancel_task(packet_cancel));

    always @(posedge clk)begin
     if(!rst_n)begin sequence_assigned<=0;sequence_consumed<=0;sequence_sn<=0;end
     else begin
      if(grant_fire)begin sequence_assigned<=0;sequence_consumed<=0;end
      if(sequence_result_valid && owner && !sequence_assigned)begin sequence_assigned<=1;sequence_sn<=sequence_result_sn;end
      if(submitted)sequence_consumed<=1;
      if(release_fire)sequence_assigned<=0;
     end
    end
    always @(posedge clk)begin
      if(!rst_n)begin
        command_state<=C_IDLE;command_index<=0;command_length<=0;fill_meta<=0;
        fill_closed<=0;fill_count<=0;query_cancelled<=0;error_valid<=0;error_code<=0;
      end else begin
        if(error_valid && error_ready)error_valid<=0;
        if(pool_error)begin error_valid<=1;error_code<=pool_error_code==2?4'd4:4'd7;end
        if(packet_error_valid)begin error_valid<=1;error_code<=6;end
        case(command_state)
          C_IDLE:if(app_cmd_valid && app_cmd_ready)begin
            command_index<=app_cmd_index;command_length<=app_cmd_length;query_cancelled<=0;
            if(app_cmd_length==0 || app_cmd_length>4096 || app_cmd_index>=TX_ENTRIES)begin error_valid<=1;error_code<=1;end
            else command_state<=C_QUERY;
          end
          C_QUERY:begin
            if(abort)begin command_state<=C_IDLE;error_valid<=1;error_code<=5;end
            else if(query_ready)command_state<=C_WAIT_QUERY;
          end
          C_WAIT_QUERY:begin
            if(abort)query_cancelled<=1;
            if(query_result_valid)begin
              if(abort || query_cancelled)begin command_state<=C_IDLE;error_valid<=1;error_code<=5;end
              else if(!query_found || !query_config[240] || query_result_index!=command_index)begin
                command_state<=C_IDLE;error_valid<=1;error_code<=2;
              end else if(query_config[223:208]<64 || query_config[223:208]>1518 ||
                           (command_length<=1471?command_length>query_config[223:208]-16'd47:query_config[223:208]!=1518))begin
                command_state<=C_IDLE;error_valid<=1;error_code<=3;
              end else begin
                fill_meta<=0;fill_meta[255:0]<=query_config;fill_meta[268:256]<=command_index;
                fill_meta[284:269]<=query_version;command_state<=command_length>1471?L_START:C_ALLOC;
              end
            end
          end
          C_ALLOC:begin
            if(abort)begin command_state<=C_IDLE;error_valid<=1;error_code<=5;end
            else if(pool_alloc_ready)begin command_state<=C_FILL;fill_closed<=0;fill_count<=0;end
          end
          C_FILL:begin
            if(app_valid && app_ready)begin fill_count<=fill_count+1;if(app_last)fill_closed<=1;end
            if(pool_final_valid && pool_final_ready)command_state<=C_FINAL;
          end
          C_FINAL:if(pool_committed || discarded)command_state<=C_IDLE;
          L_START:if(abort)command_state<=C_IDLE;else if(long_start_ready)command_state<=L_FEED;else begin command_state<=C_IDLE;error_valid<=1;error_code<=11;end
          L_FEED:begin
           if(abort || long_error)begin command_state<=C_IDLE;if(long_error)begin error_valid<=1;error_code<=4;end end
           else if(commit_valid && long_commit_ready)command_state<=L_WAIT;
          end
          L_WAIT:begin
           fill_meta[351:320]<={long_id,long_flags};
           if(long_idle)command_state<=C_IDLE;
           else if(long_offer && pool_alloc_ready)begin command_state<=L_FILL;fill_closed<=0;fill_count<=0;end
          end
          L_FILL:begin
           if(long_valid && pool_s_ready)begin fill_count<=fill_count+1;if(long_last)fill_closed<=1;end
           if(fill_closed && pool_final_ready)command_state<=L_FINAL;
          end
          L_FINAL:if(pool_committed || discarded)command_state<=L_WAIT;
          default:command_state<=C_IDLE;
        endcase
      end
    end
    always @(posedge clk)begin
      if(!rst_n)begin
        owner<=0;owner_slot<=0;owner_started<=0;cancel_worker<=0;
        current_index<=0;current_config<=0;current_length<=0;current_fragment<=0;current_id<=0;current_flags<=0;
        pending_mask<=0;candidate_epoch<=0;
        read_active<=0;read_inflight<=0;read_next<=0;response_offset<=0;
        for(reset_slot=0;reset_slot<8;reset_slot=reset_slot+1)begin contexts[reset_slot]<=0;candidate_lengths[reset_slot]<=0;older_same_vl[reset_slot]<=0;end
      end else begin
        case({desc_fire,grant_fire})
          2'b01,2'b10:candidate_epoch<=candidate_epoch+1;
          2'b11:candidate_epoch<=candidate_epoch+2;
          default:begin end
        endcase
        if(desc_fire)begin
          contexts[pool_desc_slot]<=pool_desc_meta;candidate_lengths[pool_desc_slot]<=pool_desc_length;
          pending_mask[pool_desc_slot]<=1;older_same_vl[pool_desc_slot]<=new_older;
        end
        if(grant_fire)begin
          owner<=1;owner_slot<=grant_slot;owner_started<=0;cancel_worker<=0;
          current_index<=contexts[grant_slot][268:256];current_config<=contexts[grant_slot][255:0];
          current_fragment<=contexts[grant_slot][335:320]!=0;current_id<=contexts[grant_slot][351:336];current_flags<=contexts[grant_slot][335:320];
          current_length<=contexts[grant_slot][335:320]!=0?candidate_lengths[grant_slot]-8:candidate_lengths[grant_slot];pending_mask[grant_slot]<=0;
          for(reset_slot=0;reset_slot<8;reset_slot=reset_slot+1)
            if(!desc_fire || reset_slot!=pool_desc_slot)older_same_vl[reset_slot][grant_slot]<=0;
        end
        if(owner && !owner_started && sequence_assigned && packet_desc_ready)owner_started<=1;
        if(packet_error_valid)begin cancel_worker<=1;read_active<=0;read_inflight<=0;end
        if(release_fire)begin owner<=0;owner_started<=0;cancel_worker<=0;end
        if(packet_read_valid && read_command_ready)begin read_active<=1;read_next<=0;response_offset<=0;end
        if(pool_read_valid && pool_rd_ready)begin read_inflight<=1;read_next<=read_next+1;end
        if(pool_rsp_valid && pool_rsp_ready)begin
          read_inflight<=0;response_offset<=response_offset+1;
          if(pool_rsp_last)read_active<=0;
        end
      end
    end
endmodule
