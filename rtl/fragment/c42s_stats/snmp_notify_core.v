// C20 integration boundary: 128 TX / 4096 RX configurations, bounded shared
// pools and TWO actual full-duplex GMII MACs. Not the final AFDX_top pinout.
module snmp_notify_core (
 output wire [1:0] trap_fault_events,output wire [31:0] trap_fault_total,output wire [15:0] trap_used,output wire trap_line_complete,
 input wire budget_valid,input wire [15:0] budget_max,input wire [2:0] budget_period,
 input wire [31:0] budget_line,budget_service,
 output wire [15:0] budget_version,
 input wire clk,rst_n,gtx_clk,phy_a_rx_clk,
 input wire [7:0] phy_a_rxd,input wire phy_a_rx_dv,phy_a_rx_er,
 output wire phy_a_tx_clk,output wire [7:0] phy_a_txd,output wire phy_a_tx_en,phy_a_tx_er,
 // One management bus reuses address/data lines for config, state and stats.
 input wire phy_b_rx_clk,input wire [7:0] phy_b_rxd,input wire phy_b_rx_dv,phy_b_rx_er,
 output wire phy_b_tx_clk,output wire [7:0] phy_b_txd,output wire phy_b_tx_en,phy_b_tx_er,
 output wire app_rx_network,
 input wire cfg_valid,cfg_write,input wire [1:0] cfg_kind,
 input wire cfg_bank,cfg_shadow,input wire [12:0] cfg_index,
 input wire [3:0] cfg_word,input wire [31:0] cfg_data,
 output wire cfg_ready,output reg cfg_resp_valid,input wire cfg_resp_ready,
 output reg cfg_resp_error,output reg [31:0] cfg_resp_data,
 input wire cfg_commit_valid,output wire cfg_commit_ready,cfg_pending,cfg_applied,
 output wire cfg_result_valid,cfg_result_ok,input wire cfg_result_ready,
 output wire [2:0] cfg_result_code,
 output wire init_done,
 input wire final_app_frame,final_app_byte,
 input wire message_seed_valid,input wire [15:0] message_seed,output wire message_seed_ready,
 input wire app_tx_cmd_valid,output wire app_tx_cmd_ready,
 input wire [12:0] app_tx_cmd_index,input wire [15:0] app_tx_cmd_length,
 input wire [7:0] app_tx_data,input wire app_tx_valid,app_tx_last,
 output wire app_tx_ready,input wire app_tx_commit_valid,app_tx_abort,
 output wire app_tx_commit_ready,app_tx_error_valid,input wire app_tx_error_ready,
 output wire [3:0] app_tx_error_code,
 output wire app_rx_desc_valid,input wire app_rx_desc_ready,
 output wire [15:0] app_rx_desc_length,app_rx_desc_vl,app_rx_desc_app_id,app_rx_desc_version,
 output wire [7:0] app_rx_desc_sn,output wire app_rx_desc_udp_checked,
 output wire [127:0] app_rx_fragment,
 output wire [7:0] app_rx_data,output wire app_rx_valid,app_rx_sop,app_rx_last,
 input wire app_rx_ready,
 input wire mgmt_cmd_valid,input wire [15:0] mgmt_cmd_length,output wire mgmt_cmd_ready,
 input wire [7:0] mgmt_data,input wire mgmt_valid,mgmt_last,mgmt_commit_valid,mgmt_abort,
 output wire mgmt_ready,mgmt_commit_ready,mgmt_error_valid,input wire mgmt_error_ready,
 output wire [2:0] mgmt_error_code,
 output wire [7:0] events,output wire line_management,
 input wire [1:0] management_select,output wire [15:0] management_max,
 output wire [15:0] management_rx_data,output wire [1:0] management_rx_valid,management_rx_sop,management_rx_last,management_rx_error,
 input wire [1:0] management_rx_ready
);
 // C23 read-only kind3 words8..15: reading8 snapshots one coherent record.
 // No writable time/decision controls, no change to IC/RM or pool behavior.
 reg [31:0] obs_sequence,obs_meta;
 reg [63:0] obs_candidate,obs_decision;
 reg [15:0] obs_vl;
 reg [4:0] obs_drop_a,obs_drop_b;
 reg [1:0] obs_drop_valid;
 reg [255:0] obs_snapshot;
 wire [255:0] obs_live={16'd0,obs_vl,20'd0,obs_drop_valid,obs_drop_b,obs_drop_a,
   obs_meta,obs_decision[63:32],obs_decision[31:0],obs_candidate[63:32],obs_candidate[31:0],obs_sequence};
 wire [63:0] extended_time;
 wire [15:0] cfg_version;assign budget_version=cfg_version;
 wire rx_a_idle,rx_b_idle;wire [1:0] rx_idles;
 assign rx_a_idle=rx_idles[0];assign rx_b_idle=rx_idles[1];
 wire [1:0] iq_valid,iq_ready,ir_valid,ir_ready,ir_pass,ir_ic,ir_error;
 wire [12:0] iq_index[0:1];wire [15:0] iq_vl[0:1];wire [7:0] iq_sn[0:1];
 wire [63:0] iq_time[0:1];wire [1:0] iq_select[0:1];wire [1:0] iq_enable;
 wire [3:0] ir_reason;
 wire [127:0] rm_record;wire [191:0] rm_counts;
 wire rm_request_ready,rm_result_valid,rm_result_pass,rm_ic_pass,rm_result_error,rm_expired;
 wire rm_busy,rm_owner,rm_request;wire [103:0] merged_candidate;
 assign ir_valid[0]=rm_busy && !rm_owner && rm_result_valid;
 assign ir_valid[1]=rm_busy && rm_owner && rm_result_valid;
 assign ir_pass={2{rm_result_pass}};assign ir_ic={2{rm_ic_pass}};assign ir_error={2{rm_result_error}};
 wire rm_take=rm_busy && ir_ready[rm_owner];
 wire [1:0] rx_accepted,rx_rejected,rx_resources,rx_cancels,rx_discards,rx_releases,rx_allocs,rx_errors,rx_knowns,rx_checkeds,rx_overs;
 wire [12:0] rx_indices[0:1];wire [15:0] rx_lengths[0:1];wire [7:0] rx_sns[0:1];wire [4:0] rx_reasons[0:1];
 wire [15:0] rx_useds[0:1],rx_frees[0:1],rx_peaks[0:1];
 wire [7:0] rx_raw_datas[0:1];wire [1:0] rx_raw_valids,rx_raw_readys,rx_raw_sops,rx_raw_lasts,rx_raw_errors;
 wire [1:0] rx_queries,rx_query_readys,rx_query_takes;wire [15:0] rx_query_vls[0:1];
 wire [1:0] app_desc_valids,app_desc_readys,app_valids,app_readys,app_sops,app_lasts,app_checkeds;
 wire [127:0] app_fragments[0:1];
 wire [15:0] app_lengths[0:1],app_vls[0:1],app_ids[0:1],app_versions[0:1];wire [7:0] app_sns[0:1],app_datas[0:1];
 reg query_owner_b,query_rr;
 wire choose_b=rx_queries[1] && (!rx_queries[0] || query_rr);
 wire [1:0] physical_start,physical_finish,physical_idle,physical_overrun;
 wire [1:0] copy_mask;
 reg [1:0] owner_mask,started_mask,finished_mask;reg line_started,line_finished;
 wire [1:0] next_started=started_mask|physical_start,next_finished=finished_mask|physical_finish;
 wire [1:0] rx_mac_badframe,rx_mac_badfcs,rx_mac_overflow,tx_mac_underflow,tx_mac_overflow;
 wire [31:0] rx_event_data;wire rx_event_valid,rx_event_overrun;
 wire [127:0] rx_legacy_data;
 wire table_init,tx_state_init,rx_state_init,bag_init,table_freeze;
 wire seq_tx_init,seq_rx_init,seq_tx_q_ready,seq_rx_q_ready,seq_tx_r_valid,seq_rx_r_valid,seq_tx_error,seq_rx_error;
 wire [31:0] seq_tx_word,seq_rx_word;
 wire [191:0] seq_tx_counts,seq_rx_counts;
 wire sequence_query;
 wire tx_idle,tx_setup,rx_idle,mgmt_cache_busy,owner_busy,bridge_idle;
 wire [15:0] tx_used,tx_free,tx_peak,rx_used,rx_free,rx_peak;
 wire [31:0] now;
 wire freeze_new=table_freeze || cfg_commit_valid || !init_done;
 // Accepted commands and a partially parsed RX frame must finish their old
 // active-bank lookup BEFORE the table accepts commit and blocks its port.
 wire commit_safe=!tx_setup && rx_idle;
 wire table_commit_ready;
 assign cfg_commit_ready=table_commit_ready && commit_safe;
 wire quiescent=tx_idle && rx_idle && !mgmt_cache_busy && !owner_busy && bridge_idle;
 wire [15:0] active_mgmt_max;
 wire [2:0] active_period,active_max_bag;
 wire admitted;
 wire [31:0] active_line,active_service,line_sum,service_sum;
 wire [15:0] active_tx_count,active_rx_count;
 reg [15:0] shadow_mgmt_max;
 reg [2:0] shadow_period;
 reg [31:0] shadow_line,shadow_service;
 wire table_wr_ready,table_wr_error,table_rd_ready,table_rd_valid,table_rd_error;
 wire [31:0] table_rd_data;
 wire [15:0] table_rd_version;
 wire table_q_ready,table_q_valid,table_q_found,table_q_error;
 wire [12:0] table_q_index;
 wire [255:0] table_q_config;
 wire [15:0] table_q_version;
 wire tx_query,tx_query_ready,tx_q_take,rx_query,rx_query_ready,rx_q_take;
 wire [12:0] tx_query_index;
 wire [15:0] rx_query_vl;
 reg query_busy,query_owner_rx;
 wire choose_rx=|rx_queries;
 assign rx_query=|rx_queries;
 assign rx_query_vl=rx_query_vls[choose_b];
 assign rx_query_readys[0]=!query_busy && choose_rx && !choose_b && table_q_ready;
 assign rx_query_readys[1]=!query_busy && choose_rx && choose_b && table_q_ready;
 wire query_request=!query_busy && (rx_query || tx_query);
 assign tx_query_ready=!query_busy && !choose_rx && table_q_ready;
 assign rx_query_ready=!query_busy && choose_rx && table_q_ready;
 wire q_result_ready=query_owner_rx?rx_query_takes[query_owner_b]:tx_q_take;
 // Management reads never hold the result port across an unbounded scan.
 reg [3:0] bus_state;
 reg [3:0] saved_word;
 reg saved_bank,saved_bad_index;
 localparam B_IDLE=0,B_WRITE=1,B_READ=2,B_STATE=3,B_STATS=4,B_SEQUENCE=5;
 wire bus_idle=bus_state==B_IDLE && !cfg_resp_valid;
 wire bus_accept=cfg_valid && cfg_ready;
 assign sequence_query=bus_idle && cfg_valid && !cfg_write && cfg_kind==1 && cfg_word>=4;
 wire cfg_access=bus_idle && cfg_kind==0;
 wire table_write=cfg_access && cfg_valid && cfg_write;
 wire table_read=cfg_access && cfg_valid && !cfg_write;
 wire stats_read=bus_idle && cfg_valid && !cfg_write && cfg_kind==2;
 wire stats_read_ready,stats_result_valid,stats_result_error;
 wire [31:0] stats_result_data,snapshot_epoch;
 wire tx_state_q_ready,rx_state_q_ready,tx_state_r_valid,rx_state_r_valid;
 wire [127:0] tx_state_data,rx_state_data;
 wire tx_state_r_error,rx_state_r_error,tx_state_update_ready,rx_state_update_ready,tx_state_error,rx_state_error;
 wire state_request=bus_idle && cfg_valid && !cfg_write && cfg_kind==1 && cfg_word<4;
 assign cfg_ready=bus_idle && init_done &&
    (cfg_kind==0?(cfg_write?table_wr_ready:table_rd_ready):
     cfg_kind==1?(cfg_write || (cfg_word>=4?(cfg_bank?seq_rx_q_ready:seq_tx_q_ready):(cfg_bank?rx_state_q_ready:tx_state_q_ready))):
     cfg_kind==2?(cfg_write || stats_read_ready):!table_freeze && !cfg_commit_valid);
 snmp_config_table table_core (
  .clk(clk),.rst_n(rst_n),.wr_valid(table_write),.wr_bank(cfg_bank),.wr_index(cfg_index),.wr_word(cfg_word),.wr_data(cfg_data),.wr_ready(table_wr_ready),.wr_error(table_wr_error),
  .rd_valid(table_read),.rd_shadow(cfg_shadow),.rd_bank(cfg_bank),.rd_index(cfg_index),.rd_word(cfg_word),.rd_ready(table_rd_ready),
  .rd_result_valid(table_rd_valid),.rd_result_ready(bus_state==B_READ),.rd_error(table_rd_error),.rd_data(table_rd_data),.rd_version(table_rd_version),
  .commit_valid(cfg_commit_valid && commit_safe),.budget_only(budget_valid),.quiescent(quiescent),.commit_ready(table_commit_ready),.freeze(table_freeze),.pending(cfg_pending),.applied(cfg_applied),
  .result_valid(cfg_result_valid),.result_ready(cfg_result_ready),.result_ok(cfg_result_ok),.result_code(cfg_result_code),.version(cfg_version),.result_version(),.init_done(table_init),
  .q_valid(query_request),.q_dir(choose_rx),.q_index(tx_query_index),.q_vl(rx_query_vl),.q_ready(table_q_ready),
  .q_result_valid(table_q_valid),.q_result_ready(query_busy && q_result_ready),.q_found(table_q_found),.q_error(table_q_error),.q_result_index(table_q_index),.q_config(table_q_config),.q_version(table_q_version),
  .mgmt_max_client(budget_valid?budget_max:shadow_mgmt_max),.mgmt_period_exp(budget_valid?budget_period:shadow_period),.line_limit_kbps(budget_valid?budget_line:shadow_line),.service_limit_cycles(budget_valid?budget_service:shadow_service),
  .active_mgmt_max_client(active_mgmt_max),.active_mgmt_period_exp(active_period),.active_line_limit_kbps(active_line),.active_service_limit_cycles(active_service),
  .active_line_sum(line_sum),.active_service_sum(service_sum),.active_admitted(admitted),.active_max_bag_exp(active_max_bag),.active_tx_count(active_tx_count),.active_rx_count(active_rx_count));
 always @(posedge clk)begin
  if(!rst_n)begin query_busy<=0;query_owner_rx<=0;query_owner_b<=0;query_rr<=0;end
  else begin
   if(query_request && table_q_ready)begin query_busy<=1;query_owner_rx<=choose_rx;query_owner_b<=choose_b;if(choose_rx)query_rr<=!choose_b;end
   if(table_q_valid && query_busy && q_result_ready)query_busy<=0;
  end
 end
 wire [2:0] cand_slot,grant_slot;
 wire cand_valid,grant_valid,grant_ready,tx_busy,tx_alloc,tx_discard,tx_release,tx_submitted,tx_error;
 wire [255:0] cand_config,tx_current_config;
 wire [12:0] cand_index,tx_current_index;
 wire [15:0] cand_length,cand_version,tx_current_length,tx_current_payload_length;
 wire [31:0] candidate_epoch;
 wire [7:0] pending_mask;
 wire [7:0] rt_data;
 wire rt_valid,rt_ready,rt_sop,rt_last,rt_error;
 sequence_tx_path transmit (.message_seed_valid(message_seed_valid),.message_seed(message_seed),.message_seed_ready(message_seed_ready),
  .clk(clk),.rst_n(rst_n),.freeze(freeze_new),
  .app_cmd_valid(app_tx_cmd_valid),.app_cmd_ready(app_tx_cmd_ready),.app_cmd_index(app_tx_cmd_index),.app_cmd_length(app_tx_cmd_length),
  .app_data(app_tx_data),.app_valid(app_tx_valid),.app_ready(app_tx_ready),.app_last(app_tx_last),.commit_valid(app_tx_commit_valid),.commit_ready(app_tx_commit_ready),.abort(app_tx_abort),
  .error_valid(app_tx_error_valid),.error_ready(app_tx_error_ready),.error_code(app_tx_error_code),
  .query_valid(tx_query),.query_ready(tx_query_ready),.query_index(tx_query_index),
  .query_result_valid(table_q_valid && query_busy && !query_owner_rx),.query_result_ready(tx_q_take),.query_found(table_q_found && !table_q_error),
  .query_config(table_q_config),.query_result_index(table_q_index),.query_version(table_q_version),
  .cand_index(cand_slot),.cand_valid(cand_valid),.cand_config(cand_config),.cand_index_out(cand_index),.cand_version(cand_version),.cand_length(cand_length),
  .grant_valid(grant_valid),.grant_slot(grant_slot),.grant_ready(grant_ready),
  .m_data(rt_data),.m_valid(rt_valid),.m_ready(rt_ready),.m_sop(rt_sop),.m_last(rt_last),.m_error(rt_error),
  .submitted(tx_submitted),.released(tx_release),.allocated(tx_alloc),.discarded(tx_discard),.ownership_error(tx_error),
  .used_count(tx_used),.free_count(tx_free),.peak_count(tx_peak),.idle(tx_idle),.setup_busy(tx_setup),.busy(tx_busy),
  .seq_init(seq_tx_init),.seq_q_valid(sequence_query&&!cfg_bank),.seq_q_ready(seq_tx_q_ready),.seq_q_index(cfg_index),
  .seq_q_result_valid(seq_tx_r_valid),.seq_q_result_ready(bus_state==B_SEQUENCE&&!saved_bank),.seq_q_error(seq_tx_error),.seq_q_data(seq_tx_word),.seq_counts(seq_tx_counts),
  .current_index(tx_current_index),.current_config(tx_current_config),.current_payload_length(tx_current_payload_length),.current_length(tx_current_length),.candidate_epoch(candidate_epoch),.pending_mask(pending_mask));
 wire rx_accept,rx_reject,rx_resource,rx_cancel,rx_discard,rx_release,rx_alloc,rx_error,rx_known,rx_checked,rx_overlength;
 wire [12:0] rx_index;
 wire [15:0] rx_length;
 wire [7:0] rx_sn,rx_raw_data;
 wire [4:0] rx_reason;
 wire rx_raw_valid,rx_raw_ready,rx_raw_sop,rx_raw_last,rx_raw_error;
 wire [7:0] mac_raw_data[0:1];
 wire [1:0] mac_raw_valid,mac_raw_ready,mac_raw_sop,mac_raw_last,mac_raw_error;
 genvar n;
 generate for(n=0;n<2;n=n+1)begin:networks
  snmp_rx_demux management_split(.clk(clk),.rst_n(rst_n),
   .s_data(mac_raw_data[n]),.s_valid(mac_raw_valid[n]),.s_ready(mac_raw_ready[n]),.s_sop(mac_raw_sop[n]),.s_last(mac_raw_last[n]),.s_error(mac_raw_error[n]),
   .rt_data(rx_raw_datas[n]),.rt_valid(rx_raw_valids[n]),.rt_ready(rx_raw_readys[n]),.rt_sop(rx_raw_sops[n]),.rt_last(rx_raw_lasts[n]),.rt_error(rx_raw_errors[n]),
   .mg_data(management_rx_data[n*8+:8]),.mg_valid(management_rx_valid[n]),.mg_ready(management_rx_ready[n]),.mg_sop(management_rx_sop[n]),.mg_last(management_rx_last[n]),.mg_error(management_rx_error[n]));
  redundancy_rx_path receive_path (
   .clk(clk),.rst_n(rst_n),.monotonic_time(extended_time),.freeze(freeze_new),
   .raw_data(rx_raw_datas[n]),.raw_valid(rx_raw_valids[n]),.raw_ready(rx_raw_readys[n]),.raw_sop(rx_raw_sops[n]),.raw_last(rx_raw_lasts[n]),.raw_error(rx_raw_errors[n]),
   .query_valid(rx_queries[n]),.query_ready(rx_query_readys[n]),.query_vl(rx_query_vls[n]),
   .query_result_valid(table_q_valid && query_busy && query_owner_rx && query_owner_b==n),.query_result_ready(rx_query_takes[n]),.query_found(table_q_found && !table_q_error),
   .query_config(table_q_config),.query_index(table_q_index),.query_version(table_q_version),
   .integrity_valid(iq_valid[n]),.integrity_ready(iq_ready[n]),.integrity_index(iq_index[n]),.integrity_vl(iq_vl[n]),.integrity_sn(iq_sn[n]),.integrity_time(iq_time[n]),.integrity_rm_enable(iq_enable[n]),.integrity_select(iq_select[n]),
   .integrity_result_valid(ir_valid[n]),.integrity_result_ready(ir_ready[n]),.integrity_pass(ir_pass[n]),.integrity_ic_pass(ir_ic[n]),.integrity_error(ir_error[n]),.integrity_reason(ir_reason),
   .app_desc_fragment(app_fragments[n]),.app_desc_valid(app_desc_valids[n]),.app_desc_ready(app_desc_readys[n]),.app_desc_length(app_lengths[n]),.app_desc_vl(app_vls[n]),.app_desc_app_id(app_ids[n]),.app_desc_version(app_versions[n]),.app_desc_sn(app_sns[n]),.app_desc_udp_checked(app_checkeds[n]),
   .app_data(app_datas[n]),.app_valid(app_valids[n]),.app_ready(app_readys[n]),.app_sop(app_sops[n]),.app_last(app_lasts[n]),
   .used_count(rx_useds[n]),.free_count(rx_frees[n]),.peak_count(rx_peaks[n]),.idle(rx_idles[n]),
   .accepted(rx_accepted[n]),.rejected(rx_rejected[n]),.resource_drop(rx_resources[n]),.cancelled(rx_cancels[n]),.discarded(rx_discards[n]),.overlength(rx_overs[n]),.released(rx_releases[n]),.allocated(rx_allocs[n]),.ownership_error(rx_errors[n]),
   .reason(rx_reasons[n]),.event_index(rx_indices[n]),.event_length(rx_lengths[n]),.event_sn(rx_sns[n]),.event_checked(rx_checkeds[n]),.event_known(rx_knowns[n]));
 end endgenerate
 assign rx_idle=rx_a_idle && rx_b_idle && !rm_busy;
 assign rx_used=rx_useds[0]+rx_useds[1];assign rx_free=rx_frees[0]+rx_frees[1];
 reg [15:0] combined_peak;
 always @(posedge clk)if(!rst_n)combined_peak<=0;else if(rx_used>combined_peak)combined_peak<=rx_used;
 assign rx_peak=combined_peak;
 // Application arbitration follows RM winner COMMIT order, not a fresh RR
 // selection after each application frame. This prevents cross-network reordering.
 reg [15:0] winner_queue;reg [3:0] win_write,win_read;reg [4:0] win_count;
 reg queue_error;
 wire win_push=|rx_accepted,win_pop=app_rx_valid && app_rx_ready && app_rx_last;
 wire winner=winner_queue[win_read];
 assign app_rx_network=winner;
 assign app_rx_fragment=app_fragments[winner];
 assign app_rx_desc_valid=win_count!=0 && app_desc_valids[winner];
 assign app_rx_desc_length=app_lengths[winner];assign app_rx_desc_vl=app_vls[winner];
 assign app_rx_desc_app_id=app_ids[winner];assign app_rx_desc_version=app_versions[winner];
 assign app_rx_desc_sn=app_sns[winner];assign app_rx_desc_udp_checked=app_checkeds[winner];
 assign app_desc_readys[0]=win_count!=0 && !winner && app_rx_desc_ready;
 assign app_desc_readys[1]=win_count!=0 && winner && app_rx_desc_ready;
 assign app_rx_data=app_datas[winner];assign app_rx_valid=win_count!=0 && app_valids[winner];
 assign app_rx_sop=app_sops[winner];assign app_rx_last=app_lasts[winner];
 assign app_readys[0]=win_count!=0 && !winner && app_rx_ready;
 assign app_readys[1]=win_count!=0 && winner && app_rx_ready;
 always @(posedge clk)begin
  if(!rst_n)begin winner_queue<=0;win_write<=0;win_read<=0;win_count<=0;queue_error<=0;end
  else begin
   queue_error<=0;
   if(win_push)begin
    if(rx_accepted==3 || (win_count==16 && !win_pop))queue_error<=1;
    else begin winner_queue[win_write]<=rx_accepted[1];win_write<=win_write+1'b1;end
   end
   if(win_pop)begin if(win_count==0)queue_error<=1;else win_read<=win_read+1'b1;end
   case({win_push,win_pop})2'b10:win_count<=win_count+1'b1;2'b01:win_count<=win_count-1'b1;default:begin end endcase
  end
 end
 redundancy_core redundancy_manager(.clk(clk),.rst_n(rst_n),.init_done(seq_rx_init),
   .s_valid(rm_request),.s_ready(rm_request_ready),.s_network(rm_owner),.s_index(merged_candidate[12:0]),.s_vl(merged_candidate[28:13]),.s_sn(merged_candidate[36:29]),.s_time(merged_candidate[100:37]),.s_rm_enable(merged_candidate[101]),.s_select(merged_candidate[103:102]),
  .result_valid(rm_result_valid),.result_ready(rm_take),.result_pass(rm_result_pass),.result_ic_pass(rm_ic_pass),.result_error(rm_result_error),.result_expired(rm_expired),.result_reason(ir_reason),
  .q_valid(sequence_query && cfg_bank),.q_ready(seq_rx_q_ready),.q_index(cfg_index),.q_result_valid(seq_rx_r_valid),.q_result_ready(bus_state==B_SEQUENCE && saved_bank),.q_error(seq_rx_error),.q_data(rm_record),
  .count_a(rm_counts[31:0]),.count_b(rm_counts[63:32]),.count_ic_drop(rm_counts[95:64]),.count_rm_drop(rm_counts[127:96]),.count_winner(rm_counts[159:128]),.count_reset(rm_counts[191:160]),.idle());
 candidate_merge candidate_order(.clk(clk),.rst_n(rst_n),.s_valid(iq_valid),.s_ready(iq_ready),
  .a_data({iq_select[0],iq_enable[0],iq_time[0],iq_sn[0],iq_vl[0],iq_index[0]}),
  .b_data({iq_select[1],iq_enable[1],iq_time[1],iq_sn[1],iq_vl[1],iq_index[1]}),
  .m_valid(rm_request),.m_ready(rm_request_ready),.m_data(merged_candidate),.network(rm_owner),.completed(rm_result_valid && rm_take),.busy(rm_busy));
 wire [7:0] mgmt_out;
 wire mgmt_out_valid,mgmt_out_ready,mgmt_out_sop,mgmt_out_last,mgmt_candidate,mgmt_submitted,mgmt_released,mgmt_launch,mgmt_release,mgmt_grant;
 wire [15:0] mgmt_length;
 management_buffer management (
  .clk(clk),.rst_n(rst_n),.abort(mgmt_abort && !line_management),.freeze(freeze_new),.configured_max(active_mgmt_max),
  .cmd_valid(mgmt_cmd_valid),.cmd_ready(mgmt_cmd_ready),.cmd_length(mgmt_cmd_length),.s_data(mgmt_data),.s_valid(mgmt_valid),.s_last(mgmt_last),.s_ready(mgmt_ready),
  .commit_valid(mgmt_commit_valid),.commit_ready(mgmt_commit_ready),.launch(mgmt_launch),.release_frame(mgmt_release),
  .candidate(mgmt_candidate),.busy(mgmt_cache_busy),.released(mgmt_released),.submitted(mgmt_submitted),.error_valid(mgmt_error_valid),.error_ready(mgmt_error_ready),.error_code(mgmt_error_code),.length(mgmt_length),
  .m_data(mgmt_out),.m_valid(mgmt_out_valid),.m_sop(mgmt_out_sop),.m_last(mgmt_out_last),.m_ready(mgmt_out_ready));
 wire line_start,line_finish,rt_start,rt_finish,scheduler_error,bridge_overrun;
 wire [12:0] owner_index;
 wire [2:0] owner_exp;
 wire [31:0] management_service,available_window;
 wire rt_permit;
 capacity_scheduler scheduler (
  .clk(clk),.rst_n(rst_n),.dispatch_enable(admitted && init_done),.config_applied(cfg_applied),.active_max_bag_exp(active_max_bag),.management_period(active_period),
  .cand_slot(cand_slot),.cand_valid(cand_valid),.cand_config(cand_config),.cand_index(cand_index),.candidate_epoch(candidate_epoch),.cand_length(cand_length),.rt_permit(rt_permit),
  .grant_valid(grant_valid),.grant_slot(grant_slot),.grant_ready(grant_ready),.management_candidate(mgmt_candidate),.management_length(mgmt_length),
  .management_launch(mgmt_launch),.management_release(mgmt_release),.management_submitted(mgmt_submitted),.rt_submitted(tx_submitted),.rt_busy(tx_busy),
  .line_start(line_start),.line_finish(line_finish),.owner_busy(owner_busy),.owner_management(line_management),.rt_start(rt_start),.rt_finish(rt_finish),.mgmt_grant(mgmt_grant),
  .owner_index(owner_index),.owner_exp(owner_exp),.now(now),.init_done(bag_init),.management_service(management_service),.available_window(available_window),.ownership_error(scheduler_error));
 wire [7:0] mac_tx_data=line_management?mgmt_out:rt_data;
 wire mac_tx_valid=owner_busy && (line_management?mgmt_out_valid:(rt_valid && rt_permit));
 wire mac_tx_last=line_management?mgmt_out_last:rt_last;
 wire mac_tx_ready;
 assign rt_ready=owner_busy && !line_management && rt_permit && mac_tx_ready;
 assign mgmt_out_ready=owner_busy && line_management && mac_tx_ready;
 wire [7:0] copy_data_a,copy_data_b;wire [1:0] copy_valid,copy_ready,copy_last,copy_error;
 wire [1:0] frame_selection=line_management?management_select:tx_current_config[245:244];
 wire replicator_idle;
 tx_replicator replicator(.clk(clk),.rst_n(rst_n),.select_net(frame_selection),.management(line_management),
  .s_data(mac_tx_data),.s_valid(mac_tx_valid),.s_sop(line_management?mgmt_out_sop:rt_sop),.s_last(mac_tx_last),.s_error(!line_management && rt_error),.s_ready(mac_tx_ready),
  .a_data(copy_data_a),.b_data(copy_data_b),.a_valid(copy_valid[0]),.b_valid(copy_valid[1]),.a_ready(copy_ready[0]),.b_ready(copy_ready[1]),.a_last(copy_last[0]),.b_last(copy_last[1]),.a_error(copy_error[0]),.b_error(copy_error[1]),.active_mask(copy_mask),.idle(replicator_idle));
 gmii_event_bridge bridge_a(.clk(clk),.rst_n(rst_n),.gtx_clk(gtx_clk),.tx_en(phy_a_tx_en),.start_confirmed(physical_start[0]),.finish_confirmed(physical_finish[0]),.idle(physical_idle[0]),.overrun(physical_overrun[0]));
 gmii_event_bridge bridge_b(.clk(clk),.rst_n(rst_n),.gtx_clk(gtx_clk),.tx_en(phy_b_tx_en),.start_confirmed(physical_start[1]),.finish_confirmed(physical_finish[1]),.idle(physical_idle[1]),.overrun(physical_overrun[1]));
 assign bridge_idle=&physical_idle;assign bridge_overrun=|physical_overrun;
 // Latest selected start is the conservative BAG anchor for BOTH networks.
 // The scheduler retains one logical owner until every selected line has ended.
 assign line_start=owner_busy && !line_started && ((next_started & owner_mask)==owner_mask) && owner_mask!=0;
 assign line_finish=owner_busy && !line_finished && ((next_finished & owner_mask)==owner_mask) && owner_mask!=0;
 always @(posedge clk)begin
  if(!rst_n)begin owner_mask<=0;started_mask<=0;finished_mask<=0;line_started<=0;line_finished<=0;end
  else if(!owner_busy)begin owner_mask<=0;started_mask<=0;finished_mask<=0;line_started<=0;line_finished<=0;end
  else begin
   if(owner_mask==0 && mac_tx_valid)owner_mask<=copy_mask;
   started_mask<=next_started;finished_mask<=next_finished;
   if(line_start)line_started<=1;if(line_finish)line_finished<=1;
  end
 end
 mac_channel_gmii mac_a (
  .clk(clk),.rst_n(rst_n),.tx_data(copy_data_a),.tx_valid(copy_valid[0]),.tx_ready(copy_ready[0]),.tx_last(copy_last[0]),.tx_error(copy_error[0]),
  .rx_data(mac_raw_data[0]),.rx_valid(mac_raw_valid[0]),.rx_ready(mac_raw_ready[0]),.rx_sop(mac_raw_sop[0]),.rx_last(mac_raw_last[0]),.rx_error(mac_raw_error[0]),
  .gtx_clk(gtx_clk),.phy_rx_clk(phy_a_rx_clk),.phy_rxd(phy_a_rxd),.phy_rx_dv(phy_a_rx_dv),.phy_rx_er(phy_a_rx_er),.phy_tx_clk(phy_a_tx_clk),.phy_txd(phy_a_txd),.phy_tx_en(phy_a_tx_en),.phy_tx_er(phy_a_tx_er),
  .cfg_tx_enable(1'b1),.cfg_rx_enable(1'b1),.tx_sop_to_mac(),.tx_error_underflow(tx_mac_underflow[0]),.tx_fifo_overflow(tx_mac_overflow[0]),.tx_fifo_bad_frame(),.tx_fifo_good_frame(),
  .rx_error_bad_frame(rx_mac_badframe[0]),.rx_error_bad_fcs(rx_mac_badfcs[0]),.rx_fifo_overflow(rx_mac_overflow[0]),.rx_fifo_bad_frame(),.rx_fifo_good_frame());
 mac_channel_gmii mac_b (
  .clk(clk),.rst_n(rst_n),.tx_data(copy_data_b),.tx_valid(copy_valid[1]),.tx_ready(copy_ready[1]),.tx_last(copy_last[1]),.tx_error(copy_error[1]),
  .rx_data(mac_raw_data[1]),.rx_valid(mac_raw_valid[1]),.rx_ready(mac_raw_ready[1]),.rx_sop(mac_raw_sop[1]),.rx_last(mac_raw_last[1]),.rx_error(mac_raw_error[1]),
  .gtx_clk(gtx_clk),.phy_rx_clk(phy_b_rx_clk),.phy_rxd(phy_b_rxd),.phy_rx_dv(phy_b_rx_dv),.phy_rx_er(phy_b_rx_er),.phy_tx_clk(phy_b_tx_clk),.phy_txd(phy_b_txd),.phy_tx_en(phy_b_tx_en),.phy_tx_er(phy_b_tx_er),
  .cfg_tx_enable(1'b1),.cfg_rx_enable(1'b1),.tx_sop_to_mac(),.tx_error_underflow(tx_mac_underflow[1]),.tx_fifo_overflow(tx_mac_overflow[1]),.tx_fifo_bad_frame(),.tx_fifo_good_frame(),
  .rx_error_bad_frame(rx_mac_badframe[1]),.rx_error_bad_fcs(rx_mac_badfcs[1]),.rx_fifo_overflow(rx_mac_overflow[1]),.rx_fifo_bad_frame(),.rx_fifo_good_frame());
 wire mac_underflow=|tx_mac_underflow,mac_tx_overflow=|tx_mac_overflow,mac_rx_badframe=|rx_mac_badframe,mac_rx_badfcs=|rx_mac_badfcs,mac_rx_overflow=|rx_mac_overflow;
 assign init_done=table_init && tx_state_init && rx_state_init && bag_init && seq_tx_init && seq_rx_init;
 reg [31:0] tick_high;
 always @(posedge clk)begin
  if(!rst_n)tick_high<=0;
  else if(now==32'hffffffff)tick_high<=tick_high+1'b1;
 end
 assign extended_time={tick_high,now};
 vl_state_ram #(.ENTRY_COUNT(128),.RX_MODE(0)) tx_state (
  .clk(clk),.rst_n(rst_n),.init_done(tx_state_init),.update_valid(rt_start),.update_ready(tx_state_update_ready),.update_index(owner_index),.update_accepted(1'b1),.update_length(tx_current_payload_length),.update_time(extended_time),.update_budget(32'd100000<<owner_exp),.update_sn(8'd1),.update_checked(1'b1),
  .q_valid(state_request && !cfg_bank),.q_ready(tx_state_q_ready),.q_index(cfg_index),.result_valid(tx_state_r_valid),.result_ready(bus_state==B_STATE && !saved_bank),.result_error(tx_state_r_error),.result_data(tx_state_data),.error_event(tx_state_error));
 wire [47:0] legacy_event;
 dual_event_queue legacy_events(.clk(clk),.rst_n(rst_n),
  .a_valid((rx_accepted[0] || rx_rejected[0]) && rx_knowns[0]),.a_data({9'd0,rx_checkeds[0],rx_sns[0],rx_lengths[0],rx_indices[0],rx_accepted[0]}),
  .b_valid((rx_accepted[1] || rx_rejected[1]) && rx_knowns[1]),.b_data({9'd0,rx_checkeds[1],rx_sns[1],rx_lengths[1],rx_indices[1],rx_accepted[1]}),
  .m_valid(rx_event_valid),.m_ready(rx_state_update_ready),.m_data(legacy_event),.overflow(rx_event_overrun));
 vl_state_ram #(.ENTRY_COUNT(4096),.RX_MODE(1)) rx_state (
  .clk(clk),.rst_n(rst_n),.init_done(rx_state_init),.update_valid(rx_event_valid),.update_ready(rx_state_update_ready),
  .update_index(legacy_event[13:1]),.update_accepted(legacy_event[0]),.update_length(legacy_event[29:14]),.update_time(64'd0),.update_budget(32'd0),.update_sn(legacy_event[37:30]),.update_checked(legacy_event[38]),
  .q_valid(state_request && cfg_bank),.q_ready(rx_state_q_ready),.q_index(cfg_index),.result_valid(rx_state_r_valid),.result_ready(bus_state==B_STATE && saved_bank),.result_error(rx_state_r_error),.result_data(rx_state_data),.error_event(rx_state_error));
 assign rx_accept=|rx_accepted;assign rx_reject=|rx_rejected;assign rx_resource=|rx_resources;
 assign rx_cancel=|rx_cancels;assign rx_discard=|rx_discards;assign rx_release=|rx_releases;assign rx_alloc=|rx_allocs;
 assign rx_error=(|rx_errors) || queue_error || rx_event_overrun;assign rx_overlength=|rx_overs;
 assign rx_length=rx_accepted[0]?rx_lengths[0]:rx_lengths[1];
 reg [895:0] increments;
 always @* begin
  increments=0;
  increments[0*32+:32]=rt_finish;increments[1*32+:32]=rt_finish?{16'd0,tx_current_payload_length}:0;
  increments[2*32+:32]={31'd0,rx_accepted[0]}+{31'd0,rx_accepted[1]};increments[3*32+:32]=(rx_accepted[0]?{16'd0,rx_lengths[0]}:0)+(rx_accepted[1]?{16'd0,rx_lengths[1]}:0);
  increments[4*32+:32]={31'd0,rx_rejected[0]}+{31'd0,rx_rejected[1]};increments[5*32+:32]={31'd0,(rx_rejected[0] && rx_reasons[0]==16 && !rx_knowns[0])}+{31'd0,(rx_rejected[1] && rx_reasons[1]==16 && !rx_knowns[1])};
  increments[6*32+:32]={31'd0,rx_overs[0]}+{31'd0,rx_overs[1]};increments[7*32+:32]={31'd0,rx_resources[0]}+{31'd0,rx_resources[1]};
  increments[8*32+:32]=app_tx_error_valid && app_tx_error_ready;
  increments[9*32+:32]={31'd0,rx_mac_badfcs[0]}+{31'd0,rx_mac_badfcs[1]};increments[10*32+:32]={31'd0,rx_mac_badframe[0]}+{31'd0,rx_mac_badframe[1]};increments[11*32+:32]={31'd0,rx_mac_overflow[0]}+{31'd0,rx_mac_overflow[1]};increments[12*32+:32]=mac_underflow || mac_tx_overflow;
  increments[13*32+:32]=cfg_result_valid && cfg_result_ready && !cfg_result_ok;
  increments[14*32+:32]=tx_alloc;increments[15*32+:32]={31'd0,tx_release}+{31'd0,tx_discard};
  increments[16*32+:32]={31'd0,rx_allocs[0]}+{31'd0,rx_allocs[1]};increments[17*32+:32]={31'd0,rx_releases[0]}+{31'd0,rx_releases[1]}+{31'd0,rx_discards[0]}+{31'd0,rx_discards[1]};
  increments[18*32+:32]=bridge_overrun || tx_error || rx_error || scheduler_error || tx_state_error || rx_state_error || (rt_start && !tx_state_update_ready);
  increments[19*32+:32]={31'd0,rx_cancels[0]}+{31'd0,rx_cancels[1]};
  increments[20*32+:32]=mgmt_release;increments[21*32+:32]=mgmt_release?{16'd0,mgmt_length}:0;
  increments[22*32+:32]=cfg_applied;increments[23*32+:32]=grant_valid && grant_ready;
  increments[24*32+:32]=final_app_frame;
  increments[25*32+:32]=final_app_byte;
  increments[26*32+:32]=mgmt_error_valid && mgmt_error_ready;
  increments[27*32+:32]=mac_tx_valid && mac_tx_ready && mac_tx_last;
 end
 snmp_event_stats statistics(.live_resource_count(trap_fault_total),.clk(clk),.rst_n(rst_n),.increments(increments),
  .snapshot_valid(bus_accept && cfg_kind==2 && cfg_write),.snapshot_ready(),.snapshot_epoch(snapshot_epoch),
  .read_valid(stats_read),.read_ready(stats_read_ready),.read_index(cfg_index[5:0]),.result_valid(stats_result_valid),.result_ready(bus_state==B_STATS),.result_error(stats_result_error),.result_data(stats_result_data),
  .tx_used(tx_used),.tx_free(tx_free),.tx_peak(tx_peak),.rx_used(rx_used),.rx_free(rx_free),.rx_peak(rx_peak));
 assign trap_fault_events=rx_resources;assign trap_used=rx_used;assign trap_line_complete=mgmt_release;
 assign events={rx_cancel,rx_resource,rx_reject,rx_accept,tx_release,mgmt_grant,rt_start,rt_finish};
 always @(posedge clk)begin
  if(!rst_n)begin
   obs_sequence<=0;obs_candidate<=0;obs_decision<=0;obs_meta<=0;obs_vl<=0;
   obs_drop_a<=0;obs_drop_b<=0;obs_drop_valid<=0;obs_snapshot<=0;
  end else begin
   if(rm_result_valid && rm_take)begin
    obs_sequence<=obs_sequence+1'b1;obs_candidate<=merged_candidate[100:37];
    obs_decision<=extended_time;obs_vl<=merged_candidate[28:13];
    obs_meta<={1'b0,1'b1,rm_result_error,rm_expired,rm_result_pass,rm_ic_pass,
      ir_reason,rm_owner,merged_candidate[36:29],merged_candidate[12:0]};
   end
   if(rx_rejected[0])begin obs_drop_a<=rx_reasons[0];obs_drop_valid[0]<=1;end
   if(rx_rejected[1])begin obs_drop_b<=rx_reasons[1];obs_drop_valid[1]<=1;end
   if(bus_accept && cfg_kind==3 && !cfg_write && cfg_word==8)obs_snapshot<=obs_live;
  end
 end
 always @(posedge clk)begin
  if(!rst_n)begin
   bus_state<=B_IDLE;saved_word<=0;saved_bank<=0;saved_bad_index<=0;cfg_resp_valid<=0;cfg_resp_error<=0;cfg_resp_data<=0;
   shadow_mgmt_max<=1514;shadow_period<=0;shadow_line<=700000;shadow_service<=80000;
  end else begin
   if(cfg_resp_valid && cfg_resp_ready)cfg_resp_valid<=0;
   if(bus_accept)begin
    saved_word<=cfg_word;saved_bank<=cfg_bank;saved_bad_index<=cfg_index>=32;cfg_resp_error<=0;cfg_resp_data<=0;
    if(cfg_kind==0)bus_state<=cfg_write?B_WRITE:B_READ;
    else if(cfg_kind==1)begin
     if(cfg_write)begin cfg_resp_valid<=1;cfg_resp_error<=1;end
     else bus_state<=cfg_word>=4?B_SEQUENCE:B_STATE;
    end
    else if(cfg_kind==2)begin
     if(cfg_write)begin cfg_resp_valid<=1;cfg_resp_data<=snapshot_epoch+1'b1;end
     else bus_state<=B_STATS;
    end else begin
     cfg_resp_valid<=1;
     if(cfg_write)case(cfg_word)
      0:begin if(cfg_data[31:16]==0)shadow_mgmt_max<=cfg_data[15:0];else cfg_resp_error<=1;end
      1:begin if(cfg_data[31:3]==0)shadow_period<=cfg_data[2:0];else cfg_resp_error<=1;end
      2:shadow_line<=cfg_data;
      3:shadow_service<=cfg_data;
      default:cfg_resp_error<=1;
     endcase
     else case(cfg_word)
      0:cfg_resp_data<={16'd0,active_mgmt_max};1:cfg_resp_data<={29'd0,active_period};
      2:cfg_resp_data<=active_line;3:cfg_resp_data<=active_service;
      4:cfg_resp_data<=line_sum;5:cfg_resp_data<=service_sum;
      6:cfg_resp_data<={active_rx_count,active_tx_count};
      7:cfg_resp_data<={16'd0,cfg_version};
      8:cfg_resp_data<=obs_sequence;
      9:cfg_resp_data<=obs_snapshot[63:32];
      10:cfg_resp_data<=obs_snapshot[95:64];
      11:cfg_resp_data<=obs_snapshot[127:96];
      12:cfg_resp_data<=obs_snapshot[159:128];
      13:cfg_resp_data<=obs_snapshot[191:160];
      14:cfg_resp_data<=obs_snapshot[223:192];
      15:cfg_resp_data<=obs_snapshot[255:224];
      default:cfg_resp_error<=1;
     endcase
    end
   end
   if(bus_state==B_WRITE)begin cfg_resp_valid<=1;cfg_resp_error<=table_wr_error;bus_state<=B_IDLE;end
   if(bus_state==B_READ && table_rd_valid)begin cfg_resp_valid<=1;cfg_resp_error<=table_rd_error;cfg_resp_data<=table_rd_data;bus_state<=B_IDLE;end
   if(bus_state==B_STATE && (saved_bank?rx_state_r_valid:tx_state_r_valid))begin
    cfg_resp_valid<=1;cfg_resp_error<=saved_word>=4 || (saved_bank?rx_state_r_error:tx_state_r_error);
    cfg_resp_data<=saved_bank?(rx_state_data>>(saved_word*32)):(tx_state_data>>(saved_word*32));bus_state<=B_IDLE;
   end
   if(bus_state==B_SEQUENCE && (saved_bank?seq_rx_r_valid:seq_tx_r_valid))begin
    cfg_resp_valid<=1;cfg_resp_error<=saved_bank?(saved_word>13 || seq_rx_error):(saved_word>10 || seq_tx_error);
    if(saved_bank)begin
     if(saved_word<8)cfg_resp_data<=rm_record[(saved_word-4)*32+:32];
     else cfg_resp_data<=rm_counts[(saved_word-8)*32+:32];
    end else if(saved_word==4)cfg_resp_data<=seq_tx_word;
    else cfg_resp_data<=seq_tx_counts[(saved_word-5)*32+:32];
    bus_state<=B_IDLE;
   end
   if(bus_state==B_STATS && stats_result_valid)begin cfg_resp_valid<=1;cfg_resp_error<=stats_result_error || saved_bad_index;cfg_resp_data<=saved_bad_index?32'd0:stats_result_data;bus_state<=B_IDLE;end
  end
 end
 assign management_max=active_mgmt_max;
endmodule
