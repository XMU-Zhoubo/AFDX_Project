// C20 integration boundary: 128 TX / 4096 RX configurations, bounded shared
// pools and TWO actual full-duplex GMII MACs. Not the final AFDX_top pinout.
module loading_system_top #(
 parameter [31:0] TFTP_RTO_MIN=32'd100000000,TFTP_RTO_MAX=32'd800000000,TFTP_DALLY=32'd1600000000,
 parameter [3:0] TFTP_RETRIES=4'd5
) (
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
 output wire cfg_ready,output wire cfg_resp_valid,input wire cfg_resp_ready,
 output wire cfg_resp_error,output wire [31:0] cfg_resp_data,
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
 output wire [7:0] store_tx_data,output wire store_tx_valid,store_tx_last,input wire store_tx_ready,
 input wire [7:0] store_rx_data,input wire store_rx_valid,store_rx_last,output wire store_rx_ready,store_cancel,
 output wire [7:0] events,output wire line_management

);

 // C30 time register bank is kind3/index3, word={bank,shadow,index[8:4],word}.
 // Compact public pins reuse the existing 32-bit config request/response bus.
 // C36 ODD controller, one added data WRQ context; existing writer sends LNS/LNL.
 wire dn_select=cfg_kind==3 && cfg_index[3:0]==9;reg dn_owned,dn_denied_owned;
 wire dn_busy,dn_h_ready,dn_h_result,dn_h_error;wire [31:0] dn_h_data;
 wire dn_denied=dn_busy && cfg_write && cfg_kind==3 && (cfg_index[3:0]==8 || cfg_index[3:0]==7 || cfg_index[3:0]==5 || cfg_index[3:0]==6 || (cfg_index[3:0]==4 && {cfg_index[9:4],cfg_word}!=10'd18 && {cfg_index[9:4],cfg_word}!=10'd22));
 wire dn_lno_allowed,dn_lna_allowed,dn_network,dn_lno_complete,dn_lna_complete,dn_lno_network;
 wire [47:0] dn_mac,dn_lno_mac;wire [31:0] dn_ip,dn_lno_ip;wire [15:0] dn_lna_size;
 wire dn_notice_owned,dn_c_valid,dn_c_write,dn_c_take;wire [3:0] dn_notice_object;
 wire [9:0] dn_c_address;wire [31:0] dn_c_data;
 wire dn_context_ready,dn_rx_ready,dn_rx_release;
 wire dt_cmd,dt_cmd_ready,dt_network,dt_valid,dt_ready,dt_last,dt_done,dt_error;
 wire [47:0] dt_mac;wire [31:0] dt_ip;wire [15:0] dt_port,dt_source;wire [9:0] dt_length;wire [7:0] dt_data;
 wire dn_req,dn_req_ready,dn_valid,dn_last,dn_sready,dn_result,dn_take,dn_read_ready,dn_cancel,dn_final;
 wire [2:0] dn_op;wire [3:0] dn_object;wire [16:0] dn_offset;wire [9:0] dn_length;wire [7:0] dn_data;

 wire up_select=cfg_kind==3 && cfg_index[3:0]==8;reg up_owned;wire up_ready,up_result,up_error;wire [31:0] up_rdata;
 // C35 separate read-client and immutable status writer contexts.
 wire upload_busy,lur_allowed,lur_complete,upload_net;wire [15:0] lur_size,init_serial;
 wire init_peer_net;wire [47:0] init_peer_mac,upload_mac;wire [31:0] init_peer_ip,upload_ip;
 wire rr_start,rr_start_ready,rr_busy,rr_result,rr_take,rr_cancel;wire [7:0] rr_reason;
 wire [15:0] rr_bytes,rr_crc16;wire [31:0] rr_crc32,rr_seed,rr_retrans,rr_blocks,rr_ignored;
 wire [255:0] rr_name;wire [5:0] rr_nl;wire [2:0] rr_object;
 wire rr_context_ready,rr_rx_ready,rr_release;
 wire rt_cmd,rt_cmd_ready,rt_network,rt_valid,rt_ready,rt_last,rt_done,rt_error;
 wire [47:0] rt_mac;wire [31:0] rt_ip;wire [15:0] rt_port,rt_source;wire [9:0] rt_length;wire [7:0] rt_data;
 wire rr_req,rr_req_ready,rr_store_valid,rr_store_last,rr_store_ready,rr_store_result,rr_store_take,rr_store_cancel,rr_final;
 wire [2:0] rr_op,rr_store_object;wire [15:0] rr_offset;wire [9:0] rr_length;wire [7:0] rr_data;
 wire ur_req,ur_ready,ur_read_ready,ur_result,ur_take,ur_cancel,ur_final;
 wire [2:0] ur_op,ur_object;wire [15:0] ur_offset;wire [9:0] ur_length;
 wire notice_start,notice_ready,notice_busy,notice_result,notice_take,notice_cancel,notice_owned;
 wire [7:0] notice_reason;wire [15:0] notice_serial,notice_status;wire [6:0] notice_ratio;
 wire [255:0] notice_name,notice_pn;wire [5:0] notice_nl,notice_pl;wire [31:0] notice_deadline;
 wire nc_valid,nc_write,nc_take;wire [9:0] nc_address;wire [31:0] nc_data;
 wire nr_req,nr_ready,nr_valid,nr_last,nr_data_ready,nr_result,nr_take,nr_cancel;
 wire [2:0] nr_op;wire [9:0] nr_length;wire [7:0] nr_data;
 wire time_select=cfg_kind==3 && cfg_index[3:0]==3;
 wire init_client_owned,initialization_busy,initialization_complete,control_available,control_accepted,init_storage_locked,init_storage_leased,bridge_cancel;
 wire initialization_select=cfg_kind==3 && cfg_index[3:0]==7;reg initialization_owned;
 wire initialization_ready,initialization_result,initialization_error;wire [31:0] initialization_rdata;
 wire writer_select=cfg_kind==3 && cfg_index[3:0]==6;reg writer_owned;
 wire wc_busy,control_busy,server_busy,wc_h_ready,wc_h_result,wc_h_error;wire [31:0] wc_h_data;
 wire control_select=cfg_kind==3 && cfg_index[3:0]==5;
 wire control_ready,control_result,control_error;wire [31:0] control_rdata;reg control_owned;
 wire load_select=cfg_kind==3 && cfg_index[3:0]==4;
 wire load_ready,load_result_valid,load_error;wire [31:0] load_rdata;
 reg load_owned;
 wire [9:0] load_address={cfg_index[9:4],cfg_word};
 reg host_busy;wire host_request=cfg_valid && !host_busy && !dn_denied;
 wire time_valid=host_request && time_select,time_write=cfg_write;
 wire [7:0] time_address={cfg_index[7:4],cfg_word};wire [31:0] time_wdata=cfg_data;
 wire time_ready,time_result_valid,time_result_error;wire [31:0] time_rdata;
 reg time_owned;wire time_result_ready=cfg_resp_ready && time_owned;
 wire legacy_ready,legacy_result_valid,legacy_result_error;wire [31:0] legacy_result_data;
 wire time_sample_valid,time_trace_valid;wire [2:0] time_trace_kind;wire [31:0] time_trace_tick;
 assign cfg_ready=!host_busy && (dn_denied?1'b1:dn_select?dn_h_ready:up_select?up_ready:initialization_select?(!upload_busy && initialization_ready):writer_select?(!init_client_owned && !notice_owned && !dn_notice_owned && wc_h_ready):control_select?control_ready:load_select?(load_ready && !bridge_cancel && (!(init_storage_locked || upload_busy) || load_address<32)):time_select?time_ready:legacy_ready);
 assign cfg_resp_valid=host_busy && (dn_denied_owned?1'b1:dn_owned?dn_h_result:up_owned?up_result:initialization_owned?initialization_result:writer_owned?wc_h_result:control_owned?control_result:load_owned?load_result_valid:time_owned?time_result_valid:legacy_result_valid);
 assign cfg_resp_error=dn_denied_owned?1'b1:dn_owned?dn_h_error:up_owned?up_error:initialization_owned?initialization_error:writer_owned?wc_h_error:control_owned?control_error:load_owned?load_error:time_owned?time_result_error:legacy_result_error;
 assign cfg_resp_data=dn_denied_owned?32'd0:dn_owned?dn_h_data:up_owned?up_rdata:initialization_owned?initialization_rdata:writer_owned?wc_h_data:control_owned?control_rdata:load_owned?load_rdata:time_owned?time_rdata:legacy_result_data;
 always @(posedge clk)if(!rst_n)begin dn_owned<=0;dn_denied_owned<=0;up_owned<=0;initialization_owned<=0;writer_owned<=0;control_owned<=0;time_owned<=0;load_owned<=0;host_busy<=0;end
 else begin
  if(cfg_resp_valid && cfg_resp_ready)host_busy<=0;
  if(cfg_valid && cfg_ready)begin dn_owned<=dn_select;dn_denied_owned<=dn_denied;up_owned<=up_select;initialization_owned<=initialization_select;writer_owned<=writer_select;control_owned<=control_select;time_owned<=time_select;load_owned<=load_select;host_busy<=1;end
 end
 wire [31:0] time_timeout,time_rate;
 // Public host interface is unchanged. The agent arbitrates real kind2 reads;
 // neither the testbench nor this wrapper synthesizes a counter answer.
 wire c_valid,c_write,c_bank,c_shadow,c_ready,c_result_valid,c_result_ready,c_result_error;
 wire [1:0] c_kind;wire [12:0] c_index;wire [3:0] c_word;wire [31:0] c_data,c_result_data;
 wire stat_valid,stat_write,stat_ready,stat_result_valid,stat_result_ready,stat_result_error;
 wire [12:0] stat_index;wire [31:0] stat_data;wire [1:0] stat_kind;wire stat_bank;wire [3:0] stat_word;
 wire lock_valid,lock_write,lock_ready,lock_error,lock_release;
 wire a_commit_valid,a_commit_ready,a_result_valid,a_result_ready,a_result_ok;wire [2:0] a_result_code;
 wire c_commit_valid,c_commit_ready,c_commit_result_valid,c_commit_result_ready,c_commit_result_ok,c_budget_only;
 wire [2:0] c_commit_result_code;wire [15:0] budget_version;wire [127:0] set_values;
 wire [15:0] management_rx_data,active_mgmt_max;wire [1:0] management_rx_valid,management_rx_ready,management_rx_sop,management_rx_last,management_rx_error;
 wire [1:0] management_select;
 wire queue_cmd_valid,queue_cmd_ready,queue_valid,queue_ready,queue_last,queue_commit,queue_commit_ready,queue_abort,queue_error_valid,queue_error_ready;
 wire [15:0] queue_length;wire [7:0] queue_data;wire [2:0] queue_error_code;
 wire [7:0] merged_data;wire merged_valid,merged_ready,merged_sop,merged_last,merged_error,merged_network;
 wire context_valid,context_ready,context_network,rx_valid,rx_ready,rx_last,rx_release,rx_idle;
 wire [47:0] context_mac;wire [31:0] context_ip;wire [15:0] context_port;wire [9:0] context_length;
 wire [7:0] rx_data;wire [31:0] rx_good,rx_bad,rx_busy;wire [3:0] rx_reason;
 wire tx_context_valid,tx_context_ready,tx_network,tx_valid,tx_ready,tx_last,tx_done_valid,tx_done_ready,tx_done_error;
 wire [47:0] tx_mac;wire [31:0] tx_ip;wire [15:0] tx_port;wire [9:0] tx_length;wire [7:0] tx_data;
 wire agent_cmd_valid,agent_cmd_ready,agent_valid,agent_ready,agent_last,agent_commit,agent_commit_ready,agent_abort,agent_error_valid,agent_error_ready;
 wire [15:0] agent_length;wire [1:0] agent_network;wire [7:0] agent_data;
 wire [351:0] agent_diagnostics;
 wire [1:0] trap_faults;wire [31:0] trap_total,trap_snapshot,trap_ticks;wire [15:0] trap_used,trap_occupancy;
 wire trap_valid,trap_ready,trap_result_valid,trap_result_error,tx_is_trap,core_line_complete;
 wire [511:0] trap_diagnostics;wire [3:0] trap_result_reason;reg response_is_trap,line_is_trap;reg line_is_tftp;

 wire [63:0] rtc_seconds;wire [31:0] rtc_nanoseconds,time_now,time_generation;
 wire time_start,time_start_ready,time_cancel,time_basis_changed,time_coarse,rearm,sample_take;
 wire [31:0] time_id,time_sample_word;wire [4:0] sample_index;
 wire client_idle;wire [31:0] ignored_count,timeout_count,sample_count,commit_count;
 wire [7:0] udp_data;wire udp_snmp_valid,udp_time_valid,udp_snmp_ready,udp_time_ready,udp_sop,udp_last,udp_error,udp_network;
 wire [63:0] stamp_seconds,context_seconds;wire [31:0] stamp_nanoseconds,stamp_tick,stamp_generation,context_nanoseconds,context_tick,context_generation;
 wire tr_context_valid,tr_context_ready,tr_network,tr_valid,tr_ready,tr_last,tr_release;
 wire [47:0] tr_mac;wire [31:0] tr_ip;wire [15:0] tr_port;wire [9:0] tr_length;wire [7:0] tr_data;
 wire tt_cmd,tt_cmd_ready,tt_valid,tt_ready,tt_last,tt_done,tt_done_error;wire [7:0] tt_data;
 wire tm_cmd,tm_cmd_ready,tm_valid,tm_ready,tm_last,tm_commit,tm_commit_ready,tm_abort,tm_error,tm_error_ready;
 wire [15:0] tm_length;wire [1:0] tm_network;wire [7:0] tm_data;
 wire cm_cmd,cm_cmd_ready,cm_valid,cm_ready,cm_last,cm_commit,cm_commit_ready,cm_abort,cm_error,cm_error_ready;
 wire [15:0] cm_length;wire [1:0] cm_network;wire [7:0] cm_data;
 wire [31:0] tr_good,tr_bad,tr_busy;wire [3:0] tr_reason;
 wire [7:0] post_data;wire post_valid,post_ready,post_sop,post_last,post_error,post_network;
 wire lf_rx_valid,lf_rx_ready,lf_context,lf_context_ready,lf_network,lf_valid,lf_ready,lf_last,lf_release;
 wire [7:0] lf_data;wire [47:0] lf_mac;wire [31:0] lf_ip;wire [15:0] lf_port,lf_destination;wire [9:0] lf_length;
 wire [31:0] lf_good,lf_bad,lf_busy;wire [3:0] lf_reason;
 wire lt_cmd,lt_cmd_ready,lt_network,lt_valid,lt_ready,lt_last,lt_done,lt_error;
 wire [47:0] lt_mac;wire [31:0] lt_ip;wire [15:0] lt_port,lt_source;wire [9:0] lt_length;wire [7:0] lt_data;
 wire lm_cmd,lm_cmd_ready,lm_valid,lm_ready,lm_last,lm_commit,lm_commit_ready,lm_abort,lm_error,lm_error_ready;
 wire [15:0] lm_length;wire [1:0] lm_network;wire [7:0] lm_data;
 wire am_cmd,am_cmd_ready,am_valid,am_ready,am_last,am_commit,am_commit_ready,am_abort,am_error,am_error_ready;
 wire [15:0] am_length;wire [1:0] am_network;wire [7:0] am_data;
 wire sr_valid,sr_ready,sd_valid,sd_ready,sd_last,sresult,sresult_ready,serror,scancel,load_cancel;
 wire [2:0] sr_op;wire [15:0] sr_offset,sr_size;wire [7:0] sr_flags,rd_data;wire rd_valid,rd_last,rd_ready;wire [9:0] sr_length;wire sr_final;wire [7:0] sd_data;
 wire [511:0] load_diagnostics;wire [31:0] load_timeout;

 rtc_sync_control time_bus(.clk(clk),.rst_n(rst_n),.h_valid(time_valid),.h_write(time_write),.h_address(time_address),.h_data(time_wdata),.h_ready(time_ready),
  .h_result_valid(time_result_valid),.h_result_ready(time_result_ready),.h_error(time_result_error),.h_result(time_rdata),
  .timeout_cycles(time_timeout),.rate_cycles(time_rate),.rtc_seconds(rtc_seconds),.rtc_nanoseconds(rtc_nanoseconds),.now(time_now),.generation(time_generation),.basis_changed(time_basis_changed),.coarse_valid(time_coarse),
  .start(time_start),.start_ready(time_start_ready),.transaction(time_id),.cancel(time_cancel),.rearm(rearm),
  .sample_valid(time_sample_valid),.sample_take(sample_take),.sample_index(sample_index),.sample_word(time_sample_word),.client_idle(client_idle),
  .ignored_count(ignored_count),.timeout_count(timeout_count),.sample_count(sample_count),.commit_count(commit_count),.rx_bad_count(tr_bad),.rx_good_count(tr_good),.rx_busy_count(tr_busy),.rx_reason(tr_reason));
 time_port_demux time_split(.clk(clk),.rst_n(rst_n),.s_data(merged_data),.s_valid(merged_valid),.s_ready(merged_ready),.s_sop(merged_sop),.s_last(merged_last),.s_error(merged_error),.s_network(merged_network),
  .rtc_seconds(rtc_seconds),.rtc_nanoseconds(rtc_nanoseconds),.now(time_now),.generation(time_generation),
  .m_data(udp_data),.m_sop(udp_sop),.m_last(udp_last),.m_error(udp_error),.m_network(udp_network),.snmp_valid(post_valid),.snmp_ready(post_ready),.time_valid(udp_time_valid),.time_ready(udp_time_ready),
  .stamp_seconds(stamp_seconds),.stamp_nanoseconds(stamp_nanoseconds),.stamp_tick(stamp_tick),.stamp_generation(stamp_generation));
 download_port_demux load_split(.clk(clk),.rst_n(rst_n),.s_data(udp_data),.s_valid(post_valid),.s_ready(post_ready),.s_sop(udp_sop),.s_last(udp_last),.s_error(udp_error),.s_network(udp_network),
  .m_data(post_data),.m_sop(post_sop),.m_last(post_last),.m_error(post_error),.m_network(post_network),.snmp_valid(udp_snmp_valid),.snmp_ready(udp_snmp_ready),.time_valid(lf_rx_valid),.time_ready(lf_rx_ready),.unused_stamp());
 download_udp_rx load_endpoint(.clk(clk),.rst_n(rst_n),.s_data(post_data),.s_valid(lf_rx_valid),.s_ready(lf_rx_ready),.s_sop(post_sop),.s_last(post_last),.s_error(post_error),.s_network(post_network),
  .context_valid(lf_context),.context_ready(lf_context_ready),.context_network(lf_network),.context_mac(lf_mac),.context_ip(lf_ip),.context_port(lf_port),.context_destination(lf_destination),.context_length(lf_length),
  .m_data(lf_data),.m_valid(lf_valid),.m_ready(lf_ready),.m_last(lf_last),.release_valid(lf_release),.count_good(lf_good),.count_bad(lf_bad),.count_busy(lf_busy),.last_reason(lf_reason),.idle());
 // C34 dedicated initialization CSR bank7. Bank5 remains manual LUI/LUR.
 
 
 wire ic_h_valid,ic_h_write,ic_h_take;wire [9:0] ic_h_address;wire [31:0] ic_h_data;
 wire ir_req,ir_ready,ir_valid,ir_last,ir_data_ready,ir_result,ir_result_ready,ir_cancel;
 wire [2:0] ir_op;wire [9:0] ir_length;wire [7:0] ir_data;
 wire lui_complete,lui_network;wire [47:0] lui_mac;wire [31:0] lui_ip;
 upload_initialization initialization(.clk(clk),.rst_n(rst_n),.now(time_now),
  .control_available(control_available),.control_accepted(control_accepted),.control_busy(control_busy),.server_busy(server_busy),.writer_busy(wc_busy),
  .lui_complete(lui_complete),.lui_network(lui_network),.lui_mac(lui_mac),.lui_ip(lui_ip),
  .h_valid(host_request && initialization_select),.h_write(cfg_write),.h_address(load_address),.h_data(cfg_data),.h_ready(initialization_ready),
  .h_result_valid(initialization_result),.h_result_ready(cfg_resp_ready && initialization_owned),.h_error(initialization_error),.h_result(initialization_rdata),
  .client_owned(init_client_owned),.client_valid(ic_h_valid),.client_write(ic_h_write),.client_address(ic_h_address),.client_data(ic_h_data),
  .client_ready(wc_h_ready),.client_result_valid(wc_h_result),.client_error(wc_h_error),.client_result(wc_h_data),.client_result_ready(ic_h_take),
  .req_valid(ir_req),.req_ready(ir_ready),.req_op(ir_op),.req_length(ir_length),.s_data(ir_data),.s_valid(ir_valid),.s_last(ir_last),.s_ready(ir_data_ready),
  .result_valid(ir_result),.result_error(serror),.result_ready(ir_result_ready),.cancel(ir_cancel),.busy(initialization_busy),.initialization_complete(initialization_complete),.serial_value(init_serial),.peer_network(init_peer_net),.loader_mac(init_peer_mac),.loader_ip(init_peer_ip),.storage_locked(init_storage_locked),.storage_leased(init_storage_leased));
 // C34 transparent active writer, independent of the unresolved LUS format.
 wire wc_req,wc_req_ready,wc_object,wc_read_valid,wc_read_last,wc_read_ready,wc_result,wc_result_ready,wc_cancel;
 wire [2:0] wc_op;wire [15:0] wc_offset;wire [9:0] wc_length;wire [7:0] wc_read_data;
 wire server_context_ready,server_rx_ready,server_release,wc_context_ready,wc_rx_ready,wc_release;
 wire destination_download=lf_destination>=35000 && lf_destination<=39999;
 wire destination_client=lf_destination>=45001 && lf_destination<=49151;
 wire destination_reader=lf_destination>=40000 && lf_destination<=44999;
 assign lf_context_ready=destination_download?dn_context_ready:destination_reader?rr_context_ready:destination_client?wc_context_ready:server_context_ready;
 assign lf_ready=destination_download?dn_rx_ready:destination_reader?rr_rx_ready:destination_client?wc_rx_ready:server_rx_ready;
 assign lf_release=destination_download?dn_rx_release:destination_reader?rr_release:destination_client?wc_release:server_release;
 wire wt_cmd,wt_cmd_ready,wt_network,wt_valid,wt_ready,wt_last,wt_done,wt_error;
 wire [47:0] wt_mac;wire [31:0] wt_ip;wire [15:0] wt_port,wt_source;wire [9:0] wt_length;wire [7:0] wt_data;
 wire out_cmd,out_cmd_ready,out_network,out_valid,out_ready,out_last,out_done,out_error;
 wire [47:0] out_mac;wire [31:0] out_ip;wire [15:0] out_port,out_source;wire [9:0] out_length;wire [7:0] out_data;
 reg [1:0] encoder_state,encoder_owner,line_owner;reg [1:0] encoder_round;
 wire [3:0] tx_requests={dt_cmd,rt_cmd,wt_cmd,lt_cmd};reg [1:0] choice;
 always @* begin
  case(encoder_round)
   0:choice=lt_cmd?0:wt_cmd?1:rt_cmd?2:3;
   1:choice=wt_cmd?1:rt_cmd?2:dt_cmd?3:0;
   2:choice=rt_cmd?2:dt_cmd?3:lt_cmd?0:1;
   default:choice=dt_cmd?3:lt_cmd?0:wt_cmd?1:2;
  endcase
 end
 reg [31:0] load_submit_count,load_client_count,load_line_count,load_accept_context,load_accept_tick;
 always @(posedge clk)begin
  if(!rst_n)begin load_submit_count<=0;load_client_count<=0;load_line_count<=0;load_accept_context<=0;load_accept_tick<=0;end
  else begin
   if(out_cmd && out_cmd_ready)begin load_submit_count<=load_submit_count+1'b1;load_accept_context<={13'd0,encoder_owner,out_network,out_source};load_accept_tick<=time_now;end
   if(encoder_state==2 && out_done && !out_error)load_client_count<=load_client_count+1'b1;
   if(core_line_complete && line_is_tftp)load_line_count<=load_line_count+1'b1;
  end
 end
 always @(posedge clk)begin
  if(!rst_n)begin encoder_state<=0;encoder_owner<=0;encoder_round<=0;line_owner<=0;end
  else begin
   case(encoder_state)
    0:if(|tx_requests)begin encoder_owner<=choice;encoder_state<=1;end
    1:if(out_cmd && out_cmd_ready)encoder_state<=2;
    2:if(out_done)begin encoder_state<=0;encoder_round<=encoder_owner==3?0:encoder_owner+1'b1;end
   endcase
   if(queue_cmd_valid && queue_cmd_ready && lm_cmd && lm_cmd_ready)line_owner<=encoder_owner;
  end
 end
 assign out_cmd=encoder_state==1 && (encoder_owner==0?lt_cmd:encoder_owner==1?wt_cmd:encoder_owner==2?rt_cmd:dt_cmd);
 assign out_network=(encoder_owner==0?lt_network:encoder_owner==1?wt_network:encoder_owner==2?rt_network:dt_network);
 assign out_mac=(encoder_owner==0?lt_mac:encoder_owner==1?wt_mac:encoder_owner==2?rt_mac:dt_mac);
 assign out_ip=(encoder_owner==0?lt_ip:encoder_owner==1?wt_ip:encoder_owner==2?rt_ip:dt_ip);
 assign out_port=(encoder_owner==0?lt_port:encoder_owner==1?wt_port:encoder_owner==2?rt_port:dt_port);
 assign out_source=(encoder_owner==0?lt_source:encoder_owner==1?wt_source:encoder_owner==2?rt_source:dt_source);
 assign out_length=(encoder_owner==0?lt_length:encoder_owner==1?wt_length:encoder_owner==2?rt_length:dt_length);
 assign out_data=(encoder_owner==0?lt_data:encoder_owner==1?wt_data:encoder_owner==2?rt_data:dt_data);
 assign out_valid=encoder_state==2 && (encoder_owner==0?lt_valid:encoder_owner==1?wt_valid:encoder_owner==2?rt_valid:dt_valid);
 assign out_last=(encoder_owner==0?lt_last:encoder_owner==1?wt_last:encoder_owner==2?rt_last:dt_last);
 assign lt_cmd_ready=encoder_state==1 && encoder_owner==0 && out_cmd_ready;
 assign lt_ready=encoder_state==2 && encoder_owner==0 && out_ready;
 assign lt_done=encoder_state==2 && encoder_owner==0 && out_done;
 assign lt_error=out_error;
 assign wt_cmd_ready=encoder_state==1 && encoder_owner==1 && out_cmd_ready;
 assign wt_ready=encoder_state==2 && encoder_owner==1 && out_ready;
 assign wt_done=encoder_state==2 && encoder_owner==1 && out_done;
 assign wt_error=out_error;
 assign rt_cmd_ready=encoder_state==1 && encoder_owner==2 && out_cmd_ready;
 assign rt_ready=encoder_state==2 && encoder_owner==2 && out_ready;
 assign rt_done=encoder_state==2 && encoder_owner==2 && out_done;
 assign rt_error=out_error;
 assign dt_cmd_ready=encoder_state==1 && encoder_owner==3 && out_cmd_ready;
 assign dt_ready=encoder_state==2 && encoder_owner==3 && out_ready;
 assign dt_done=encoder_state==2 && encoder_owner==3 && out_done;assign dt_error=out_error;
 tftp_write_client #(.RTO_MIN(TFTP_RTO_MIN),.RTO_MAX(TFTP_RTO_MAX),.RETRY_LIMIT(TFTP_RETRIES)) writer(
  .clk(clk),.rst_n(rst_n),.now(time_now),.timeout_cycles(load_timeout),.start_blocked((server_busy && !notice_owned && !dn_notice_owned) || control_busy),
  .h_valid(init_client_owned?ic_h_valid:notice_owned?nc_valid:dn_notice_owned?dn_c_valid:host_request && writer_select),.h_write(init_client_owned?ic_h_write:notice_owned?nc_write:dn_notice_owned?dn_c_write:cfg_write),.h_address(init_client_owned?ic_h_address:notice_owned?nc_address:dn_notice_owned?dn_c_address:load_address),.h_data(init_client_owned?ic_h_data:notice_owned?nc_data:dn_notice_owned?dn_c_data:cfg_data),.h_ready(wc_h_ready),
  .h_result_valid(wc_h_result),.h_result_ready(ic_h_take || nc_take || dn_c_take || (cfg_resp_ready && writer_owned && host_busy)),.h_error(wc_h_error),.h_result(wc_h_data),.busy(wc_busy),
  .rx_context_valid(lf_context && destination_client),.rx_context_ready(wc_context_ready),.rx_network(lf_network),.rx_mac(lf_mac),.rx_ip(lf_ip),.rx_port(lf_port),.rx_destination(lf_destination),.rx_length(lf_length),
  .rx_data(lf_data),.rx_valid(lf_valid && destination_client),.rx_last(lf_last),.rx_ready(wc_rx_ready),.rx_release(wc_release),
  .tx_cmd_valid(wt_cmd),.tx_cmd_ready(wt_cmd_ready),.tx_network(wt_network),.tx_mac(wt_mac),.tx_ip(wt_ip),.tx_port(wt_port),.tx_source(wt_source),.tx_length(wt_length),
  .tx_data(wt_data),.tx_valid(wt_valid),.tx_last(wt_last),.tx_ready(wt_ready),.tx_done(wt_done),.tx_error(wt_error),.tx_line_done(core_line_complete && line_is_tftp && line_owner==1),
  .store_req_valid(wc_req),.store_req_ready(wc_req_ready),.store_op(wc_op),.store_object(wc_object),.store_offset(wc_offset),.store_length(wc_length),
  .store_size(sr_size),.store_flags(sr_flags),.store_data(wc_read_data),.store_valid(wc_read_valid),.store_last(wc_read_last),.store_ready(wc_read_ready),
  .store_result_valid(wc_result),.store_result_ready(wc_result_ready),.store_error(serror),.store_cancel(wc_cancel));
 // C35 independent objects, shared tagged adapter and operation ownership.
 wire [3:0] server_object,bridge_object;wire [16:0] bridge_size;assign sr_size=bridge_size[15:0];wire bridge_req,bridge_ready,bridge_valid,bridge_last,bridge_data_ready,bridge_result,bridge_result_ready;
 wire [2:0] bridge_op;wire [16:0] bridge_offset;wire [9:0] bridge_length;wire bridge_final;wire [7:0] bridge_data;
 wire cr_req,cr_ready,cr_valid,cr_ready_data,cr_last,cr_result,cr_result_ready,cr_cancel,init_complete;
 wire [2:0] cr_op;wire [9:0] cr_length;wire [7:0] cr_data;
 wire [7:0] bridge_read_data;wire bridge_read_valid,bridge_read_last,bridge_read_ready;
 reg [2:0] storage_owner;reg storage_owned;wire [2:0] storage_choice;
 assign storage_choice=dn_req?3'd7:ir_req?3'd3:nr_req?3'd5:ur_req?3'd6:cr_req?3'd1:sr_valid?3'd0:wc_req?3'd2:3'd4;
 assign bridge_req=dn_req || (!ir_cancel && (ir_req || (!init_storage_locked && (nr_req || ur_req || cr_req || sr_valid || wc_req || rr_req))));
 assign bridge_object=dn_req?dn_object:ir_req?3'd2:nr_req?3'd2:ur_req?ur_object:cr_req?3'd1:sr_valid?server_object:wc_req?(dn_notice_owned?dn_notice_object:init_client_owned || notice_owned?4'd2:{3'd0,wc_object}):rr_store_object;
 assign bridge_op=dn_req?dn_op:ir_req?ir_op:nr_req?nr_op:ur_req?ur_op:cr_req?cr_op:sr_valid?sr_op:wc_req?wc_op:rr_op;
 assign bridge_offset=dn_req?dn_offset:ir_req?16'd0:nr_req?16'd0:ur_req?ur_offset:cr_req?16'd0:sr_valid?sr_offset:wc_req?wc_offset:rr_offset;
 assign bridge_length=dn_req?dn_length:ir_req?ir_length:nr_req?nr_length:ur_req?ur_length:cr_req?cr_length:sr_valid?sr_length:wc_req?wc_length:rr_length;
 assign bridge_final=dn_req?dn_final:ir_req?1'b1:nr_req?1'b1:ur_req?ur_final:cr_req?1'b1:sr_valid?sr_final:wc_req?1'b0:rr_final;
 assign ir_ready=bridge_ready && bridge_req && storage_choice==3'd3;
 assign ir_result=bridge_result && storage_owned && storage_owner==3'd3;
 assign ir_data_ready=bridge_data_ready && storage_owned && storage_owner==3'd3;
 assign nr_ready=bridge_ready && bridge_req && storage_choice==3'd5;
 assign nr_result=bridge_result && storage_owned && storage_owner==3'd5;
 assign nr_data_ready=bridge_data_ready && storage_owned && storage_owner==3'd5;
 assign ur_ready=bridge_ready && bridge_req && storage_choice==3'd6;
 assign ur_result=bridge_result && storage_owned && storage_owner==3'd6;
 assign cr_ready=bridge_ready && bridge_req && storage_choice==3'd1;
 assign cr_result=bridge_result && storage_owned && storage_owner==3'd1;
 assign cr_ready_data=bridge_data_ready && storage_owned && storage_owner==3'd1;
 assign sr_ready=bridge_ready && bridge_req && storage_choice==3'd0;
 assign sresult=bridge_result && storage_owned && storage_owner==3'd0;
 assign sd_ready=bridge_data_ready && storage_owned && storage_owner==3'd0;
 assign wc_req_ready=bridge_ready && bridge_req && storage_choice==3'd2;
 assign wc_result=bridge_result && storage_owned && storage_owner==3'd2;
 assign rr_req_ready=bridge_ready && bridge_req && storage_choice==3'd4;
 assign rr_store_result=bridge_result && storage_owned && storage_owner==3'd4;
 assign rr_store_ready=bridge_data_ready && storage_owned && storage_owner==3'd4;
 assign bridge_data=storage_owner==3'd7 ? dn_data:storage_owner==3'd3 ? ir_data:storage_owner==3'd5 ? nr_data:storage_owner==3'd6 ? 8'd0:storage_owner==3'd1 ? cr_data:storage_owner==3'd0 ? sd_data:storage_owner==3'd2 ? 8'd0:rr_data;
 assign bridge_valid=storage_owner==3'd7 ? dn_valid:storage_owner==3'd3 ? ir_valid:storage_owner==3'd5 ? nr_valid:storage_owner==3'd6 ? 1'b0:storage_owner==3'd1 ? cr_valid:storage_owner==3'd0 ? sd_valid:storage_owner==3'd2 ? 1'b0:rr_store_valid;
 assign bridge_last=storage_owner==3'd7 ? dn_last:storage_owner==3'd3 ? ir_last:storage_owner==3'd5 ? nr_last:storage_owner==3'd6 ? 1'b0:storage_owner==3'd1 ? cr_last:storage_owner==3'd0 ? sd_last:storage_owner==3'd2 ? 1'b0:rr_store_last;
 assign bridge_result_ready=storage_owner==3'd7 ? dn_take:storage_owner==3'd3 ? ir_result_ready:storage_owner==3'd5 ? nr_take:storage_owner==3'd6 ? ur_take:storage_owner==3'd1 ? cr_result_ready:storage_owner==3'd0 ? sresult_ready:storage_owner==3'd2 ? wc_result_ready:rr_store_take;
 assign bridge_read_ready=storage_owner==3'd7 ? dn_read_ready:storage_owner==3'd3 ? 1'b0:storage_owner==3'd5 ? 1'b0:storage_owner==3'd6 ? ur_read_ready:storage_owner==3'd1 ? 1'b0:storage_owner==3'd0 ? rd_ready:storage_owner==3'd2 ? wc_read_ready:1'b0;
 assign bridge_cancel=(storage_owned && storage_owner==7 && dn_cancel) || (ir_cancel && init_storage_leased) || (storage_owned && ((storage_owner==3'd3 && ir_cancel) || (storage_owner==3'd5 && nr_cancel) || (storage_owner==3'd6 && ur_cancel) || (storage_owner==3'd1 && cr_cancel) || (storage_owner==3'd0 && scancel) || (storage_owner==3'd2 && wc_cancel) || (storage_owner==3'd4 && rr_store_cancel)));
 always @(posedge clk)begin
  if(!rst_n)begin storage_owner<=0;storage_owned<=0;end
  else begin
   if((bridge_result && bridge_result_ready) || bridge_cancel)storage_owned<=0;
   if(bridge_req && bridge_ready)begin storage_owner<=storage_choice;storage_owned<=1;end
  end
 end
 assign rd_data=bridge_read_data;assign rd_valid=bridge_read_valid && storage_owner==0;assign rd_last=bridge_read_last;
 assign wc_read_data=bridge_read_data;assign wc_read_valid=bridge_read_valid && storage_owner==2;assign wc_read_last=bridge_read_last;
  arinc615a_control control(.clk(clk),.rst_n(rst_n),.now(time_now),.server_active(server_busy || wc_busy || initialization_busy || upload_busy),.busy(control_busy),
   .h_valid(host_request && control_select),.h_write(cfg_write),.h_address(load_address),.h_data(cfg_data),.h_ready(control_ready),
   .h_result_valid(control_result),.h_result_ready(cfg_resp_ready && control_owned),.h_error(control_error),.h_result(control_rdata),
   .req_valid(cr_req),.req_ready(cr_ready),.req_op(cr_op),.req_length(cr_length),.s_data(cr_data),.s_valid(cr_valid),.s_last(cr_last),.s_ready(cr_ready_data),
   .result_valid(cr_result),.result_error(serror),.result_ready(cr_result_ready),.cancel(cr_cancel),.available(control_available),.accepted(control_accepted),.initialization_complete(init_complete));
 tftp_duplex_server #(.RTO_MIN(TFTP_RTO_MIN),.RTO_MAX(TFTP_RTO_MAX),.DALLY_TICKS(TFTP_DALLY),.RETRY_LIMIT(TFTP_RETRIES)) loader(.clk(clk),.rst_n(rst_n),.now(time_now),.timeout_cycles(load_timeout),.cancel(load_cancel),
  .rx_context_valid(lf_context && !destination_client && !destination_reader && !destination_download),.rx_context_ready(server_context_ready),.rx_network(lf_network),.rx_mac(lf_mac),.rx_ip(lf_ip),.rx_port(lf_port),.rx_destination(lf_destination),.rx_length(lf_length),
  .rx_data(lf_data),.rx_valid(lf_valid && !destination_client && !destination_reader && !destination_download),.rx_last(lf_last),.rx_ready(server_rx_ready),.rx_release(server_release),
  .tx_cmd_valid(lt_cmd),.tx_cmd_ready(lt_cmd_ready),.tx_network(lt_network),.tx_mac(lt_mac),.tx_ip(lt_ip),.tx_port(lt_port),.tx_source(lt_source),.tx_length(lt_length),.tx_data(lt_data),.tx_valid(lt_valid),.tx_last(lt_last),.tx_ready(lt_ready),.tx_done(lt_done),.tx_error(lt_error),.tx_line_done(core_line_complete && line_is_tftp && line_owner==0),
  .dn_allowed(dn_lno_allowed),.dn_lna_allowed(dn_lna_allowed),.dn_network(dn_network),.dn_mac(dn_mac),.dn_ip(dn_ip),.lno_complete(dn_lno_complete),.lno_network(dn_lno_network),.lno_mac(dn_lno_mac),.lno_ip(dn_lno_ip),.lna_complete(dn_lna_complete),.lna_size(dn_lna_size),.lur_allowed(lur_allowed),.expected_network(upload_net),.expected_mac(upload_mac),.expected_ip(upload_ip),.lur_complete(lur_complete),.lur_size(lur_size),.client_active(dn_busy || upload_busy || (wc_busy && !init_client_owned && !notice_owned)),.lui_complete(lui_complete),.lui_network(lui_network),.lui_mac(lui_mac),.lui_ip(lui_ip),.server_busy(server_busy),.store_object(server_object),.store_req_valid(sr_valid),.store_req_ready(sr_ready),.store_op(sr_op),.store_offset(sr_offset),.store_size(sr_size),.store_flags(sr_flags),.store_read_data(rd_data),.store_read_valid(rd_valid),.store_read_last(rd_last),.store_read_ready(rd_ready),.store_length(sr_length),.store_final(sr_final),.store_data(sd_data),.store_valid(sd_valid),.store_ready(sd_ready),.store_last(sd_last),
  .store_result_valid(sresult),.store_result_ready(sresult_ready),.store_error(serror),.store_cancel(scancel),.diagnostics(load_diagnostics));
 storage_epoch_if storage(.clk(clk),.rst_n(rst_n),.event_diagnostics({load_accept_tick,load_accept_context,load_line_count,load_client_count,load_submit_count}),.epoch_change_allowed(!dn_busy && !upload_busy && !rr_busy && !wc_busy && !initialization_busy && !server_busy && !control_busy && !notice_busy),.req_valid(bridge_req),.req_ready(bridge_ready),.req_op(bridge_op),.req_object(bridge_object),.req_offset(bridge_offset),.result_size(bridge_size),.result_flags(sr_flags),.m_data(bridge_read_data),.m_valid(bridge_read_valid),.m_last(bridge_read_last),.m_ready(bridge_read_ready),.req_length(bridge_length),.req_final(bridge_final),.s_data(bridge_data),.s_valid(bridge_valid),.s_last(bridge_last),.s_ready(bridge_data_ready),
  .result_valid(bridge_result),.result_ready(bridge_result_ready),.result_error(serror),.cancel(bridge_cancel),
  .h_valid(host_request && load_select && !bridge_cancel && (!(init_storage_locked || upload_busy) || load_address<32)),.h_write(cfg_write),.h_address(load_address),.h_data(cfg_data),.h_ready(load_ready),.h_result_valid(load_result_valid),.h_result_ready(cfg_resp_ready && load_owned),.h_error(load_error),.h_result(load_rdata),
  .diagnostics({load_diagnostics[511:64],lf_bad,lf_good}),.timeout_cycles(load_timeout),.cancel_request(load_cancel),
  .store_tx_data(store_tx_data),.store_tx_valid(store_tx_valid),.store_tx_last(store_tx_last),.store_tx_ready(store_tx_ready),.store_rx_data(store_rx_data),.store_rx_valid(store_rx_valid),.store_rx_last(store_rx_last),.store_rx_ready(store_rx_ready),.store_cancel(store_cancel));

 arinc615a_upload upload(.clk(clk),.rst_n(rst_n),.now(time_now),.initialized(initialization_complete),.init_network(init_peer_net),.init_mac(init_peer_mac),.init_ip(init_peer_ip),.init_serial(init_serial),
 .lur_complete(lur_complete),.lur_size(lur_size),.h_valid(host_request && up_select),.h_write(cfg_write),.h_address(load_address),.h_data(cfg_data),.h_ready(up_ready),
 .h_result_valid(up_result),.h_result_ready(cfg_resp_ready && up_owned),.h_error(up_error),.h_result(up_rdata),.busy(upload_busy),.accept_lur(lur_allowed),.loader_mac(upload_mac),.loader_ip(upload_ip),.loader_network(upload_net),
 .rr_start(rr_start),.rr_ready(rr_start_ready),.rr_busy(rr_busy),.rr_result(rr_result),.rr_reason(rr_reason),.rr_length(rr_bytes),.rr_crc16(rr_crc16),.rr_crc32(rr_crc32),.rr_take(rr_take),.rr_cancel(rr_cancel),
 .rr_filename(rr_name),.rr_name_length(rr_nl),.rr_object(rr_object),.rr_seed(rr_seed),
 .req_valid(ur_req),.req_ready(ur_ready),.req_op(ur_op),.req_object(ur_object),.req_offset(ur_offset),.req_length(ur_length),.req_final(ur_final),
 .read_data(bridge_read_data),.read_valid(bridge_read_valid && storage_owner==6),.read_last(bridge_read_last),.read_ready(ur_read_ready),.store_result(ur_result),.store_error(serror),.store_size(sr_size),.store_flags(sr_flags),.store_take(ur_take),.store_cancel(ur_cancel),
 .notice_start(notice_start),.notice_ready(notice_ready),.notice_busy(notice_busy),.notice_result(notice_result),.notice_reason(notice_reason),.notice_take(notice_take),.notice_cancel(notice_cancel),
 .notice_serial(notice_serial),.notice_status(notice_status),.notice_ratio(notice_ratio),.notice_name(notice_name),.notice_pn(notice_pn),.notice_nl(notice_nl),.notice_pl(notice_pl),.notice_deadline(notice_deadline));
 arinc615a_notice notice(.clk(clk),.rst_n(rst_n),.now(time_now),.deadline(notice_deadline),.start(notice_start),.ready(notice_ready),.cancel(notice_cancel),
 .network(upload_net),.mac(upload_mac),.ip(upload_ip),.port(16'd59),.serial(notice_serial),.status(notice_status),.ratio(notice_ratio),.filename(notice_name),.part_number(notice_pn),.name_length(notice_nl),.pn_length(notice_pl),
 .busy(notice_busy),.result_valid(notice_result),.result_ready(notice_take),.reason(notice_reason),
 .client_owned(notice_owned),.client_valid(nc_valid),.client_write(nc_write),.client_address(nc_address),.client_data(nc_data),.client_ready(wc_h_ready),.client_result_valid(wc_h_result),.client_error(wc_h_error),.client_result(wc_h_data),.client_take(nc_take),.writer_busy(wc_busy),
 .req_valid(nr_req),.req_ready(nr_ready),.req_op(nr_op),.req_length(nr_length),.s_data(nr_data),.s_valid(nr_valid),.s_last(nr_last),.s_ready(nr_data_ready),.store_result(nr_result),.store_error(serror),.store_take(nr_take),.store_cancel(nr_cancel));
 tftp_read_client #(.RTO_MIN(TFTP_RTO_MIN),.RTO_MAX(TFTP_RTO_MAX),.RETRY_LIMIT(TFTP_RETRIES)) reader(
 .clk(clk),.rst_n(rst_n),.now(time_now),.timeout_cycles(load_timeout),.start(rr_start),.start_ready(rr_start_ready),.cancel(rr_cancel),.network(upload_net),.mac(upload_mac),.ip(upload_ip),.port(16'd59),.filename(rr_name),.filename_length(rr_nl),.object_id(rr_object),.crc_seed(rr_seed),
 .busy(rr_busy),.result_valid(rr_result),.result_ready(rr_take),.reason(rr_reason),.result_length(rr_bytes),.result_crc16(rr_crc16),.result_crc32(rr_crc32),.retransmissions(rr_retrans),.blocks(rr_blocks),.ignored(rr_ignored),
 .rx_context_valid(lf_context && destination_reader),.rx_context_ready(rr_context_ready),.rx_network(lf_network),.rx_mac(lf_mac),.rx_ip(lf_ip),.rx_port(lf_port),.rx_destination(lf_destination),.rx_length(lf_length),.rx_data(lf_data),.rx_valid(lf_valid && destination_reader),.rx_last(lf_last),.rx_ready(rr_rx_ready),.rx_release(rr_release),
 .tx_cmd_valid(rt_cmd),.tx_cmd_ready(rt_cmd_ready),.tx_network(rt_network),.tx_mac(rt_mac),.tx_ip(rt_ip),.tx_port(rt_port),.tx_source(rt_source),.tx_length(rt_length),.tx_data(rt_data),.tx_valid(rt_valid),.tx_last(rt_last),.tx_ready(rt_ready),.tx_done(rt_done),.tx_error(rt_error),.tx_line_done(core_line_complete && line_is_tftp && line_owner==2),
 .store_req_valid(rr_req),.store_req_ready(rr_req_ready),.store_op(rr_op),.store_object(rr_store_object),.store_offset(rr_offset),.store_length(rr_length),.store_final(rr_final),.store_data(rr_data),.store_valid(rr_store_valid),.store_last(rr_store_last),.store_ready(rr_store_ready),.store_result_valid(rr_store_result),.store_error(serror),.store_result_ready(rr_store_take),.store_cancel(rr_store_cancel));
 assign dn_req_ready=bridge_ready && bridge_req && storage_choice==7;
 assign dn_result=bridge_result && storage_owned && storage_owner==7;
 assign dn_sready=bridge_data_ready && storage_owned && storage_owner==7;
 arinc615a_download #(.RTO_MIN(TFTP_RTO_MIN),.RTO_MAX(TFTP_RTO_MAX),.RETRY_LIMIT(TFTP_RETRIES)) download(
 .clk(clk),.rst_n(rst_n),.now(time_now),.timeout_cycles(load_timeout),
 .start_allowed(!upload_busy && !rr_busy && !wc_busy && !initialization_busy && !server_busy && !control_busy && !notice_busy),
 .lno_complete(dn_lno_complete),.lno_network(dn_lno_network),.lno_mac(dn_lno_mac),.lno_ip(dn_lno_ip),.lna_complete(dn_lna_complete),.lna_size(dn_lna_size),
 .lno_allowed(dn_lno_allowed),.lna_allowed(dn_lna_allowed),.busy(dn_busy),.network(dn_network),.mac(dn_mac),.ip(dn_ip),
 .h_valid(host_request && dn_select),.h_write(cfg_write),.h_address(load_address),.h_data(cfg_data),.h_ready(dn_h_ready),.h_result_valid(dn_h_result),.h_result_ready(cfg_resp_ready && dn_owned),.h_error(dn_h_error),.h_result(dn_h_data),
 .notice_owned(dn_notice_owned),.notice_object(dn_notice_object),.client_valid(dn_c_valid),.client_write(dn_c_write),.client_address(dn_c_address),.client_data(dn_c_data),
 .client_ready(wc_h_ready),.client_result_valid(wc_h_result),.client_error(wc_h_error),.client_result(wc_h_data),.client_take(dn_c_take),.writer_busy(wc_busy),
 .rx_context_valid(lf_context && destination_download),.rx_context_ready(dn_context_ready),.rx_network(lf_network),.rx_mac(lf_mac),.rx_ip(lf_ip),.rx_port(lf_port),.rx_destination(lf_destination),.rx_length(lf_length),
 .rx_data(lf_data),.rx_valid(lf_valid && destination_download),.rx_last(lf_last),.rx_ready(dn_rx_ready),.rx_release(dn_rx_release),
 .tx_cmd_valid(dt_cmd),.tx_cmd_ready(dt_cmd_ready),.tx_network(dt_network),.tx_mac(dt_mac),.tx_ip(dt_ip),.tx_port(dt_port),.tx_source(dt_source),.tx_length(dt_length),
 .tx_data(dt_data),.tx_valid(dt_valid),.tx_last(dt_last),.tx_ready(dt_ready),.tx_done(dt_done),.tx_error(dt_error),.tx_line_done(core_line_complete && line_is_tftp && line_owner==3),
 .req_valid(dn_req),.req_ready(dn_req_ready),.req_op(dn_op),.req_object(dn_object),.req_offset(dn_offset),.req_length(dn_length),.req_final(dn_final),
 .s_data(dn_data),.s_valid(dn_valid),.s_last(dn_last),.s_ready(dn_sready),.m_data(bridge_read_data),.m_valid(bridge_read_valid && storage_owned && storage_owner==7),.m_last(bridge_read_last),.m_ready(dn_read_ready),
 .result_valid(dn_result),.result_error(serror),.result_size(bridge_size),.result_flags(sr_flags),.result_ready(dn_take),.cancel(dn_cancel));
 file_udp_tx load_transmitter(.clk(clk),.rst_n(rst_n),.cmd_valid(out_cmd),.cmd_ready(out_cmd_ready),.cmd_network(out_network),.cmd_mac(out_mac),.cmd_ip(out_ip),.cmd_port(out_port),.cmd_source(out_source),.cmd_length(out_length),
  .s_data(out_data),.s_valid(out_valid),.s_ready(out_ready),.s_last(out_last),.done_valid(out_done),.done_ready(1'b1),.done_error(out_error),.configured_max(active_mgmt_max),
  .mgmt_cmd_valid(lm_cmd),.mgmt_cmd_ready(lm_cmd_ready),.mgmt_cmd_length(lm_length),.mgmt_network(lm_network),.mgmt_data(lm_data),.mgmt_valid(lm_valid),.mgmt_ready(lm_ready),.mgmt_last(lm_last),.mgmt_commit_valid(lm_commit),.mgmt_commit_ready(lm_commit_ready),.mgmt_abort(lm_abort),.mgmt_error_valid(lm_error),.mgmt_error_ready(lm_error_ready));
 time_management_mux load_egress(.clk(clk),.rst_n(rst_n),
  .h_cmd_valid(agent_cmd_valid),.h_length(agent_length),.h_network(agent_network),.h_cmd_ready(agent_cmd_ready),.h_data(agent_data),.h_valid(agent_valid),.h_last(agent_last),.h_commit(agent_commit),.h_abort(agent_abort),.h_ready(agent_ready),.h_commit_ready(agent_commit_ready),.h_error_valid(agent_error_valid),.h_error_ready(agent_error_ready),.h_error_code(),
  .a_cmd_valid(lm_cmd),.a_length(lm_length),.a_network(lm_network),.a_cmd_ready(lm_cmd_ready),.a_data(lm_data),.a_valid(lm_valid),.a_last(lm_last),.a_commit(lm_commit),.a_abort(lm_abort),.a_ready(lm_ready),.a_commit_ready(lm_commit_ready),.a_error_valid(lm_error),.a_error_ready(lm_error_ready),
  .c_cmd_valid(am_cmd),.c_length(am_length),.c_cmd_ready(am_cmd_ready),.c_data(am_data),.c_valid(am_valid),.c_last(am_last),.c_commit(am_commit),.c_abort(am_abort),.c_ready(am_ready),.c_commit_ready(am_commit_ready),.c_error_valid(am_error),.c_error_ready(am_error_ready),.c_error_code(queue_error_code),.c_network(am_network));
 sync_udp_rx time_endpoint(.clk(clk),.rst_n(rst_n),.s_data(udp_data),.s_valid(udp_time_valid),.s_ready(udp_time_ready),.s_sop(udp_sop),.s_last(udp_last),.s_error(udp_error),.s_network(udp_network),
  .stamp_seconds(stamp_seconds),.stamp_nanoseconds(stamp_nanoseconds),.stamp_tick(stamp_tick),.stamp_generation(stamp_generation),
  .context_seconds(context_seconds),.context_nanoseconds(context_nanoseconds),.context_tick(context_tick),.context_generation(context_generation),
  .context_valid(tr_context_valid),.context_ready(tr_context_ready),.context_network(tr_network),.context_mac(tr_mac),.context_ip(tr_ip),.context_port(tr_port),.context_length(tr_length),
  .m_data(tr_data),.m_valid(tr_valid),.m_ready(tr_ready),.m_last(tr_last),.release_valid(tr_release),.count_good(tr_good),.count_bad(tr_bad),.count_busy(tr_busy),.last_reason(tr_reason),.idle());
 sync_time_client client(.clk(clk),.rst_n(rst_n),.timeout_cycles(time_timeout),.rate_cycles(time_rate),.now(time_now),.rtc_seconds(rtc_seconds),.rtc_nanoseconds(rtc_nanoseconds),.coarse_valid(time_coarse),.basis_changed(time_basis_changed),.generation(time_generation),
  .start_valid(time_start),.start_ready(time_start_ready),.transaction(time_id),.cancel(time_cancel),.rearm(rearm),
  .tx_cmd_valid(tt_cmd),.tx_cmd_ready(tt_cmd_ready),.tx_data(tt_data),.tx_valid(tt_valid),.tx_ready(tt_ready),.tx_last(tt_last),.tx_done(tt_done),.tx_error(tt_done_error),
  .rx_context_valid(tr_context_valid),.rx_context_ready(tr_context_ready),.rx_network(tr_network),.rx_mac(tr_mac),.rx_ip(tr_ip),.rx_port(tr_port),.rx_length(tr_length),
  .rx_seconds(context_seconds),.rx_nanoseconds(context_nanoseconds),.rx_tick(context_tick),.rx_generation(context_generation),
  .rx_data(tr_data),.rx_valid(tr_valid),.rx_ready(tr_ready),.rx_last(tr_last),.rx_release(tr_release),
  .sample_valid(time_sample_valid),.sample_ready(sample_take),.sample_index(sample_index),.sample_word(time_sample_word),.idle(client_idle),
  .trace_valid(time_trace_valid),.trace_kind(time_trace_kind),.trace_tick(time_trace_tick),
  .ignored_count(ignored_count),.timeout_count(timeout_count),.sample_count(sample_count),.commit_count(commit_count));
 sync_udp_tx time_transmitter(.clk(clk),.rst_n(rst_n),.cmd_valid(tt_cmd),.cmd_ready(tt_cmd_ready),.cmd_network(1'b0),.cmd_mac(48'h020000001003),.cmd_ip(32'hc0000214),.cmd_port(16'd123),.cmd_length(10'd48),
  .s_data(tt_data),.s_valid(tt_valid),.s_ready(tt_ready),.s_last(tt_last),.done_valid(tt_done),.done_ready(1'b1),.done_error(tt_done_error),.configured_max(active_mgmt_max),
  .mgmt_cmd_valid(tm_cmd),.mgmt_cmd_ready(tm_cmd_ready),.mgmt_cmd_length(tm_length),.mgmt_network(tm_network),.mgmt_data(tm_data),.mgmt_valid(tm_valid),.mgmt_ready(tm_ready),.mgmt_last(tm_last),.mgmt_commit_valid(tm_commit),.mgmt_commit_ready(tm_commit_ready),.mgmt_abort(tm_abort),.mgmt_error_valid(tm_error),.mgmt_error_ready(tm_error_ready));
 time_management_mux time_egress(.clk(clk),.rst_n(rst_n),
  .h_cmd_valid(am_cmd),.h_length(am_length),.h_network(am_network),.h_cmd_ready(am_cmd_ready),.h_data(am_data),.h_valid(am_valid),.h_last(am_last),.h_commit(am_commit),.h_abort(am_abort),.h_ready(am_ready),.h_commit_ready(am_commit_ready),.h_error_valid(am_error),.h_error_ready(am_error_ready),.h_error_code(),
  .a_cmd_valid(tm_cmd),.a_length(tm_length),.a_network(tm_network),.a_cmd_ready(tm_cmd_ready),.a_data(tm_data),.a_valid(tm_valid),.a_last(tm_last),.a_commit(tm_commit),.a_abort(tm_abort),.a_ready(tm_ready),.a_commit_ready(tm_commit_ready),.a_error_valid(tm_error),.a_error_ready(tm_error_ready),
  .c_cmd_valid(cm_cmd),.c_length(cm_length),.c_cmd_ready(cm_cmd_ready),.c_data(cm_data),.c_valid(cm_valid),.c_last(cm_last),.c_commit(cm_commit),.c_abort(cm_abort),.c_ready(cm_ready),.c_commit_ready(cm_commit_ready),.c_error_valid(cm_error),.c_error_ready(cm_error_ready),.c_error_code(queue_error_code),.c_network(cm_network));
 always @(posedge clk)begin
  if(!rst_n)begin response_is_trap<=0;line_is_trap<=0;line_is_tftp<=0;end
  else begin
   if(core_line_complete)line_is_tftp<=0;
   if(queue_cmd_valid && queue_cmd_ready)line_is_tftp<=lm_cmd && lm_cmd_ready;
   if(tx_context_valid && tx_context_ready)response_is_trap<=tx_is_trap;
   if(queue_cmd_valid && queue_cmd_ready)line_is_trap<=agent_cmd_valid && agent_cmd_ready && response_is_trap;
  end
 end
 snmp_trap_events trap_events(.clk(clk),.rst_n(rst_n),.faults(trap_faults),.fault_total(trap_total),.used(trap_used),
  .generated_ready(trap_ready),.pending_valid(trap_valid),.snapshot_count(trap_snapshot),.snapshot_used(trap_occupancy),.generation_ticks(trap_ticks),
  .result_valid(trap_result_valid),.result_error(trap_result_error),.result_reason(trap_result_reason),.line_complete(core_line_complete && line_is_trap),.diagnostics(trap_diagnostics));
 wire [511:0] diagnostics={{16'd0,active_mgmt_max},{27'd0,rx_reason,rx_idle},rx_busy,rx_bad,rx_good,agent_diagnostics};
 snmp_notify_mux config_bus(.clk(clk),.rst_n(rst_n),
  .h_valid(host_request && !time_select && !load_select && !control_select && !writer_select && !initialization_select && !up_select && !dn_select),.h_write(cfg_write),.h_kind(cfg_kind),.h_bank(cfg_bank),.h_shadow(cfg_shadow),.h_index(cfg_index),.h_word(cfg_word),.h_data(cfg_data),.h_ready(legacy_ready),
  .h_result_valid(legacy_result_valid),.h_result_ready(cfg_resp_ready && !time_owned && !load_owned && !control_owned && !writer_owned && !initialization_owned && !up_owned && !dn_owned && !dn_denied_owned),.h_result_error(legacy_result_error),.h_result_data(legacy_result_data),
  .h_commit_valid(cfg_commit_valid),.h_commit_ready(cfg_commit_ready),.h_commit_result_valid(cfg_result_valid),.h_commit_result_ready(cfg_result_ready),.h_commit_result_ok(cfg_result_ok),.h_commit_result_code(cfg_result_code),
  .lock_valid(lock_valid),.lock_write(lock_write),.lock_ready(lock_ready),.lock_error(lock_error),.lock_release(lock_release),
  .a_commit_valid(a_commit_valid),.a_commit_ready(a_commit_ready),.a_commit_result_valid(a_result_valid),.a_commit_result_ready(a_result_ready),.a_commit_result_ok(a_result_ok),.a_commit_result_code(a_result_code),
  .c_commit_valid(c_commit_valid),.c_commit_ready(c_commit_ready),.c_commit_result_valid(c_commit_result_valid),.c_commit_result_ready(c_commit_result_ready),.c_commit_result_ok(c_commit_result_ok),.c_commit_result_code(c_commit_result_code),.c_budget_only(c_budget_only),.c_pending(cfg_pending),.c_applied(cfg_applied),
  .a_valid(stat_valid),.a_write(stat_write),.a_index(stat_index),.a_kind(stat_kind),.a_bank(stat_bank),.a_word(stat_word),.a_ready(stat_ready),.a_result_valid(stat_result_valid),.a_result_ready(stat_result_ready),.a_result_error(stat_result_error),.a_result_data(stat_data),
  .c_valid(c_valid),.c_write(c_write),.c_kind(c_kind),.c_bank(c_bank),.c_shadow(c_shadow),.c_index(c_index),.c_word(c_word),.c_data(c_data),.c_ready(c_ready),
  .c_result_valid(c_result_valid),.c_result_ready(c_result_ready),.c_result_error(c_result_error),.c_result_data(c_result_data),.diagnostics(diagnostics),.trap_diagnostics(trap_diagnostics));
 assign queue_cmd_valid=cm_cmd;assign cm_cmd_ready=queue_cmd_ready;assign queue_length=cm_length;
 assign queue_data=cm_data;assign queue_valid=cm_valid;assign queue_last=cm_last;assign queue_commit=cm_commit;assign queue_abort=cm_abort;
 assign cm_ready=queue_ready;assign cm_commit_ready=queue_commit_ready;assign cm_error=queue_error_valid;assign queue_error_ready=cm_error_ready;
 reg [1:0] queued_management_network;
 always @(posedge clk)begin
  if(!rst_n)queued_management_network<=0;
  else if(queue_cmd_valid && queue_cmd_ready)queued_management_network<=cm_network;
 end
 assign management_select=queued_management_network;
 snmp_frame_merge ingress(.clk(clk),.rst_n(rst_n),
  .a_data(management_rx_data[7:0]),.b_data(management_rx_data[15:8]),.a_valid(management_rx_valid[0]),.b_valid(management_rx_valid[1]),.a_ready(management_rx_ready[0]),.b_ready(management_rx_ready[1]),
  .a_sop(management_rx_sop[0]),.b_sop(management_rx_sop[1]),.a_last(management_rx_last[0]),.b_last(management_rx_last[1]),.a_error(management_rx_error[0]),.b_error(management_rx_error[1]),
  .m_data(merged_data),.m_valid(merged_valid),.m_ready(merged_ready),.m_sop(merged_sop),.m_last(merged_last),.m_error(merged_error),.m_network(merged_network));
 snmp_udp_rx endpoint(.clk(clk),.rst_n(rst_n),.s_data(post_data),.s_valid(udp_snmp_valid),.s_ready(udp_snmp_ready),.s_sop(post_sop),.s_last(post_last),.s_error(post_error),.s_network(post_network),
  .context_valid(context_valid),.context_ready(context_ready),.context_network(context_network),.context_mac(context_mac),.context_ip(context_ip),.context_port(context_port),.context_length(context_length),
  .m_data(rx_data),.m_valid(rx_valid),.m_ready(rx_ready),.m_last(rx_last),.release_valid(rx_release),.count_good(rx_good),.count_bad(rx_bad),.count_busy(rx_busy),.last_reason(rx_reason),.idle(rx_idle));
 snmp_notify_agent agent(.clk(clk),.rst_n(rst_n),.trap_valid(trap_valid),.trap_ready(trap_ready),.trap_count(trap_snapshot),.trap_ticks(trap_ticks),.trap_used(trap_occupancy),.tx_is_trap(tx_is_trap),.trap_result_valid(trap_result_valid),.trap_result_error(trap_result_error),.trap_result_reason(trap_result_reason),.context_valid(context_valid),.context_ready(context_ready),.context_network(context_network),.context_mac(context_mac),.context_ip(context_ip),.context_port(context_port),
  .s_data(rx_data),.s_valid(rx_valid),.s_ready(rx_ready),.s_last(rx_last),.release_context(rx_release),
  .stat_valid(stat_valid),.stat_write(stat_write),.stat_ready(stat_ready),.stat_index(stat_index),.stat_kind(stat_kind),.stat_bank(stat_bank),.stat_word(stat_word),
  .lock_valid(lock_valid),.lock_write(lock_write),.lock_ready(lock_ready),.lock_error(lock_error),.lock_release(lock_release),
  .cfg_commit_valid(a_commit_valid),.cfg_commit_ready(a_commit_ready),.cfg_result_valid(a_result_valid),.cfg_result_ready(a_result_ready),.cfg_result_ok(a_result_ok),.cfg_result_code(a_result_code),.cfg_applied(cfg_applied),.cfg_version(budget_version),.set_values(set_values),.response_limit(active_mgmt_max),.stat_result_valid(stat_result_valid),.stat_result_ready(stat_result_ready),.stat_result_error(stat_result_error),.stat_data(stat_data),
  .tx_context_valid(tx_context_valid),.tx_context_ready(tx_context_ready),.tx_network(tx_network),.tx_mac(tx_mac),.tx_ip(tx_ip),.tx_port(tx_port),.tx_length(tx_length),
  .m_data(tx_data),.m_valid(tx_valid),.m_ready(tx_ready),.m_last(tx_last),.tx_done_valid(tx_done_valid),.tx_done_ready(tx_done_ready),.tx_done_error(tx_done_error),.diagnostics(agent_diagnostics));
 snmp_udp_tx response(.clk(clk),.rst_n(rst_n),.cmd_valid(tx_context_valid),.cmd_ready(tx_context_ready),.cmd_network(tx_network),.cmd_mac(tx_mac),.cmd_ip(tx_ip),.cmd_port(tx_port),.cmd_length(tx_length),
  .s_data(tx_data),.s_valid(tx_valid),.s_ready(tx_ready),.s_last(tx_last),.done_valid(tx_done_valid),.done_ready(tx_done_ready),.done_error(tx_done_error),.configured_max(active_mgmt_max),
  .mgmt_cmd_valid(agent_cmd_valid),.mgmt_cmd_ready(agent_cmd_ready),.mgmt_cmd_length(agent_length),.mgmt_network(agent_network),.mgmt_data(agent_data),.mgmt_valid(agent_valid),.mgmt_ready(agent_ready),.mgmt_last(agent_last),.mgmt_commit_valid(agent_commit),.mgmt_commit_ready(agent_commit_ready),.mgmt_abort(agent_abort),.mgmt_error_valid(agent_error_valid),.mgmt_error_ready(agent_error_ready));
 snmp_notify_core datapath(.trap_fault_events(trap_faults),.trap_fault_total(trap_total),.trap_used(trap_used),.trap_line_complete(core_line_complete),
  .budget_valid(c_budget_only),.budget_max(set_values[15:0]),.budget_period(set_values[34:32]),.budget_line(set_values[95:64]),.budget_service(set_values[127:96]),.budget_version(budget_version),
  .clk(clk),
  .rst_n(rst_n),
  .gtx_clk(gtx_clk),
  .phy_a_rx_clk(phy_a_rx_clk),
  .phy_a_rxd(phy_a_rxd),
  .phy_a_rx_dv(phy_a_rx_dv),
  .phy_a_rx_er(phy_a_rx_er),
  .phy_a_tx_clk(phy_a_tx_clk),
  .phy_a_txd(phy_a_txd),
  .phy_a_tx_en(phy_a_tx_en),
  .phy_a_tx_er(phy_a_tx_er),
  .phy_b_rx_clk(phy_b_rx_clk),
  .phy_b_rxd(phy_b_rxd),
  .phy_b_rx_dv(phy_b_rx_dv),
  .phy_b_rx_er(phy_b_rx_er),
  .phy_b_tx_clk(phy_b_tx_clk),
  .phy_b_txd(phy_b_txd),
  .phy_b_tx_en(phy_b_tx_en),
  .phy_b_tx_er(phy_b_tx_er),
  .app_rx_network(app_rx_network),
  .cfg_valid(c_valid),
  .cfg_write(c_write),
  .cfg_kind(c_kind),
  .cfg_bank(c_bank),
  .cfg_shadow(c_shadow),
  .cfg_index(c_index),
  .cfg_word(c_word),
  .cfg_data(c_data),
  .cfg_ready(c_ready),
  .cfg_resp_valid(c_result_valid),
  .cfg_resp_ready(c_result_ready),
  .cfg_resp_error(c_result_error),
  .cfg_resp_data(c_result_data),
  .cfg_commit_valid(c_commit_valid),
  .cfg_commit_ready(c_commit_ready),
  .cfg_pending(cfg_pending),
  .cfg_applied(cfg_applied),
  .cfg_result_valid(c_commit_result_valid),
  .cfg_result_ok(c_commit_result_ok),
  .cfg_result_ready(c_commit_result_ready),
  .cfg_result_code(c_commit_result_code),
  .init_done(init_done),
  .message_seed_valid(message_seed_valid),.message_seed(message_seed),.message_seed_ready(message_seed_ready),.final_app_frame(final_app_frame),.final_app_byte(final_app_byte),.app_tx_cmd_valid(app_tx_cmd_valid),
  .app_tx_cmd_ready(app_tx_cmd_ready),
  .app_tx_cmd_index(app_tx_cmd_index),
  .app_tx_cmd_length(app_tx_cmd_length),
  .app_tx_data(app_tx_data),
  .app_tx_valid(app_tx_valid),
  .app_tx_last(app_tx_last),
  .app_tx_ready(app_tx_ready),
  .app_tx_commit_valid(app_tx_commit_valid),
  .app_tx_abort(app_tx_abort),
  .app_tx_commit_ready(app_tx_commit_ready),
  .app_tx_error_valid(app_tx_error_valid),
  .app_tx_error_ready(app_tx_error_ready),
  .app_tx_error_code(app_tx_error_code),
  .app_rx_desc_valid(app_rx_desc_valid),
  .app_rx_desc_ready(app_rx_desc_ready),
  .app_rx_desc_length(app_rx_desc_length),
  .app_rx_desc_vl(app_rx_desc_vl),
  .app_rx_desc_app_id(app_rx_desc_app_id),
  .app_rx_desc_version(app_rx_desc_version),
  .app_rx_desc_sn(app_rx_desc_sn),
  .app_rx_desc_udp_checked(app_rx_desc_udp_checked),
  .app_rx_fragment(app_rx_fragment),.app_rx_data(app_rx_data),
  .app_rx_valid(app_rx_valid),
  .app_rx_sop(app_rx_sop),
  .app_rx_last(app_rx_last),
  .app_rx_ready(app_rx_ready),
  .mgmt_cmd_valid(queue_cmd_valid),
  .mgmt_cmd_length(queue_length),
  .mgmt_cmd_ready(queue_cmd_ready),
  .mgmt_data(queue_data),
  .mgmt_valid(queue_valid),
  .mgmt_last(queue_last),
  .mgmt_commit_valid(queue_commit),
  .mgmt_abort(queue_abort),
  .mgmt_ready(queue_ready),
  .mgmt_commit_ready(queue_commit_ready),
  .mgmt_error_valid(queue_error_valid),
  .mgmt_error_ready(queue_error_ready),
  .mgmt_error_code(queue_error_code),
  .events(events),
  .line_management(line_management),
  .management_select(management_select),
  .management_max(active_mgmt_max),
  .management_rx_data(management_rx_data),
  .management_rx_valid(management_rx_valid),
  .management_rx_ready(management_rx_ready),
  .management_rx_sop(management_rx_sop),
  .management_rx_last(management_rx_last),
  .management_rx_error(management_rx_error)
 );
endmodule
