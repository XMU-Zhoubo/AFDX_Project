`timescale 1ns/1ps
module c42_system;
 parameter VECTOR_DIR="vectors/tftp/c33",TIMEOUT_NS=500000000;
reg clk=0;
reg rst_n=0;
reg gtx_clk=0;
reg phy_rx_clk=0;
reg [7:0] phy_rxd=0;
reg phy_rx_dv=0;
reg phy_rx_er=0;
wire phy_tx_clk;
wire [7:0] phy_txd;
wire phy_tx_en;
wire phy_tx_er;
reg cfg_valid=0;
reg cfg_write=0;
reg [1:0] cfg_kind=0;
reg cfg_bank=0;
reg cfg_shadow=0;
reg [12:0] cfg_index=0;
reg [3:0] cfg_word=0;
reg [31:0] cfg_data=0;
wire cfg_ready;
wire cfg_resp_valid;
reg cfg_resp_ready=0;
wire cfg_resp_error;
wire [31:0] cfg_resp_data;
reg cfg_commit_valid=0;
wire cfg_commit_ready;
wire cfg_pending;
wire cfg_applied;
wire cfg_result_valid;
wire cfg_result_ok;
reg cfg_result_ready=0;
wire [2:0] cfg_result_code;
wire [15:0] cfg_version;
wire init_done;
reg app_tx_cmd_valid=0;
wire app_tx_cmd_ready;
reg [12:0] app_tx_cmd_index=0;
reg [15:0] app_tx_cmd_length=0;
reg [7:0] app_tx_data=0;
reg app_tx_valid=0;
reg app_tx_last=0;
wire app_tx_ready;
reg app_tx_commit_valid=0;
reg app_tx_abort=0;
wire app_tx_commit_ready;
wire app_tx_error_valid;
reg app_tx_error_ready=0;
wire [3:0] app_tx_error_code;
wire app_rx_desc_valid;
reg app_rx_desc_ready=0;
wire [15:0] app_rx_desc_length;
wire [15:0] app_rx_desc_vl;
wire [15:0] app_rx_desc_app_id;
wire [15:0] app_rx_desc_version;
wire [7:0] app_rx_desc_sn;
wire app_rx_desc_udp_checked;
wire [7:0] app_rx_data;
wire app_rx_valid;
wire app_rx_sop;
wire app_rx_last;
reg app_rx_ready=0;
wire [7:0] store_tx_data,store_rx_data;
wire store_tx_valid,store_tx_last,store_tx_ready,store_rx_valid,store_rx_last,store_rx_ready,store_cancel;
wire [7:0] events;
wire line_management;
 reg phy_b_rx_clk=0;reg [7:0] phy_b_rxd=0;reg phy_b_rx_dv=0,phy_b_rx_er=0;
 wire phy_b_tx_clk,phy_b_tx_en,phy_b_tx_er,app_rx_network;wire [7:0] phy_b_txd;
 reg app_tx_sop=0;reg [15:0] app_tx_vlid=0;
 AFDX_top dut(.clk(clk),.rst_n(rst_n),.gtx_clk(gtx_clk),.phy_b_rx_clk(phy_b_rx_clk),.phy_b_rxd(phy_b_rxd),.phy_b_rx_dv(phy_b_rx_dv),.phy_b_rx_er(phy_b_rx_er),.phy_b_tx_clk(phy_b_tx_clk),.phy_b_txd(phy_b_txd),.phy_b_tx_en(phy_b_tx_en),.phy_b_tx_er(phy_b_tx_er),.rx_network(app_rx_network),.phy_a_rx_clk(phy_rx_clk),.phy_a_rxd(phy_rxd),.phy_a_rx_dv(phy_rx_dv),.phy_a_rx_er(phy_rx_er),.phy_a_tx_clk(phy_tx_clk),.phy_a_txd(phy_txd),.phy_a_tx_en(phy_tx_en),.phy_a_tx_er(phy_tx_er),.cfg_valid(cfg_valid),.cfg_write(cfg_write),.cfg_kind(cfg_kind),.cfg_bank(cfg_bank),.cfg_shadow(cfg_shadow),.cfg_index(cfg_index),.cfg_word(cfg_word),.cfg_data(cfg_data),.cfg_ready(cfg_ready),.cfg_resp_valid(cfg_resp_valid),.cfg_resp_ready(cfg_resp_ready),.cfg_resp_error(cfg_resp_error),.cfg_resp_data(cfg_resp_data),.cfg_commit_valid(cfg_commit_valid),.cfg_commit_ready(cfg_commit_ready),.cfg_pending(cfg_pending),.cfg_applied(cfg_applied),.cfg_result_valid(cfg_result_valid),.cfg_result_ok(cfg_result_ok),.cfg_result_ready(cfg_result_ready),.cfg_result_code(cfg_result_code),.init_done(init_done),.tx_cmd_valid(app_tx_cmd_valid),.tx_cmd_ready(app_tx_cmd_ready),.tx_vlid(app_tx_vlid),.tx_length(app_tx_cmd_length),.tx_data(app_tx_data),.tx_valid(app_tx_valid),.tx_sop(app_tx_sop),.tx_last(app_tx_last),.tx_ready(app_tx_ready),.tx_commit_valid(app_tx_commit_valid),.tx_abort(app_tx_abort),.tx_commit_ready(app_tx_commit_ready),.tx_error_valid(app_tx_error_valid),.tx_error_ready(app_tx_error_ready),.tx_error_code(app_tx_error_code),.rx_desc_valid(app_rx_desc_valid),.rx_desc_ready(app_rx_desc_ready),.rx_desc_length(app_rx_desc_length),.rx_desc_vl(app_rx_desc_vl),.rx_desc_app_id(app_rx_desc_app_id),.rx_desc_version(app_rx_desc_version),.rx_desc_sn(app_rx_desc_sn),.rx_desc_udp_checked(app_rx_desc_udp_checked),.rx_data(app_rx_data),.rx_valid(app_rx_valid),.rx_sop(app_rx_sop),.rx_last(app_rx_last),.rx_ready(app_rx_ready),.store_tx_data(store_tx_data),.store_tx_valid(store_tx_valid),.store_tx_last(store_tx_last),.store_tx_ready(store_tx_ready),.store_rx_data(store_rx_data),.store_rx_valid(store_rx_valid),.store_rx_last(store_rx_last),.store_rx_ready(store_rx_ready),.store_cancel(store_cancel),.events(events),.line_management(line_management));
 always #5 clk=~clk;
 always #4 gtx_clk=~gtx_clk;
 initial begin #2;forever #4 phy_rx_clk=~phy_rx_clk;end
 initial begin #3;forever #4 phy_b_rx_clk=~phy_b_rx_clk;end

 parameter CONTROL_DIR="vectors/615a/c34";
 reg [7:0] control_gold[0:511];integer fd_storage;
 reg done=0;wire timeout_seen;integer checks=0,failures=0,cases=0,cycles=0;
 reg [511:0] case_name="startup";reg [2047:0] path;reg [31:0] dummy,value;
 reg inject_stale=0;reg force_stall=0,random_stall=0,hold_completion=0,fail_write=0;
 wire [31:0] store_opens,store_writes,store_reads,store_cancelled,store_failed;
 wire object_valid,object_complete,store_event;wire [15:0] object_length,store_event_length;wire [2:0] store_event_kind;
 wire [7:0] media_rx_data;wire media_rx_valid,media_rx_last;
 reg storage_inject=0;reg [3:0] storage_inject_index=0;reg [31:0] saved_old_tag=0;
 assign store_rx_valid=storage_inject?1'b1:media_rx_valid;
 assign store_rx_last=storage_inject?storage_inject_index==4:media_rx_last;
 assign store_rx_data=storage_inject?(storage_inject_index<4?saved_old_tag[31-storage_inject_index*8-:8]:8'd0):media_rx_data;
 storage_download_model media(.clk(clk),.rst_n(rst_n),.cancel(store_cancel),.s_data(store_tx_data),.s_valid(store_tx_valid),.s_last(store_tx_last),.s_ready(store_tx_ready),
  .m_data(media_rx_data),.m_valid(media_rx_valid),.m_last(media_rx_last),.m_ready(store_rx_ready && !storage_inject),
  .stall(force_stall || (random_stall && (cycles%7==0 || cycles%7==1))),.hold_completion(hold_completion),.fail_write(fail_write),.inject_stale(inject_stale),
  .opens(store_opens),.writes(store_writes),.reads(store_reads),.cancelled(store_cancelled),.failed(store_failed),.object_valid(object_valid),.object_complete(object_complete),.object_length(object_length),
  .event_valid(store_event),.event_kind(store_event_kind),.event_length(store_event_length));
 tb_watchdog #(.TIMEOUT_NS(TIMEOUT_NS)) watchdog(.done(done),.timeout_seen(timeout_seen));
 integer fd_events,fd_wire,fd_rx,fd_read,fd_progress,i,rx_frames=0,tx_frames=0,ack0=0,ack1=0,errors=0,apps=0,rt_frames=0,snmp_frames=0;
 integer expected_writes=0,expected_opens=0,model_epoch=0;
 reg [31:0] config_words[0:15];reg [7:0] message[0:1023],inj[0:2047],snmp_request[0:255],snmp_response[0:255],real_a[0:255],real_b[0:255];
 integer message_length=0,inj_length=0;reg [15:0] current_tid=0,last_tid=0;reg [15:0] sender_port=40001,destination=69;
 reg [47:0] sender_mac=48'h020000001004;reg [31:0] sender_ip=32'hc000021e;reg selected_network=0;
 integer fd_peer,peer_received=0,peer_dropped=0;reg exp_drop[0:511];time wire_start[0:511],wire_end[0:511];
 integer qhead=0,qtail=0;integer exp_op[0:511],exp_number[0:511],exp_net[0:511],exp_port[0:511],exp_source[0:511],exp_commits[0:511];
 integer exp_bytes[0:511],exp_seed[0:511],exp_offset[0:511];integer data_frames=0,tx_stalls=0;
 time last_store_complete=0,last_data_accept=0,last_open_complete=0;
 task automatic ck;input condition;input [511:0] label;input [127:0] expected,actual;
 begin checks=checks+1;if(condition!==1'b1)begin failures=failures+1;$display("C42_MISMATCH case=%0s item=%0s time_ps=%0t expected=%032h actual=%032h",case_name,label,$time,expected,actual);    $finish;end end endtask
 task pause;input integer n;begin repeat(n)@(negedge clk);end endtask
 parameter UPLOAD_DIR="vectors/615a/c35";
 reg [7:0] hfile[0:511],rfile[0:511],dfile[0:4095],wire_bytes[0:264191];
 reg [7:0] last_lus[0:511];time offered[0:65535],wire_offer_time[0:511],cancel_tick=0;
 integer wire_len[0:511],wire_source[0:511],wire_port[0:511],wire_net[0:511];
 integer file_id=0,business_size=0,expected_bad=0,header_bytes=108,lur_bytes=25;
 integer rr_tid=0,rr_file=0,rr_offset=0,rr_block=0,rr_chunk=0,wr_tid=0;
 integer init_counter=0,last_counter=0,final_status=0,status_files=0,periodic_files=0;
 integer data_commits=0,data_zero=0,duplicate_exercised=0,lose_lus_ack=0,drop_status=0;
 integer upload_index=0,last_lus_len=0,last_lus_counter=0,final_notifications=0;
 reg known_reader[0:4999];integer old_acks=0;
 integer data_retries=0,read_requests=0,header_requests=0,final_requests=0;
 reg duplicate_data=0,cancel_at_data=0;
 parameter APP_DIR="vectors/system/c42",SCENARIO=1;
 reg [7:0] app_payload[0:163839],app_gold_a[0:163839],app_gold_b[0:163839],snmp_gold[0:65535];
 reg [31:0] app_meta[0:319],snmp_lengths[0:31],app_config[0:39];
 reg [7:0] link_mem[0:524287];integer link_len[0:255],link_kind[0:255];integer lh[0:1],lt[0:1];
 reg link_a_down=0,hold_application=0,application_enable=0,source_run=0,concurrent_active=0,services_done=0;
 reg source_done=0,rtc_done=0,snmp_done=0,fault_done=0,host_lock=0;
 integer fd_app,fd_rtc,fd_links,app_accepted=0,app_unique=0,tftp_frames=0,trap_frames=0,trap_received=0,snmp_replies=0,snmp_sent=0;
 integer ntp_requests=0,ntp_served=0,rtc_success=0,rtc_timeout=0,rtc_transactions=0,app_errors=0,latest_loop_id=-1;
 integer app_seen[0:79],app_sent[0:63],physical_mask[0:63];time app_first[0:63],app_accept[0:63],app_commit[0:63];
 time last_rt_start[0:3],concurrent_begin=0,fault_begin=0,fault_end=0;
 integer out_id=-1,out_pos=0;reg out_active=0,out_visible=0;
 reg desc_held=0,data_held=0;reg [89:0] held_desc;reg [9:0] held_payload;
 reg [63:0] server_origin[0:7];time server_request[0:7];reg [7:0] ntp_inj[0:255];integer ntp_length;
 reg [31:0] samples[0:31];
 reg rtc_reset_seen=0;time rtc_tick_origin=0;
 always @(posedge clk)begin
  if(rst_n && !rtc_reset_seen)begin rtc_tick_origin=$time;$fdisplay(fd_rtc,"RTC_TICK_ORIGIN time_ns=%0d",$time);end
  rtc_reset_seen=rst_n;
 end
 function [63:0] server_ntp;input time ns;reg [127:0] t,s,f;begin
  t=128'd1760000000000000000+ns;s=t/1000000000;f=((t%1000000000)<<32)/1000000000;server_ntp=((s+128'd2208988800)<<32)|f[31:0];
 end endfunction
 task automatic enqueue_inj;input integer net,kind;output integer ticket;integer j,slot;begin
  ck(lt[net]<128,"bounded_external_link_queue",128,lt[net]);ticket=lt[net];slot=net*128+ticket;
  for(j=0;j<inj_length;j=j+1)link_mem[slot*2048+j]=inj[j];link_len[slot]=inj_length;link_kind[slot]=kind;lt[net]=ticket+1;
 end endtask
 task automatic enqueue_app;input integer net,id;integer j,slot;reg [31:0] mutated_crc;begin
  ck(lt[net]<128,"bounded_external_application_queue",128,lt[net]);slot=net*128+lt[net];
  for(j=0;j<app_meta[id*4+3];j=j+1)link_mem[slot*2048+j]=net?app_gold_b[id*2048+j]:app_gold_a[id*2048+j];
  link_len[slot]=app_meta[id*4+3];
  if(net==0 && id==0)begin link_mem[slot*2048+link_len[slot]-1]=link_mem[slot*2048+link_len[slot]-1]^1;$fdisplay(fd_events,"RX_DAMAGE id=0 net=0 reason=FCS time_ns=%0d",$time);end
  if(net==0 && id==2)begin
   link_mem[slot*2048+32]=link_mem[slot*2048+32]^1;mutated_crc=32'hffffffff;
   for(j=8;j<link_len[slot]-4;j=j+1)mutated_crc=crc_octet(mutated_crc,link_mem[slot*2048+j]);mutated_crc=~mutated_crc;
   for(j=0;j<4;j=j+1)link_mem[slot*2048+link_len[slot]-4+j]=mutated_crc[j*8+:8];
   $fdisplay(fd_events,"RX_DAMAGE id=2 net=0 reason=IP_checksum_valid_FCS time_ns=%0d",$time);
  end
  link_kind[slot]=100+id;lt[net]=lt[net]+1;
 end endtask
 task automatic enqueue_snmp;input integer id;integer j,slot;begin
  ck(lt[1]<128,"bounded_SNMP_link_queue",128,lt[1]);slot=128+lt[1];
  for(j=0;j<snmp_lengths[id];j=j+1)link_mem[slot*2048+j]=snmp_gold[id*2048+j];link_len[slot]=snmp_lengths[id];link_kind[slot]=200;lt[1]=lt[1]+1;
 end endtask
 genvar link;
 generate for(link=0;link<2;link=link+1)begin:external_links
  integer ticket,j,slot,n;reg discarded;
  initial begin
   wait(rst_n);
   forever begin
    if(link==0)@(negedge phy_rx_clk);else @(negedge phy_b_rx_clk);
    if(lh[link]<lt[link])begin
     ticket=lh[link];slot=link*128+ticket;n=link_len[slot];discarded=link==0 && link_a_down;
     if(discarded)$fdisplay(fd_links,"RX_DROP net=%0d ticket=%0d kind=%0d time_ns=%0d",link,ticket,link_kind[slot],$time);
     else begin
      $fwrite(fd_rx,"%0d %0d %0d ",link,$time,n);for(j=0;j<n;j=j+1)$fwrite(fd_rx,"%02x",link_mem[slot*2048+j]);$fwrite(fd_rx,"\n");
      $fdisplay(fd_links,"RX_BEGIN net=%0d ticket=%0d kind=%0d time_ns=%0d",link,ticket,link_kind[slot],$time);
      for(j=0;j<n;j=j+1)begin
       if(link==0)begin phy_rxd=link_mem[slot*2048+j];phy_rx_dv=1;@(negedge phy_rx_clk);end
       else begin phy_b_rxd=link_mem[slot*2048+j];phy_b_rx_dv=1;@(negedge phy_b_rx_clk);end
      end
      if(link==0)begin phy_rx_dv=0;phy_rxd=0;repeat(14)@(negedge phy_rx_clk);end
      else begin phy_b_rx_dv=0;phy_b_rxd=0;repeat(14)@(negedge phy_b_rx_clk);end
      rx_frames=rx_frames+1;
     end
     lh[link]=ticket+1;
    end
   end
  end
 end endgenerate
 task automatic app_send;input integer id;integer j,n;begin
  n=app_meta[id*4+1];@(negedge clk);app_tx_cmd_valid=1;app_tx_vlid=app_meta[id*4];app_tx_cmd_length=n;
  @(posedge clk);while(!app_tx_cmd_ready)@(posedge clk);@(negedge clk);app_tx_cmd_valid=0;
  for(j=0;j<n;j=j+1)begin
   if(j!=0 && j%7==0)pause(2);
   app_tx_data=app_payload[id*2048+j];app_tx_sop=j==0;app_tx_last=j==n-1;app_tx_valid=1;
   if(j==0)begin app_first[id]=$time;$fdisplay(fd_app,"INPUT id=%0d vl=%0d length=%0d time_ns=%0d",id,app_meta[id*4],n,$time);end
   @(posedge clk);while(!app_tx_ready)@(posedge clk);
   if(j==0)begin app_accept[id]=$time;$fdisplay(fd_app,"ACCEPT id=%0d time_ns=%0d",id,$time);end
   @(negedge clk);app_tx_valid=0;
  end
  app_tx_sop=0;app_tx_last=0;app_tx_commit_valid=1;@(posedge clk);while(!app_tx_commit_ready)@(posedge clk);
  app_commit[id]=$time;app_sent[id]=1;app_accepted=app_accepted+1;$fdisplay(fd_app,"COMMIT id=%0d time_ns=%0d",id,$time);
  @(negedge clk);app_tx_commit_valid=0;
 end endtask
 task automatic wait_app;input integer id;integer t;begin
  if(!app_seen[id] && !out_active)begin
   hold_application=1;t=0;while(!app_rx_desc_valid && t<500000)begin @(negedge clk);t=t+1;end
   ck(app_rx_desc_valid,"bounded_descriptor_before_deliberate_backpressure",1,app_rx_desc_valid);pause(7);hold_application=0;
  end
  t=0;while(!app_seen[id] && t<500000)begin @(negedge clk);t=t+1;end
  ck(app_seen[id]==1,"bounded_unique_application_delivery",1,app_seen[id]);
 end endtask
 task automatic unknown_command;input [15:0] vl,n;input [3:0] code;integer t;begin
  @(negedge clk);app_tx_error_ready=0;app_tx_vlid=vl;app_tx_cmd_length=n;app_tx_cmd_valid=1;
  @(posedge clk);while(!app_tx_cmd_ready)@(posedge clk);@(negedge clk);app_tx_cmd_valid=0;
  t=0;while(!app_tx_error_valid && t<10000)begin @(negedge clk);t=t+1;end
  ck(app_tx_error_valid && app_tx_error_code==code,"application_command_rejection",code,app_tx_error_code);
  repeat(3)begin @(negedge clk);ck(app_tx_error_valid && app_tx_error_code==code,"error_backpressure_stable",code,app_tx_error_code);end
  app_errors=app_errors+1;app_tx_error_ready=1;pause(4);
 end endtask
 always @(negedge clk)begin
  if(!rst_n || !application_enable || hold_application)begin app_rx_desc_ready=0;app_rx_ready=0;end
  else begin app_rx_desc_ready=cycles%23!=0;app_rx_ready=cycles%17<12;end
 end
 integer app_scan,found_id;reg [89:0] desc_now;
 always @(posedge clk)if(rst_n)begin
  desc_now={app_rx_network,app_rx_desc_length,app_rx_desc_vl,app_rx_desc_app_id,app_rx_desc_version,app_rx_desc_sn,app_rx_desc_udp_checked};
  if(desc_held)ck(app_rx_desc_valid && desc_now==held_desc,"descriptor_stable_under_backpressure",held_desc,desc_now);
  if(data_held)ck(app_rx_valid && {app_rx_data,app_rx_sop,app_rx_last}==held_payload,"payload_stable_under_backpressure",held_payload,{app_rx_data,app_rx_sop,app_rx_last});
  desc_held=app_rx_desc_valid && !app_rx_desc_ready;held_desc=desc_now;
  data_held=app_rx_valid && !app_rx_ready;held_payload={app_rx_data,app_rx_sop,app_rx_last};
  if(app_rx_desc_valid && app_rx_desc_ready)begin
   found_id=-1;for(app_scan=0;app_scan<80;app_scan=app_scan+1)if(app_meta[app_scan*4]==app_rx_desc_vl && app_meta[app_scan*4+2]==app_rx_desc_sn)found_id=app_scan;
   ck(found_id>=0 && !out_active,"descriptor_has_independent_input_identity",1,found_id>=0);
   ck(app_rx_desc_length==app_meta[found_id*4+1] && app_rx_desc_udp_checked,"descriptor_length_and_checked",app_meta[found_id*4+1],app_rx_desc_length);
   ck(app_rx_desc_app_id==(app_rx_desc_vl==1 ? 16'h4001 : app_rx_desc_vl==16'h8001 ? 16'hc001 : 16'h4242),"application_routing_ownership",app_rx_desc_vl,app_rx_desc_app_id);
   out_id=found_id;out_pos=0;out_active=1;out_visible=0;
   $fdisplay(fd_app,"DESC id=%0d network=%0d version=%0d time_ns=%0d",out_id,app_rx_network,app_rx_desc_version,$time);
  end
  if(app_rx_valid)begin
   ck(out_active,"data_only_after_descriptor",1,out_active);
   if(!out_visible)begin out_visible=1;$fdisplay(fd_app,"VISIBLE id=%0d time_ns=%0d",out_id,$time);end
   if(app_rx_ready)begin
    ck(app_rx_data==app_payload[out_id*2048+out_pos],"independent_application_byte",app_payload[out_id*2048+out_pos],app_rx_data);
    ck(app_rx_sop==(out_pos==0) && app_rx_last==(out_pos+1==app_meta[out_id*4+1]),"application_SOP_LAST_exact",app_meta[out_id*4+1],out_pos+1);
    if(out_pos==0)$fdisplay(fd_app,"CONSUME id=%0d time_ns=%0d",out_id,$time);
    $fdisplay(fd_app,"BYTE id=%0d offset=%0d data=%02x time_ns=%0d",out_id,out_pos,app_rx_data,$time);
    out_pos=out_pos+1;
    if(app_rx_last)begin
     ck(app_seen[out_id]==0,"no_redundant_duplicate_delivery",0,app_seen[out_id]);app_seen[out_id]=app_seen[out_id]+1;apps=apps+1;
     if(out_id<64)app_unique=app_unique+1;
     $fdisplay(fd_app,"DELIVER id=%0d network=%0d bytes=%0d time_ns=%0d",out_id,app_rx_network,out_pos,$time);out_active=0;
    end
   end
  end
 end
 task automatic resource_burst;integer j,ticket;begin
  hold_application=1;pause(30);
  for(j=64;j<74;j=j+1)enqueue_app(0,j);
  pause(25000);hold_application=0;
  $fdisplay(fd_events,"RESOURCE_BURST_END offered=10 time_ns=%0d",$time);
 end endtask
 task automatic tbus;input wr;input [7:0] address;input [31:0] data;output [31:0] answer;
 begin bus(wr,3,0,0,((address>>4)<<4)|3,address&15,data,0,answer);end endtask
 task automatic ntp_response;input integer id;integer j,n,sum,slot;reg [383:0] p;reg [15:0] cs;reg [31:0] crc;reg [63:0] t2,t3;begin
  t2=server_ntp(server_request[id]+25000);t3=server_ntp($time+56-25000);p=0;p[383:376]=8'h24;p[375:368]=1;p[367:360]=4;p[359:352]=8'he5;p[287:256]=32'h47505300;p[255:192]=t2;p[191:128]=server_origin[id];p[127:64]=t2;p[63:0]=t3;
  for(j=0;j<256;j=j+1)ntp_inj[j]=0;for(j=0;j<7;j=j+1)ntp_inj[j]=8'h55;ntp_inj[7]=8'hd5;
  {ntp_inj[8],ntp_inj[9],ntp_inj[10],ntp_inj[11],ntp_inj[12],ntp_inj[13]}=48'h020000001001;
  {ntp_inj[14],ntp_inj[15],ntp_inj[16],ntp_inj[17],ntp_inj[18],ntp_inj[19]}=48'h020000001003;ntp_inj[20]=8'h08;ntp_inj[22]=8'h45;ntp_inj[25]=76;ntp_inj[28]=8'h40;ntp_inj[30]=64;ntp_inj[31]=17;
  {ntp_inj[34],ntp_inj[35],ntp_inj[36],ntp_inj[37]}=32'hc0000214;{ntp_inj[38],ntp_inj[39],ntp_inj[40],ntp_inj[41]}=32'hc000020a;
  {ntp_inj[42],ntp_inj[43]}=123;{ntp_inj[44],ntp_inj[45]}=45000;{ntp_inj[46],ntp_inj[47]}=56;
  for(j=0;j<48;j=j+1)ntp_inj[50+j]=p[383-j*8-:8];sum=0;for(j=22;j<42;j=j+2)sum=sum+{ntp_inj[j],ntp_inj[j+1]};{ntp_inj[32],ntp_inj[33]}=complement(sum);
  sum=17+56;for(j=34;j<42;j=j+2)sum=sum+{ntp_inj[j],ntp_inj[j+1]};for(j=42;j<98;j=j+2)sum=sum+{ntp_inj[j],ntp_inj[j+1]};cs=complement(sum);if(!cs)cs=65535;{ntp_inj[48],ntp_inj[49]}=cs;
  crc=32'hffffffff;for(j=8;j<98;j=j+1)crc=crc_octet(crc,ntp_inj[j]);crc=~crc;for(j=0;j<4;j=j+1)ntp_inj[98+j]=crc[j*8+:8];
  slot=lt[0];ck(slot<128,"SNTP_link_bounded",128,slot);for(j=0;j<102;j=j+1)link_mem[slot*2048+j]=ntp_inj[j];link_len[slot]=102;link_kind[slot]=300+id;lt[0]=slot+1;
  $fdisplay(fd_rtc,"SERVER id=%0d token=%016h t2=%016h t3=%016h queued_ns=%0d A_down=%0d",id,server_origin[id],t2,t3,$time,link_a_down);
 end endtask
 initial begin:server_thread
  wait(concurrent_active);
  forever begin wait(ntp_requests>ntp_served);#150000;ntp_response(ntp_served);ntp_served=ntp_served+1;end
 end
 task sample_rtc;
  integer attempt,t,j;reg [31:0] x,before_count,after_count,flags;reg [63:0] rs,target_sec,sched_candidate,sched_decision;reg [31:0] rn,st,target_ns,apply_tick,sched_meta,sched_vl;

 begin
  for(attempt=0;attempt<1;attempt=attempt+1)begin
   if(attempt>0)pause(350000);
   tbus(0,80,0,before_count);tbus(1,4,3800+attempt,x);rtc_transactions=rtc_transactions+1;
   t=0;x=0;while(!x[0] && t<200000)begin pause(20);tbus(0,8,0,x);t=t+1;end ck(x[0],"bounded_RTC_sample_terminal",1,x[0]);
   for(j=0;j<32;j=j+1)tbus(0,16+j,0,samples[j]);
   x=32'hf0;t=0;while(x[7:4]!=0 && t<10000)begin tbus(0,95,0,x);t=t+1;end
   tbus(0,80,0,after_count);tbus(0,64,0,flags);
   if(samples[1][3:0]==1)begin ck(after_count==before_count+1,"external_sample_actually_corrects_RTC",before_count+1,after_count);rtc_success=rtc_success+1;end
   else begin ck(samples[1][3:0]==3 && after_count==before_count,"A_outage_timeout_never_corrects_RTC",before_count,after_count);rtc_timeout=rtc_timeout+1;end
   tbus(1,7,0,x);tbus(0,48,0,rs[31:0]);tbus(0,49,0,rs[63:32]);tbus(0,50,0,rn);tbus(0,56,0,st);
   tbus(0,88,0,target_sec[31:0]);tbus(0,89,0,target_sec[63:32]);tbus(0,90,0,target_ns);tbus(0,91,0,apply_tick);
   bus(0,3,0,0,0,8,0,0,x);bus(0,3,0,0,0,9,0,0,sched_candidate[31:0]);bus(0,3,0,0,0,10,0,0,sched_candidate[63:32]);
   bus(0,3,0,0,0,11,0,0,sched_decision[31:0]);bus(0,3,0,0,0,12,0,0,sched_decision[63:32]);bus(0,3,0,0,0,13,0,0,sched_meta);bus(0,3,0,0,0,15,0,0,sched_vl);
   $fwrite(fd_rtc,"SAMPLE attempt=%0d correction_before=%0d correction_after=%0d flags=%0d snapshot_seconds=%0d snapshot_ns=%0d snapshot_tick=%0d target_seconds=%0d target_ns=%0d apply_tick=%0d sched_candidate=%0d sched_decision=%0d sched_meta=%08x sched_vl=%0d time_ns=%0d ",attempt,before_count,after_count,flags,rs,rn,st,target_sec,target_ns,apply_tick,sched_candidate,sched_decision,sched_meta,sched_vl,$time);
   for(j=0;j<32;j=j+1)$fwrite(fd_rtc,"w%0d=%08x ",j,samples[j]);$fwrite(fd_rtc,"\n");tbus(1,6,0,x);
  end
  ck(rtc_success==1 && rtc_timeout==0,"one_real_external_sample_correction",1,rtc_success);rtc_done=1;
 end endtask

 parameter CHECKPOINT_MODE=0,RUN_GROUP=0;
 reg [63:0] post_candidate,post_decision;
 reg checkpoint_ready=0,resume_go=0,reference_override=0;integer selected_group=0;
 reg drop_data_ACK=0,wide_probe=0;reg [31:0] captured_tag=0;
 integer physical_reset_base=0;
 task final_accounting;reg [31:0] submitted,client_done,line_done,context,tick;begin
  pause(400);lbus(0,23,0,0,submitted);lbus(0,24,0,0,client_done);lbus(0,25,0,0,line_done);lbus(0,26,0,0,context);lbus(0,27,0,0,tick);
  ck(submitted==tftp_frames,"all_accepted_TFTP_commands_have_actual_GMII_frame",tftp_frames,submitted);
  ck(client_done==submitted && line_done==submitted,"client_complete_and_line_complete_separately_close",submitted,line_done);
  $fdisplay(fd_events,"PUBLIC_COUNTS submit=%0d client=%0d line=%0d physical_epoch=%0d last_context=%08x last_tick=%0d time_ns=%0d",submitted,client_done,line_done,tftp_frames,context,tick,$time);
 end endtask
 task begin_case;input [511:0] name;begin cases=cases+1;case_name=name;$display("C42_CASE %0d %0s time_ps=%0t",cases,name,$time);fd_progress=$fopen("live-progress.json","w");$fdisplay(fd_progress,"{\"case\":%0d,\"name\":\"%0s\",\"checks\":%0d,\"time_ps\":%0t}",cases,name,checks,$time);$fclose(fd_progress);end endtask
 task lbus;input writing;input integer address;input [31:0] data;input expected_error;output [31:0] answer;
 begin bus(writing,3,0,0,((address>>4)<<4)|4,address&15,data,expected_error,answer);end endtask
 function [7:0] pattern;input integer k,seed;begin pattern=(k*73+(k>>8)*91+seed)&255;end endfunction
 function [31:0] crc_octet;input [31:0] c;input [7:0] b;reg [31:0] x;integer k;begin x=c^b;for(k=0;k<8;k=k+1)x=x[0]?(x>>1)^32'hedb88320:x>>1;crc_octet=x;end endfunction
 function [15:0] complement;input integer sum;integer n;begin n=(sum&65535)+(sum>>16);n=(n&65535)+(n>>16);complement=~n;end endfunction
 task expect_reply;input integer op,num,net,port,source,commits;begin
  $fdisplay(fd_events,"EXPECT epoch=%0d q=%0d op=%0d num=%0d net=%0d port=%0d source=%0d commits=%0d",model_epoch,qtail,op,num,net,port,source,commits);
  exp_op[qtail]=op;exp_number[qtail]=num;exp_net[qtail]=net;exp_port[qtail]=port;exp_source[qtail]=source;exp_commits[qtail]=commits;exp_drop[qtail]=0;exp_bytes[qtail]=-1;exp_seed[qtail]=0;exp_offset[qtail]=0;qtail=qtail+1;
 end endtask
 task await_replies;integer n;begin n=0;while(qhead!=qtail && n<2000000)begin @(negedge clk);n=n+1;end ck(qhead==qtail,"bounded_functional_reply",qtail,qhead);pause(200);end endtask
 task request;input integer opcode;input [39:0] mode;input integer options;integer k;reg [79:0] name;begin
  name="upload.bin";message[0]=0;message[1]=opcode;
  for(k=0;k<10;k=k+1)message[k+2]=name[79-k*8-:8];message[12]=0;
  for(k=0;k<5;k=k+1)message[13+k]=mode[39-k*8-:8];message[18]=0;message_length=19;
  if(options)begin
   {message[19],message[20],message[21],message[22],message[23],message[24],message[25]}="blksize";message[26]=0;
   {message[27],message[28],message[29],message[30]}="2048";message[31]=0;message_length=32;
  end
 end endtask
 task data_block;input integer n,seed;integer k;begin message[0]=0;message[1]=3;message[2]=0;message[3]=1;for(k=0;k<n;k=k+1)message[k+4]=pattern(k,seed);message_length=n+4;end endtask
 task build_frame;input integer damage;integer k,sum,n,ul;reg [15:0] c;reg [31:0] crc;begin
  for(k=0;k<2048;k=k+1)inj[k]=0;
  for(k=0;k<7;k=k+1)inj[k]=8'h55;inj[7]=8'hd5;
  {inj[8],inj[9],inj[10],inj[11],inj[12],inj[13]}=48'h020000001001;
  {inj[14],inj[15],inj[16],inj[17],inj[18],inj[19]}=sender_mac;inj[20]=8'h08;
  inj[22]=8'h45;{inj[24],inj[25]}=message_length+28;{inj[26],inj[27]}=rx_frames;inj[28]=8'h40;inj[30]=64;inj[31]=17;
  {inj[34],inj[35],inj[36],inj[37]}=sender_ip;{inj[38],inj[39],inj[40],inj[41]}=32'hc000020a;
  sum=0;for(k=22;k<42;k=k+2)sum=sum+{inj[k],inj[k+1]};{inj[32],inj[33]}=complement(sum);
  {inj[42],inj[43]}=sender_port;{inj[44],inj[45]}=destination;ul=message_length+8;{inj[46],inj[47]}=ul;
  for(k=0;k<message_length;k=k+1)inj[50+k]=message[k];
  sum=17+ul;for(k=34;k<42;k=k+2)sum=sum+{inj[k],inj[k+1]};
  for(k=42;k<50+message_length;k=k+2)sum=sum+{inj[k],inj[k+1]};c=complement(sum);if(c==0)c=65535;
  if(damage==1)c=c^1;{inj[48],inj[49]}=c;
  if(damage==3)inj[47]=inj[47]-1;
  n=50+message_length;if(n<68)n=68;
  crc=32'hffffffff;for(k=8;k<n;k=k+1)crc=crc_octet(crc,inj[k]);crc=~crc;
  if(damage==2)crc=crc^1;
  for(k=0;k<4;k=k+1)inj[n+k]=crc[k*8+:8];inj_length=n+4;
 end endtask
 task inject_current;input integer net;integer ticket;begin
  enqueue_inj(net,0,ticket);while(lh[net]<=ticket)@(negedge clk);
 end endtask
 task send_message;input integer damage;begin build_frame(damage);inject_current(selected_network);end endtask
 task close_session;begin lbus(1,17,1,0,dummy);pause(60);end endtask
 task open_session;input integer net;begin
  selected_network=net;destination=69;sender_port=40001;sender_mac=48'h020000001004;sender_ip=32'hc000021e;
  request(2,"OcTeT",0);expect_reply(4,0,net,40001,0,expected_writes);send_message(0);await_replies;expected_opens=expected_opens+1;
  ck(store_opens==expected_opens,"ACK0_after_object_preparation",expected_opens,store_opens);destination=current_tid;
 end endtask
 reg store_was_blocked=0;reg [8:0] store_held;
 always @(posedge clk)begin
  cycles=cycles+1;
  if(rst_n)begin
   if(store_was_blocked)ck(store_tx_valid && {store_tx_last,store_tx_data}===store_held,"storage_link_backpressure_stability",store_held,{store_tx_last,store_tx_data});
   store_was_blocked=store_tx_valid && !store_tx_ready;store_held={store_tx_last,store_tx_data};
   if(store_event)begin $fdisplay(fd_events,"STORE epoch=%0d kind=%0d time_ns=%0d length=%0d writes=%0d",model_epoch,store_event_kind,$time,store_event_length,store_writes);if(store_event_kind==2)last_data_accept=$time;if(store_event_kind==3)last_store_complete=$time;if(store_event_kind==6)last_open_complete=$time;end

  end else store_was_blocked=0;
 end
 genvar net;
 generate for(net=0;net<2;net=net+1)begin:station
  wire tx_clk=net==0?phy_tx_clk:phy_b_tx_clk;wire tx_en=net==0?phy_tx_en:phy_b_tx_en;wire tx_er=net==0?phy_tx_er:phy_b_tx_er;wire [7:0] d=net==0?phy_txd:phy_b_txd;
  reg active=0;reg [7:0] cap[0:2047];integer n=0,k,source,op,num,sum,ul,fid,f,channel;reg [31:0] crc;time first,last_end=0;
  always @(posedge tx_clk)begin #0.001;
   if(!rst_n)begin active=0;last_end=0;end
   else if(tx_en)begin
    if(!active)begin active=1;n=0;first=$time;if(last_end!=0)ck($time-last_end>=96,"GMII_IFG_at_least12bytes",96,$time-last_end);end
    ck(!tx_er && n<2048,"GMII_known_eight_bit_data",0,tx_er);cap[n]=d;n=n+1;
   end else if(active)begin
    for(k=0;k<7;k=k+1)ck(cap[k]===8'h55,"preamble",8'h55,cap[k]);ck(cap[7]===8'hd5,"SFD",8'hd5,cap[7]);
    crc=32'hffffffff;for(k=8;k<n-4;k=k+1)crc=crc_octet(crc,cap[k]);crc=~crc;for(k=0;k<4;k=k+1)ck(cap[n-4+k]===crc[k*8+:8],"FCS",crc[k*8+:8],cap[n-4+k]);
    source={cap[42],cap[43]};
    if(source==161)begin
     if({cap[44],cap[45]}==162)begin trap_frames=trap_frames+1;if(!link_a_down)trap_received=trap_received+1;end
     else begin ck(net==1,"SNMP_reply_returns_on_B",1,net);snmp_replies=snmp_replies+1;end
    end else if(source==45000)begin
     ck(net==0 && n==102 && {cap[44],cap[45]}==123,"real_A_only_SNTP_request",102,n);
     ck(cap[50]==8'h23,"SNTP_client_version_mode",8'h23,cap[50]);server_origin[ntp_requests]=0;
     for(k=90;k<98;k=k+1)server_origin[ntp_requests]={server_origin[ntp_requests][55:0],cap[k]};
     server_request[ntp_requests]=first+56;
     $fdisplay(fd_rtc,"REQUEST id=%0d token=%016h SFD_ns=%0d time_ns=%0d A_down=%0d",ntp_requests,server_origin[ntp_requests],first+56,$time,link_a_down);ntp_requests=ntp_requests+1;
    end else if(cap[8]==3)begin
     fid=-1;
     for(f=0;f<64;f=f+1)if(app_meta[f*4]=={cap[12],cap[13]} && app_meta[f*4+2]==cap[n-5])fid=f;
     ck(fid>=0 && app_sent[fid],"wire_has_accepted_input_identity",1,fid>=0);
     ck(n==app_meta[fid*4+3],"independent_wire_length",app_meta[fid*4+3],n);
     for(k=0;k<n;k=k+1)ck(cap[k]==(net?app_gold_b[fid*2048+k]:app_gold_a[fid*2048+k]),"independent_full_frame_headers_payload_SN_FCS",net?app_gold_b[fid*2048+k]:app_gold_a[fid*2048+k],cap[k]);
     ck(!physical_mask[fid][net],"single_physical_copy_per_network",0,physical_mask[fid][net]);physical_mask[fid][net]=1;
     channel=net*2+(app_meta[fid*4]==16'h8001);
     if(last_rt_start[channel]!=0)ck(first-last_rt_start[channel]>=(app_meta[fid*4]==1?1000000:2000000),"actual_GMII_BAG_not_RTC",app_meta[fid*4]==1?1000000:2000000,first-last_rt_start[channel]);
     last_rt_start[channel]=first;
     $fdisplay(fd_app,"WIRE id=%0d network=%0d first_ns=%0d end_ns=%0d peer_received=%0d",fid,net,first,$time,net || !link_a_down);
     if(net || !link_a_down)enqueue_app(net,fid);
     if(net==1)latest_loop_id=fid;
     rt_frames=rt_frames+1;
    end else begin
     tftp_frames=tftp_frames+1;
     ck(qtail<512,"wire_capture_queue_bounded",512,qtail);
     ck({cap[8],cap[9],cap[10],cap[11],cap[12],cap[13]}==48'h020000001004,"loader_MAC",48'h020000001004,{cap[8],cap[9],cap[10],cap[11],cap[12],cap[13]});
     ck({cap[14],cap[15],cap[16],cap[17],cap[18],cap[19]}==48'h020000001001,"DUT_MAC",48'h020000001001,{cap[14],cap[15],cap[16],cap[17],cap[18],cap[19]});
     ck({cap[34],cap[35],cap[36],cap[37]}==32'hc000020a && {cap[38],cap[39],cap[40],cap[41]}==32'hc000021e,"IP_endpoints",32'hc000021e,{cap[38],cap[39],cap[40],cap[41]});
     sum=0;for(k=22;k<42;k=k+2)sum=sum+{cap[k],cap[k+1]};ck(complement(sum)==0,"IP_checksum",0,complement(sum));
     ul={cap[46],cap[47]};ck({cap[24],cap[25]}==ul+20 && n==((ul+34<60?60:ul+34)+12),"length_no_AFDDX_SN",ul+46,n);
     sum=17+ul;for(k=34;k<42;k=k+2)sum=sum+{cap[k],cap[k+1]};for(k=42;k<42+ul;k=k+2)sum=sum+{cap[k],k+1<42+ul?cap[k+1]:8'd0};ck(complement(sum)==0,"UDP_checksum",0,complement(sum));
     wire_offer_time[qtail]=offered[source];offered[source]=0;wire_len[qtail]=ul-8;wire_source[qtail]=source;wire_port[qtail]={cap[44],cap[45]};wire_net[qtail]=net;
     for(k=0;k<ul-8;k=k+1)wire_bytes[qtail*516+k]=cap[50+k];
     for(k=42+ul;k<n-4;k=k+1)ck(cap[k]==0,"Ethernet_padding_not_file",0,cap[k]);
     $fdisplay(fd_peer,"WIRE q=%0d op=%0d block=%0d source=%0d destination=%0d first_ns=%0d end_ns=%0d",qtail,{cap[50],cap[51]},{cap[52],cap[53]},source,{cap[44],cap[45]},first,$time);qtail=qtail+1;
    end
    if(net==0 && link_a_down)$fdisplay(fd_links,"TX_DROP net=0 source=%0d first_ns=%0d end_ns=%0d",source,first,$time);
    $fwrite(fd_wire,"%0d %0d %0d ",net,first,$time);for(k=0;k<n;k=k+1)$fwrite(fd_wire,"%02x",cap[k]);$fwrite(fd_wire,"\n");tx_frames=tx_frames+1;active=0;last_end=$time;
   end
  end
 end endgenerate
 task real_tx;integer k;reg [31:0] b;begin
  @(negedge clk);app_tx_cmd_valid=1;app_tx_cmd_index=0;app_tx_cmd_length=4;
  @(posedge clk);while(!app_tx_cmd_ready)@(posedge clk);@(negedge clk);app_tx_cmd_valid=0;b=32'hdeadbeef;
  for(k=0;k<4;k=k+1)begin app_tx_valid=1;app_tx_data=b[31-k*8-:8];app_tx_last=k==3;@(posedge clk);while(!app_tx_ready)@(posedge clk);@(negedge clk);app_tx_valid=0;pause(2);end
  app_tx_last=0;app_tx_commit_valid=1;@(posedge clk);while(!app_tx_commit_ready)@(posedge clk);@(negedge clk);app_tx_commit_valid=0;
 end endtask
 task setup;integer p,k,idx;begin
  lbus(1,19,1,0,dummy);while(!init_done)@(negedge clk);
  for(p=0;p<5;p=p+1)begin idx=p==0?0:p==1?127:p==2?0:p==3?4095:2048;
   for(k=0;k<8;k=k+1)bus(1,0,p>=2,1,idx,k,app_config[p*8+k],0,dummy);
  end
  commit_config(0);application_enable=1;app_tx_error_ready=1;
  bus(0,0,0,0,127,7,0,0,value);ck(value[15:0]==16'h8001,"real_active_TX127_full_VLID",16'h8001,value[15:0]);
  bus(0,0,1,0,4095,7,0,0,value);ck(value[15:0]==16'h8001,"real_RX4095_high_VLID",16'h8001,value[15:0]);
 end endtask
 task expect_data;input integer block,n,offset,seed,net,source;begin
  expect_reply(3,block,net,40001,source,expected_writes);exp_bytes[qtail-1]=n;exp_seed[qtail-1]=seed;exp_offset[qtail-1]=offset;
  $fdisplay(fd_events,"DATA_EXPECT q=%0d n=%0d offset=%0d seed=%0d",qtail-1,n,offset,seed);
 end endtask
 task make_data;input integer block,n,offset,seed;integer j;begin
  data_block(n,seed);{message[2],message[3]}=block;
  for(j=0;j<n;j=j+1)message[4+j]=pattern(offset+j,seed);
 end endtask
 task make_ack;input integer block;begin message[0]=0;message[1]=4;{message[2],message[3]}=block;message_length=4;end endtask
 task disk_readback;input integer n,seed;integer j;begin
  ck(object_valid && object_complete && object_length==n,"complete_object_real_length",n,object_length);
  $fdisplay(fd_events,"READ_EXPECT epoch=%0d commit=%0d n=%0d seed=%0d",model_epoch,expected_writes,n,seed);
  for(j=0;j<n;j=j+1)begin
   if(j%512==0)lbus(1,18,j,0,dummy);lbus(0,32+(j%512),0,0,value);
   ck(value==pattern(j,seed),"whole_file_actual_storage_readback",pattern(j,seed),value);$fdisplay(fd_read,"%0d %0d %0d %02x",model_epoch,upload_index,j,value);
  end
  lbus(1,18,0,0,dummy);
 end endtask
 task write_file;input integer n,seed,net;integer off,b,chunk,start_writes;reg [31:0] files_before;begin
  close_session;lbus(0,10,0,0,files_before);open_session(net);start_writes=store_writes;off=0;b=1;
  $fdisplay(fd_events,"FILE_WRITE epoch=%0d tid=%0d n=%0d seed=%0d",model_epoch,current_tid,n,seed);
  begin:write_loop
   forever begin
    chunk=n-off;if(chunk>512)chunk=512;make_data(b,chunk,off,seed);
    expected_writes=expected_writes+1;expect_reply(4,b,net,40001,current_tid,expected_writes);send_message(0);await_replies;
    ck(object_length==off+chunk,"block_appends_exact_offset",off+chunk,object_length);
    ck(object_valid==(chunk<512),"full_prefix_not_published_as_file",chunk<512,object_valid);
    lbus(0,10,0,0,value);ck(value==files_before+(chunk<512),"file_success_only_final_store",files_before+(chunk<512),value);
    if(chunk<512)disable write_loop;off=off+chunk;b=b+1;
   end
  end
  ck(store_writes-start_writes==(n/512)+1,"exact_commits_including_zero_terminal",n/512+1,store_writes-start_writes);
  disk_readback(n,seed);
 end endtask
 task read_file;input integer n,seed,net;integer begin_q;integer off,b,chunk,start_reads,seen;reg [31:0] files_before;begin
  close_session;lbus(0,11,0,0,files_before);selected_network=net;sender_port=40001;destination=69;request(1,"octet",0);
  begin_q=qtail;start_reads=store_reads;off=0;b=1;chunk=n;if(chunk>512)chunk=512;
  expect_data(b,chunk,off,seed,net,0);send_message(0);await_replies;destination=current_tid;
  $fdisplay(fd_events,"FILE_READ epoch=%0d tid=%0d n=%0d seed=%0d",model_epoch,current_tid,n,seed);
  begin:read_loop
   forever begin
    // Neither duplicate ACK of the previous block nor a future ACK may send
    // or advance DATA. This is checked at the actual GMII wire, not a state bit.
    seen=qhead;make_ack(b-1);send_message(0);pause(1500);make_ack(b+1);send_message(0);pause(1500);
    ck(qhead==seen,"duplicate_and_future_ACK_no_immediate_DATA",seen,qhead);
    lbus(0,11,0,0,value);ck(value==files_before,"RRQ_no_success_before_final_ACK",files_before,value);
    make_ack(b);
    if(chunk<512)begin send_message(0);pause(2500);disable read_loop;end
    off=off+chunk;b=b+1;chunk=n-off;if(chunk>512)chunk=512;
    expect_data(b,chunk,off,seed,net,current_tid);send_message(0);await_replies;
   end
  end
  ck(store_reads-start_reads==(n+511)/512,"RRQ_only_real_nonzero_store_READs",(n+511)/512,store_reads-start_reads);
  lbus(0,2,0,0,value);ck(!value[0],"RRQ_final_ACK_releases_session",0,value[0]);
  lbus(0,11,0,0,value);ck(value==files_before+1,"RRQ_final_ACK_counts_success_once",files_before+1,value);
  $fdisplay(fd_peer,"FILE_RRQ epoch=%0d first_q=%0d end_q=%0d n=%0d seed=%0d success=1",model_epoch,begin_q,qhead,n,seed);
 end endtask
 task timed_retry;input integer block,n,offset,seed,source,previous,ticks,drop;integer q;begin
  q=qtail;expect_data(block,n,offset,seed,selected_network,source);exp_drop[q]=drop;
  $fdisplay(fd_peer,"RETX_EXPECT q=%0d previous=%0d ticks=%0d",q,previous,ticks);
  await_replies;
  ck(wire_start[q]>=wire_end[previous]-8+ticks*10,"RTO_after_physical_FCS_no_early_retransmit",wire_end[previous]-8+ticks*10,wire_start[q]);
  ck(wire_start[q]<=wire_end[previous]+ticks*10+1200000,"retry_progress_under_frozen_management_budget",wire_end[previous]+ticks*10+1200000,wire_start[q]);
 end endtask
 task rrq_loss;input integer n,seed,drop_data,drop_ack;integer off,b,chunk,prior,once_data,once_ack,begin_q,read_ops;reg [31:0] files_before;reg [15:0] monitor_tid;begin
  close_session;media.preload(n,seed);lbus(0,11,0,0,files_before);selected_network=0;sender_port=40001;destination=69;request(1,"octet",0);
  off=0;b=1;chunk=n;if(chunk>512)chunk=512;begin_q=qtail;read_ops=store_reads;once_data=0;once_ack=0;
  expect_data(1,chunk,0,seed,0,0);if(drop_data==1)begin exp_drop[qtail-1]=1;once_data=1;end send_message(0);await_replies;
  begin:rrq_loop
   forever begin
    prior=qhead-1;
    if(drop_data==b && once_data==1)begin
     monitor_tid=station[0].source;timed_retry(b,chunk,off,seed,b==1?0:current_tid,prior,200000,0);
     ck(current_tid==monitor_tid,"DATA_retransmission_same_server_TID",monitor_tid,current_tid);once_data=2;
    end
    destination=current_tid;
    if(drop_ack==b && once_ack==0)begin
     $fdisplay(fd_peer,"CLIENT_DROP direction=to_DUT op=4 block=%0d occurrence=1 time_ns=%0d",b,$time);once_ack=1;
     timed_retry(b,chunk,off,seed,current_tid,qhead-1,200000,0);
    end
    make_ack(b);
    if(chunk<512)begin send_message(0);pause(2500);disable rrq_loop;end
    off=off+chunk;b=b+1;chunk=n-off;if(chunk>512)chunk=512;
    expect_data(b,chunk,off,seed,0,current_tid);if(drop_data==b)begin exp_drop[qtail-1]=1;once_data=1;end
    send_message(0);await_replies;
   end
  end
  lbus(0,11,0,0,value);ck(value==files_before+1,"RRQ_one_confirmed_success_after_loss",files_before+1,value);
  ck(store_reads-read_ops==(n+511)/512,"RRQ_retries_use_immutable_cache_not_re_reads",(n+511)/512,store_reads-read_ops);
  $fdisplay(fd_peer,"FILE_RRQ epoch=%0d first_q=%0d end_q=%0d n=%0d seed=%0d success=1",model_epoch,begin_q,qhead,n,seed);
 end endtask
 task wrq_loss;input integer n,seed,lose_ack0,lose_data,lose_ack;integer off,b,chunk,before_count,opens_before,begin_q;reg [15:0] monitor_tid;reg [31:0] files_before;begin
  close_session;selected_network=0;sender_port=40001;destination=69;request(2,"octet",0);opens_before=store_opens;before_count=store_writes;begin_q=qtail;lbus(0,10,0,0,files_before);
  expect_reply(4,0,0,40001,0,expected_writes);exp_drop[qtail-1]=lose_ack0;send_message(0);await_replies;
  if(lose_ack0)begin
   monitor_tid=station[0].source;pause(200000);destination=69;request(2,"octet",0);expect_reply(4,0,0,40001,0,expected_writes);send_message(0);await_replies;
   ck(current_tid==monitor_tid,"duplicate_WRQ_reuses_ACK0_TID",monitor_tid,current_tid);
  end
  expected_opens=expected_opens+1;ck(store_opens==opens_before+1,"WRQ_retry_exactly_one_OPEN",opens_before+1,store_opens);destination=current_tid;off=0;b=1;
  begin:wrq_loop
   forever begin
    chunk=n-off;if(chunk>512)chunk=512;make_data(b,chunk,off,seed);
    if(lose_data==b)begin
     $fdisplay(fd_peer,"CLIENT_DROP direction=to_DUT op=3 block=%0d occurrence=1 time_ns=%0d",b,$time);pause(200000);
     ck(store_writes==before_count+b-1,"dropped_DATA_has_no_store_commit",before_count+b-1,store_writes);
    end
    expected_writes=expected_writes+1;expect_reply(4,b,0,40001,current_tid,expected_writes);exp_drop[qtail-1]=lose_ack==b;send_message(0);await_replies;
    if(lose_ack==b)begin
     pause(200000);expect_reply(4,b,0,40001,current_tid,expected_writes);send_message(0);await_replies;
    end
    ck(store_writes==before_count+b,"duplicate_DATA_does_not_rewrite",before_count+b,store_writes);
    if(chunk<512)disable wrq_loop;off=off+chunk;b=b+1;
   end
  end
  disk_readback(n,seed);lbus(0,10,0,0,value);ck(value==files_before+1,"one_complete_WRQ_with_duplicate_final",files_before+1,value);
  $fdisplay(fd_peer,"FILE_WRQ epoch=%0d first_q=%0d end_q=%0d n=%0d seed=%0d success=1",model_epoch,begin_q,qhead,n,seed);
 end endtask
 parameter DOWNLOAD_DIR="vectors/615a/c36",SMOKE=0;
 reg [7:0] download_gold[0:65535],list_gold[0:31],answer_gold[0:18];
 integer fd_download,fd_control,dn_id=0,dn_size=0,dn_choice=0,dn_bad=0,dn_cancel=0;
 integer dn_tid=0,control_tid=0,control_kind=0,expected_block=1,received_bytes=0,final_ack=0;
 integer dropped_middle=0,dropped_final=0,replay_count=0,final_lns=0,lists_seen=0,control_seen=0;
 integer last_dn_counter=0,last_control_len=0,last_control_counter=0;reg [7:0] last_control[0:511];
 task dbus;input writing;input integer address;input [31:0] data;output [31:0] answer;
 begin bus(writing,3,0,0,((address>>4)<<4)|9,address&15,data,0,answer);end endtask
 task dn_next;integer t;begin
  t=0;while(qhead==qtail && t<4000000)begin @(negedge clk);t=t+1;end
  ck(qhead<qtail,"bounded_download_protocol_frame",1,qtail-qhead);
 end endtask
 task dn_ack;input integer tid,b,port;begin destination=tid;sender_port=port;make_ack(b);send_message(0);pause(100);end endtask
 task dn_name;input integer id;input [87:0] text;input integer n;integer j;begin
  ck(wire_len[id]==n+9,"download_WRQ_filename_octet_length",n+9,wire_len[id]);
  for(j=0;j<n;j=j+1)ck(wire_bytes[id*516+2+j]==text[(n-1-j)*8+:8],"download_actual_filename",text[(n-1-j)*8+:8],wire_bytes[id*516+2+j]);
  ck(wire_bytes[id*516+2+n]==0 && {wire_bytes[id*516+3+n],wire_bytes[id*516+4+n],wire_bytes[id*516+5+n],wire_bytes[id*516+6+n],wire_bytes[id*516+7+n],wire_bytes[id*516+8+n]}=={"octet",8'd0},"download_octet_and_terminators",0,0);
 end endtask
 task dn_process;integer id,op,b,n,j,c,code,offset,expected_n;reg [87:0] name;begin
  dn_next;id=qhead;qhead=qhead+1;op={wire_bytes[id*516],wire_bytes[id*516+1]};b={wire_bytes[id*516+2],wire_bytes[id*516+3]};n=wire_len[id]-4;
  ck(wire_net[id]==selected_network,"download_network_snapshot",selected_network,wire_net[id]);
  if(op==2)begin
   ck(wire_port[id]==59,"ODD_initial_WRQ_destination59",59,wire_port[id]);
   if(wire_source[id]>=35000 && wire_source[id]<=39999)begin
    ck(!dn_bad,"invalid_selection_has_no_data_WRQ",0,dn_bad);name=dn_choice?"BIG64.BIN":"SMALL.BIN";dn_name(id,name,9);dn_tid=wire_source[id];
    if(dn_cancel)begin dbus(1,0,2,dummy);$fdisplay(fd_peer,"CANCEL_DOWNLOAD_AFTER_DUT_WRQ id=%0d tid=%0d time_ns=%0d",dn_id,dn_tid,$time);end
    else dn_ack(dn_tid,0,42010);
   end else begin
    ck(wire_source[id]>=45001 && wire_source[id]<=49151,"ODD_status_TID_partition",45001,wire_source[id]);control_tid=wire_source[id];
    if(wire_bytes[id*516+12]=="L")begin dn_name(id,"AFDX_01.LNL",11);control_kind=1;end
    else begin dn_name(id,"AFDX_01.LNS",11);control_kind=2;end
    dn_ack(control_tid,0,41000);
   end
  end else if(op==3 && wire_source[id]>=45001)begin
   ck(wire_source[id]==control_tid && wire_port[id]==41000 && b==1,"control_DATA_context_and_block1",control_tid,wire_source[id]);
   $fwrite(fd_control,"%0d %0d %0d %0d ",dn_id,control_kind,$time,n);for(j=0;j<n;j=j+1)$fwrite(fd_control,"%02x",wire_bytes[id*516+4+j]);$fwrite(fd_control,"\n");
   if(control_kind==1)begin
    ck(n==32,"actual_two_entry_LNL_length",32,n);for(j=0;j<32;j=j+1)ck(wire_bytes[id*516+4+j]==list_gold[j],"actual_LNL_independent_bytes",list_gold[j],wire_bytes[id*516+4+j]);lists_seen=lists_seen+1;
   end else begin
    ck(n==20 || n==34,"LNS_independent_format_not_LUS",34,n);
    ck({wire_bytes[id*516+4],wire_bytes[id*516+5],wire_bytes[id*516+6],wire_bytes[id*516+7]}==n && {wire_bytes[id*516+8],wire_bytes[id*516+9]}=="A4","LNS_length_and_version",n,wire_bytes[id*516+7]);
    code={wire_bytes[id*516+10],wire_bytes[id*516+11]};c={wire_bytes[id*516+13],wire_bytes[id*516+14]};
    ck(code==1 || code==2 || code==3 || code==16'h1003,"LNS_formal_status",2,code);
    ck(c==last_dn_counter+1,"LNS_counter_one_per_snapshot",last_dn_counter+1,c);last_dn_counter=c;
    ck({wire_bytes[id*516+19],wire_bytes[id*516+20],wire_bytes[id*516+21]}==(code==3?24'h313030:24'h202030),"LNS_ASCII_list_ratio",code==3?100:0,wire_bytes[id*516+21]);
    if(n==34)begin
     ck(wire_bytes[id*516+24]==10 && wire_bytes[id*516+34]==0 && wire_bytes[id*516+37]==0,"LNS_entry_filename_and_empty_description",10,wire_bytes[id*516+24]);
     name=dn_choice?"BIG64.BIN":"SMALL.BIN";for(j=0;j<9;j=j+1)ck(wire_bytes[id*516+25+j]==name[64-j*8+:8],"LNS_selected_filename",name[64-j*8+:8],wire_bytes[id*516+25+j]);
     ck({wire_bytes[id*516+35],wire_bytes[id*516+36]}==code,"LNS_entry_status",code,{wire_bytes[id*516+35],wire_bytes[id*516+36]});
    end
    if(code==3 || code==16'h1003)begin
     ck(code==((dn_bad || drop_data_ACK)?16'h1003:16'd3),"operation_result_matches_selection",(dn_bad || drop_data_ACK)?16'h1003:3,code);
     if(code==3)ck(final_ack && received_bytes==dn_size,"LNS_complete_requires_actual_matching_final_DATA_ACK",dn_size,received_bytes);
     dbus(0,1,0,value);ck(!value[2],"operation_not_complete_before_final_LNS_ACK",0,value);final_lns=code;
    end
    control_seen=control_seen+1;
   end
   dn_ack(control_tid,1,41000);
  end else if(op==3 && wire_source[id]>=35000 && wire_source[id]<=39999)begin
   ck(!dn_cancel && !dn_bad && wire_source[id]==dn_tid && wire_port[id]==42010,"selected_data_context",dn_tid,wire_source[id]);
   ck(b==expected_block || b==expected_block-1,"download_block_order",expected_block,b);offset=(b-1)*512;expected_n=dn_size-offset;if(expected_n>512)expected_n=512;
   ck(offset>=0 && expected_n>=0 && n==expected_n,"actual_DATA_length_including_zero_terminal",expected_n,n);
   for(j=0;j<n;j=j+1)ck(wire_bytes[id*516+4+j]==download_gold[offset+j],"independent_download_byte_at_full_address",download_gold[offset+j],wire_bytes[id*516+4+j]);
   if(b==expected_block)begin
    $fwrite(fd_download,"%0d %0d %0d %0d ",dn_id,b,offset,n);for(j=0;j<n;j=j+1)$fwrite(fd_download,"%02x",wire_bytes[id*516+4+j]);$fwrite(fd_download,"\n");received_bytes=received_bytes+n;expected_block=expected_block+1;
   end else replay_count=replay_count+1;
   if(wide_probe && b==1)begin c37_wide;end
   else if(drop_data_ACK)begin $fdisplay(fd_peer,"DROP_ALL_DATA_ACK id=%0d block=%0d time_ns=%0d",dn_id,b,$time);end
   else if(dn_size==65536 && b==65 && !dropped_middle)begin dropped_middle=1;$fdisplay(fd_peer,"DROP_DOWNLOAD_ACK id=%0d block=65 time_ns=%0d",dn_id,$time);end
   else if(dn_size==65536 && b==129 && !dropped_final)begin
    dropped_final=1;dbus(0,1,0,value);ck(!value[1] && !value[2],"unconfirmed_final_zero_never_file_or_operation_success",0,value);
    dn_ack(dn_tid,128,42010);$fdisplay(fd_peer,"DROP_FINAL_ACK_AND_INJECT_OLD128 id=%0d time_ns=%0d",dn_id,$time);
   end else begin
    dn_ack(dn_tid,b,42010);if(n<512)begin final_ack=1;$fdisplay(fd_events,"DATA_FINAL_ACK id=%0d block=%0d bytes=%0d time_ns=%0d",dn_id,b,received_bytes,$time);end
   end
  end else if(op==4 && wire_source[id]>=49152)begin ck(b==1,"LNA_stored_before_ACK1",1,b);end
  else ck(0,"unexpected_ODD_operation",2,op);
 end endtask
 task start_download;input integer choose,net,bad_select,cancel_it;integer t,j;reg [87:0] name;begin
  dn_id=dn_id+1;dn_choice=choose;dn_size=choose?65536:37;dn_bad=bad_select;dn_cancel=cancel_it;received_bytes=0;expected_block=1;final_ack=0;final_lns=0;dropped_middle=0;dropped_final=0;dn_tid=0;
  $sformat(path,"%0s/data_%0s.hex",DOWNLOAD_DIR,choose?"big":"small");$readmemh(path,download_gold,0,dn_size-1);
  $sformat(path,"%0s/%0s_lna.hex",DOWNLOAD_DIR,choose?"big":"small");$readmemh(path,answer_gold,0,18);
  close_session;dbus(1,1,1000000,dummy);dbus(1,2,200000000,dummy);dbus(1,0,1,dummy);
  t=0;value=0;while(value[4:0]!=2 && t<1000)begin pause(20);dbus(0,0,0,value);t=t+1;end ck(value[4:0]==2,"LNO_prepared_by_RTL",2,value);
  selected_network=net;sender_mac=48'h020000001004;sender_ip=32'hc000021e;sender_port=40001;destination=59;
  name="AFDX_01.LNO";message[0]=0;message[1]=1;for(j=0;j<11;j=j+1)message[2+j]=name[87-j*8-:8];message[13]=0;{message[14],message[15],message[16],message[17],message[18],message[19]}={"octet",8'd0};message_length=20;send_message(0);
  dn_next;ck(wire_len[qhead]==19 && wire_bytes[qhead*516+1]==3,"LNO_actual_DATA1",19,wire_len[qhead]);
  ck({wire_bytes[qhead*516+8],wire_bytes[qhead*516+9]}=="A4" && wire_bytes[qhead*516+11]==1,"LNO_A4_accepted",1,wire_bytes[qhead*516+11]);current_tid=wire_source[qhead];qhead=qhead+1;dn_ack(current_tid,1,40001);
  t=0;value=0;while(value[4:0]!=5 && t<10000)begin if(qhead<qtail)dn_process;else pause(200);dbus(0,0,0,value);t=t+1;end
  ck(value[4:0]==5,"LNS_accepted_and_LNL_confirmed_before_selection",5,value);ck(lists_seen==dn_id,"one_actual_two_file_list_per_initialization",dn_id,lists_seen);
  destination=59;sender_port=40001;message[0]=0;message[1]=2;name="AFDX_01.LNA";for(j=0;j<11;j=j+1)message[2+j]=name[87-j*8-:8];message[13]=0;{message[14],message[15],message[16],message[17],message[18],message[19]}={"octet",8'd0};message_length=20;send_message(0);
  dn_next;ck(wire_bytes[qhead*516+1]==4 && wire_bytes[qhead*516+3]==0,"actual_LNA_WRQ_ACK0",0,wire_bytes[qhead*516+3]);current_tid=wire_source[qhead];qhead=qhead+1;
  destination=current_tid;message[0]=0;message[1]=3;message[2]=0;message[3]=1;for(j=0;j<19;j=j+1)message[4+j]=answer_gold[j];if(bad_select==1)message[13]="X";else if(bad_select==2)message[9]="3";message_length=23;send_message(0);
  $fdisplay(fd_events,"DOWNLOAD_BEGIN id=%0d bytes=%0d net=%0d bad=%0d cancel=%0d time_ns=%0d",dn_id,dn_size,net,bad_select,cancel_it,$time);
 end endtask
 task finish_download;input integer cancel_it;integer t;reg [31:0] read_before,ops_before,lock_before,unlock_before;begin
  read_before=media.data_read_bytes;ops_before=media.data_read_requests;lock_before=media.locks;unlock_before=media.unlocks;t=0;value=0;
  while(value[4:0]!=22 && value[4:0]!=23 && t<300000)begin
   if(qhead<qtail)dn_process;else pause(200);dbus(0,0,0,value);t=t+1;
  end
  ck(value[4:0]==((dn_bad || drop_data_ACK || cancel_it)?23:22),"bounded_ODD_terminal_state",dn_bad || drop_data_ACK || cancel_it?23:22,value[4:0]);
  if(!dn_bad && !drop_data_ACK && !cancel_it)begin
   ck(final_lns==3 && final_ack && received_bytes==dn_size,"complete_file_and_final_status",dn_size,received_bytes);
   dbus(0,5,0,value);ck(value==dn_size,"public_17bit_actual_file_length",dn_size,value);
   ck(media.data_read_bytes-read_before==dn_size && media.data_read_requests-ops_before==(dn_size+511)/512,"real_storage_READ_once_per_block_no_zero_or_retry_read",dn_size,media.data_read_bytes-read_before);
   ck(media.locks-lock_before==1 && media.unlocks-unlock_before==1,"one_snapshot_lease_and_release",1,media.unlocks-unlock_before);
  end
  if(cancel_it)begin
   while(qhead<qtail)begin
    ck(wire_source[qhead]==control_tid && wire_bytes[qhead*516+1]==3 && control_kind==2,"late_control_DATA_belongs_to_preexisting_WRQ",control_tid,wire_source[qhead]);
    $fdisplay(fd_events,"DRAIN_CANCELLED_CONTROL tid=%0d before_new_initialization time_ns=%0d",control_tid,$time);dn_process;
   end
  end
  pause(300);ck(media.locked_bank[6:5]==0 && media.state==0 && media.pos==0,"download_storage_resource_conservation",0,media.locked_bank[6:5]);
  if(cancel_it)begin
   // This case cancels after the data WRQ, while one in-progress LNS
   // snapshot has already been generated. It is not an on-wire success.
   dbus(0,9,0,value);
   ck(value==last_dn_counter+1 || value==last_dn_counter+2,"zero_or_one_cancelled_inflight_snapshot_requires_storage_proof",last_dn_counter+1,value);
   if(value==last_dn_counter+2)$fdisplay(fd_events,"CANCELLED_LNS snapshot=%0d next=%0d time_ns=%0d",last_dn_counter+1,value,$time);
   last_dn_counter=value-1;
  end
  $fdisplay(fd_events,"DOWNLOAD_END id=%0d bytes=%0d received=%0d bad=%0d cancel=%0d final_ACK=%0d LNS=%0d reads=%0d read_bytes=%0d time_ns=%0d",dn_id,dn_size,received_bytes,dn_bad,cancel_it,final_ack,final_lns,media.data_read_requests-ops_before,media.data_read_bytes-read_before,$time);
 end endtask
 task cbus;input writing;input integer address;input [31:0] data;output [31:0] answer;
 begin bus(writing,3,0,0,((address>>4)<<4)|5,address&15,data,0,answer);end endtask
 task ibus;input writing;input integer address;input [31:0] data;output [31:0] answer;
 begin bus(writing,3,0,0,((address>>4)<<4)|7,address&15,data,0,answer);end endtask
 task ubus;input writing;input integer address;input [31:0] data;output [31:0] answer;
 begin bus(writing,3,0,0,((address>>4)<<4)|8,address&15,data,0,answer);end endtask
 task next_wire;integer t;begin
  t=0;while(qhead==qtail && t<2000000)begin @(negedge clk);t=t+1;end
  ck(qhead<qtail,"bounded_protocol_frame_arrival",qtail,qhead);
 end endtask
 task pop;begin qhead=qhead+1;end endtask
 task send_ack_to;input integer source_tid,block,server_tid;begin destination=source_tid;sender_port=server_tid;make_ack(block);send_message(0);pause(200);end endtask
 task check_name;input integer id,op;input [255:0] text;input integer n;integer k;begin
  ck(wire_len[id]==n+9,"request_filename_octet_exact_length",n+9,wire_len[id]);
  ck(wire_bytes[id*516]==0 && wire_bytes[id*516+1]==op,"actual_DUT_initiated_operation",op,wire_bytes[id*516+1]);
  for(k=0;k<n;k=k+1)ck(wire_bytes[id*516+2+k]==text[255-k*8-:8],"actual_request_filename",text[255-k*8-:8],wire_bytes[id*516+2+k]);
  ck(wire_bytes[id*516+2+n]==0 && {wire_bytes[id*516+3+n],wire_bytes[id*516+4+n],wire_bytes[id*516+5+n],wire_bytes[id*516+6+n],wire_bytes[id*516+7+n],wire_bytes[id*516+8+n]}=={"octet",8'd0},"terminated_octet",0,0);
 end endtask
 task initialization;input integer net;integer k,t;reg [87:0] name;begin
  close_session;cbus(1,0,1,dummy);t=0;value=0;while(!value[1] && t<100)begin pause(40);cbus(0,0,0,value);t=t+1;end ck(value[1],"real_LUI_storage_provision",1,value[1]);
  ibus(1,9,10000000,dummy);ibus(1,0,1,dummy);ubus(1,1,1000000,dummy);ubus(1,2,20000000,dummy);
  selected_network=net;sender_mac=48'h020000001004;sender_ip=32'hc000021e;sender_port=40001;destination=59;
  name="AFDX_01.LUI";message[0]=0;message[1]=1;for(k=0;k<11;k=k+1)message[k+2]=name[87-k*8-:8];message[13]=0;
  {message[14],message[15],message[16],message[17],message[18],message[19]}={"octet",8'd0};message_length=20;send_message(0);
  next_wire;ck(wire_bytes[qhead*516+1]==3 && wire_len[qhead]==19,"actual_LUI_DATA1",19,wire_len[qhead]);
  ck({wire_bytes[qhead*516+4],wire_bytes[qhead*516+5],wire_bytes[qhead*516+6],wire_bytes[qhead*516+7]}==15,"LUI_length",15,wire_bytes[qhead*516+7]);
  current_tid=wire_source[qhead];pop;init_counter=init_counter+1;send_ack_to(current_tid,1,40001);
  next_wire;check_name(qhead,2,{"AFDX_01.LUS",168'd0},11);ck(wire_port[qhead]==59,"615A_notification_listener59",59,wire_port[qhead]);wr_tid=wire_source[qhead];pop;send_ack_to(wr_tid,0,41000);
  next_wire;ck(wire_len[qhead]==24 && wire_bytes[qhead*516+1]==3,"actual_initial_20byte_LUS",24,wire_len[qhead]);
  ck({wire_bytes[qhead*516+10],wire_bytes[qhead*516+11]}==1 && wire_bytes[qhead*516+21]=="0" && wire_bytes[qhead*516+23]==0,"accepted_zero_entry_not_completed",1,wire_bytes[qhead*516+11]);
  pop;ibus(0,1,0,value);ck(!value[0],"initialization_not_before_final_ACK",0,value);send_ack_to(wr_tid,1,41000);
  t=0;value=0;while(!value[0] && t<100)begin pause(50);ibus(0,1,0,value);t=t+1;end ck(value==1,"actual_initialization_waits_LUR",1,value);
  last_counter=init_counter;last_lus_len=0;last_lus_counter=0;
 end endtask
 task serve_data;integer k;begin
  rr_chunk=((rr_file==0?header_bytes:business_size)-rr_offset)>=512?512:((rr_file==0?header_bytes:business_size)-rr_offset);
  message[0]=0;message[1]=3;{message[2],message[3]}=rr_block;
  for(k=0;k<rr_chunk;k=k+1)message[k+4]=rr_file==0?hfile[rr_offset+k]:dfile[rr_offset+k];
  if(expected_bad==3 && rr_file==1 && rr_offset==0 && rr_chunk!=0)message[4]=message[4]^1;
  message_length=rr_chunk+4;destination=rr_tid;sender_port=42000;send_message(0);
  $fdisplay(fd_peer,"SERVER_DATA upload=%0d file=%0d block=%0d offset=%0d bytes=%0d source=42000 destination=%0d time=%0d",upload_index,rr_file,rr_block,rr_offset,rr_chunk,rr_tid,$time);
 end endtask
 task check_status;input integer id;integer k,n,c,code,p,ratio;begin
  n=wire_len[id]-4;c={wire_bytes[id*516+13],wire_bytes[id*516+14]};code={wire_bytes[id*516+10],wire_bytes[id*516+11]};
  ck(wire_bytes[id*516]==0 && wire_bytes[id*516+1]==3 && {wire_bytes[id*516+2],wire_bytes[id*516+3]}==1,"LUS_DATA_block1",1,wire_bytes[id*516+3]);
  ck({wire_bytes[id*516+4],wire_bytes[id*516+5],wire_bytes[id*516+6],wire_bytes[id*516+7]}==n,"LUS_declared_byte_length",n,wire_bytes[id*516+7]);
  ck({wire_bytes[id*516+8],wire_bytes[id*516+9]}=="A4" && wire_bytes[id*516+12]==0,"LUS_A4_empty_description",0,0);
  ck(code==2 || code==3 || code==16'h1003,"formal_status_not_private_code",2,code);
  ratio=code==3?100:0;
  ck({wire_bytes[id*516+19],wire_bytes[id*516+20],wire_bytes[id*516+21]}==(ratio==100?24'h313030:24'h202030),"ASCII_ratio_0_or_100",ratio,wire_bytes[id*516+21]);
  if(expected_bad>0 && expected_bad<4 && code==3)ck(0,"invalid_package_must_never_report_operation_completed",16'h1003,code);
  if(c==last_lus_counter && last_lus_len!=0)begin
   ck(n==last_lus_len,"retransmission_frozen_LUS_length",last_lus_len,n);
   for(k=0;k<n;k=k+1)ck(wire_bytes[id*516+4+k]==last_lus[k],"same_status_snapshot_on_retry",last_lus[k],wire_bytes[id*516+4+k]);
  end else begin
   ck(c==last_counter+1,"one_counter_per_snapshot_not_per_retransmit",last_counter+1,c);last_counter=c;last_lus_counter=c;last_lus_len=n;
   for(k=0;k<n;k=k+1)last_lus[k]=wire_bytes[id*516+4+k];
   status_files=status_files+1;if(code==2)periodic_files=periodic_files+1;
  end
  if(n!=20)begin
   ck(n==43 && {wire_bytes[id*516+22],wire_bytes[id*516+23]}==1,"one_load_header_entry",43,n);
   ck(wire_bytes[id*516+24]==8 && wire_bytes[id*516+32]==0 && wire_bytes[id*516+33]==7 && wire_bytes[id*516+40]==0,"LUS_name_part_length_NUL",8,wire_bytes[id*516+24]);
   for(k=0;k<7;k=k+1)ck(wire_bytes[id*516+25+k]==hname[55-k*8-:8],"status_header_filename",hname[55-k*8-:8],wire_bytes[id*516+25+k]);
   ck({wire_bytes[id*516+41],wire_bytes[id*516+42],wire_bytes[id*516+43]}==(ratio==100?24'h313030:24'h202030),"per_load_ratio",ratio,0);
  end
  $fwrite(fd_status,"%0d %0d %0d ",upload_index,$time,n);for(k=0;k<n;k=k+1)$fwrite(fd_status,"%02x",wire_bytes[id*516+4+k]);$fwrite(fd_status,"\n");
  if(code==3 || code==16'h1003)begin final_status=code;ubus(0,1,0,value);ck(!value[2],"no_notification_success_until_final_ACK",0,value);end
 end endtask
 reg [55:0] hname="C35.LUH";
 task process;integer id,op,num;begin
  next_wire;id=qhead;op={wire_bytes[id*516],wire_bytes[id*516+1]};num={wire_bytes[id*516+2],wire_bytes[id*516+3]};pop;
  ck(wire_net[id]==selected_network,"upload_network_snapshot",selected_network,wire_net[id]);
  if(op==1)begin
   ck(wire_port[id]==59 && wire_source[id]>=40000 && wire_source[id]<=44999,"DUT_active_RRQ_dynamic_TID",59,wire_port[id]);rr_tid=wire_source[id];known_reader[rr_tid-40000]=1;
   if(wire_len[id]==16)begin check_name(id,1,{"C35.LUH",200'd0},7);rr_file=0;header_requests=header_requests+1;end
   else begin check_name(id,1,{"PAYLOAD.BIN",168'd0},11);rr_file=1;read_requests=read_requests+1;end
   rr_offset=0;rr_block=1;
   if(cancel_at_data && rr_file==1)begin ubus(1,0,2,dummy);cancel_tick=$time;cancel_at_data=0;end else serve_data;
  end else if(op==2)begin
   check_name(id,2,{"AFDX_01.LUS",168'd0},11);ck(wire_source[id]>=45001 && wire_source[id]<=49151 && wire_port[id]==59,"independent_status_TID_context",59,wire_port[id]);
   wr_tid=wire_source[id];if(drop_status)begin
    destination=wr_tid;sender_port=41000;message[0]=0;message[1]=5;message[2]=0;message[3]=2;message[4]="D";message[5]=0;message_length=6;send_message(0);
    cancel_tick=$time;$fdisplay(fd_peer,"REJECT_STATUS_WRQ_WITH_ERROR2 upload=%0d time=%0d",upload_index,$time);
   end else send_ack_to(wr_tid,0,41000);
  end else if(op==3)begin
   ck(wire_source[id]==wr_tid && wire_port[id]==41000,"status_final_ACK_bound_server_TID",wr_tid,wire_source[id]);check_status(id);
   if(lose_lus_ack!=0)begin lose_lus_ack=0;$fdisplay(fd_peer,"DROP_LUS_ACK upload=%0d time=%0d",upload_index,$time);end
   else begin send_ack_to(wr_tid,1,41000);if(final_status!=0)final_notifications=final_notifications+1;end
  end else if(op==4)begin
   ck(wire_len[id]==4,"actual_ACK_fourbytes",4,wire_len[id]);
   if(wire_source[id]>=49152)begin
    ck(num==1,"LUR_final_storage_ACK",1,num);ck(!hold_completion,"LUR_ACK_after_storage",0,hold_completion);
   end else begin
    ck(known_reader[wire_source[id]-40000]===1 && wire_port[id]==42000,"RRQ_ACK_bound_known_TID",42000,wire_port[id]);
    if(wire_source[id]!=rr_tid || num<rr_block)begin old_acks=old_acks+1;$fdisplay(fd_peer,"IGNORE_OLD_ACK source=%0d block=%0d current_source=%0d current_block=%0d",wire_source[id],num,rr_tid,rr_block);end
    else if(duplicate_data && rr_file==1 && rr_block==1 && !duplicate_exercised)begin
     duplicate_exercised=1;data_retries=data_retries+1;$fdisplay(fd_peer,"DROP_DATA_ACK_AND_REPLAY upload=%0d block=1 time=%0d",upload_index,$time);serve_data;
    end else if(rr_chunk==512)begin rr_offset=rr_offset+rr_chunk;rr_block=rr_block+1;serve_data;end
    else begin if(rr_file==1)final_requests=final_requests+1;end
   end
  end else ck(0,"unexpected_TFTP_operation",0,op);
 end endtask
 task reject_consumed_initialization;integer j;reg [87:0] name;begin
  name="AFDX_01.LUR";destination=59;sender_port=40001;message[0]=0;message[1]=2;
  for(j=0;j<11;j=j+1)message[j+2]=name[87-j*8-:8];message[13]=0;{message[14],message[15],message[16],message[17],message[18],message[19]}={"octet",8'd0};message_length=20;
  send_message(0);next_wire;ck(wire_len[qhead]==8 && wire_bytes[qhead*516+1]==5 && wire_bytes[qhead*516+3]==2,"completed_initialization_cannot_start_a_second_LUR",2,wire_bytes[qhead*516+3]);pop;
 end endtask
 task start_lur;input integer bad;integer k;reg [87:0] name;begin
  close_session;name="AFDX_01.LUR";destination=59;sender_port=40001;message[0]=0;message[1]=2;
  for(k=0;k<11;k=k+1)message[2+k]=name[87-k*8-:8];message[13]=0;{message[14],message[15],message[16],message[17],message[18],message[19]}={"octet",8'd0};message_length=20;
  send_message(0);next_wire;ck(wire_bytes[qhead*516+1]==4 && wire_bytes[qhead*516+3]==0 && wire_source[qhead]>=49152,"LUR_WRQ_prepared_ACK0",0,wire_bytes[qhead*516+3]);current_tid=wire_source[qhead];pop;
  destination=current_tid;message[0]=0;message[1]=3;message[2]=0;message[3]=1;for(k=0;k<lur_bytes;k=k+1)message[4+k]=rfile[k];if(bad)message[9]="3";message_length=lur_bytes+4;send_message(0);
 end endtask
 task run_upload;input integer vector,net,bad,dup;integer t,before_commits,before_zero,k;begin
  upload_index=upload_index+1;cancel_tick=0;file_id=vector;business_size=vector==0?37:4096;expected_bad=bad;duplicate_data=dup;duplicate_exercised=0;final_status=0;drop_status=0;cancel_at_data=bad==4;
  $sformat(path,"%0s/header%0d.hex",UPLOAD_DIR,vector);$readmemh(path,hfile,0,107);if(bad==2)hfile[102]=hfile[102]^1;
  $sformat(path,"%0s/request%0d.hex",UPLOAD_DIR,vector);$readmemh(path,rfile,0,24);$sformat(path,"%0s/data%0d.hex",UPLOAD_DIR,vector);$readmemh(path,dfile,0,business_size-1);
  initialization(net);drop_status=bad==5;before_commits=data_commits;before_zero=data_zero;
  $fdisplay(fd_events,"UPLOAD_BEGIN id=%0d n=%0d net=%0d bad=%0d data_commits=%0d",upload_index,business_size,net,bad,data_commits);
  start_lur(bad==1);t=0;value=0;
  while(value[3:0]!=13 && value[3:0]!=14 && t<40000)begin
   if(qhead!=qtail)process;else pause(500);
   ubus(0,0,0,value);t=t+1;
  end
  ck(value[3:0]==(bad?14:13),"bounded_upload_terminal_state",bad?14:13,value[3:0]);
  ubus(0,1,0,value);
  if(!bad)begin
   ck(value==7 && final_status==3 && object_valid && object_complete && object_length==business_size,"local_valid_result_and_confirmed_final_LUS",7,value);
   ck(data_commits-before_commits==(business_size/512)+2,"one_write_per_DATA_plus_explicit_validity_commit",business_size/512+2,data_commits-before_commits);
   ck(data_zero-before_zero==(business_size%512==0?2:1),"terminal_zero_block_and_validity_commit_have_no_data_access",business_size%512==0?2:1,data_zero-before_zero);
   disk_readback(business_size,vector==0?213:230);
  end else if(bad==4 || bad==5)begin
   ck(!value[2] && !value[1],"cancel_or_notification_failure_not_success",0,value);
  end else begin
   ck(!value[1] && final_status==16'h1003,"rejected_upload_never_operation_success",16'h1003,final_status);
   if(bad==3)ck(!object_valid && !object_complete,"content_failure_remains_invalid",0,object_valid);
   else ck(data_commits==before_commits,"bad_control_never_touches_business_file",before_commits,data_commits);
  end
  close_session;drop_status=0;pause(1000);
  if(bad==4 || bad==5)begin
   while(qhead<qtail)begin
    ck(((wire_source[qhead]>=45001 && wire_source[qhead]<=49151 && (wire_bytes[qhead*516+1]==2 || wire_bytes[qhead*516+1]==3)) || (wire_source[qhead]>=40000 && wire_source[qhead]<=44999 && wire_bytes[qhead*516+1]==4)),"cancel_drain_is_only_status_or_successful_header_ACK",4,wire_bytes[qhead*516+1]);
    ck(cancel_tick!=0,"cancellation_was_accepted_publicly",1,cancel_tick!=0);
    $fdisplay(fd_peer,"CANCELLED_PREOFFERED_FRAME upload=%0d q=%0d source=%0d",upload_index,qhead,wire_source[qhead]);pop;
   end
   // A late network reply after cancellation must drain without holding the
   // common UDP context and preventing the next legitimate initialization.
   if(bad==4)begin destination=rr_tid;sender_port=42000;data_block(1,17);send_message(0);pause(1000);end
  end
  ck(qhead==qtail && media.state==0 && media.pos==0,"session_storage_and_wire_queue_drained",qtail,qhead);
  $fdisplay(fd_events,"UPLOAD_END id=%0d n=%0d bad=%0d state=%0d data_commits=%0d zero_commits=%0d object_valid=%0d",upload_index,business_size,bad,value,data_commits-before_commits,data_zero-before_zero,object_valid);
 end endtask
 initial begin #5000000;if(!checkpoint_ready && !done)ck(0,"bounded5ms_shared_configuration",1,checkpoint_ready);end
 always @(posedge clk)if(rst_n && cfg_applied)$fdisplay(fd_events,"PUBLIC_APPLY time_ns=%0d",$time);
 integer fd_status,k;
 always @(posedge clk)if(rst_n)begin
  if(store_tx_valid && store_tx_ready)captured_tag<={captured_tag[23:0],store_tx_data};
  if(store_tx_valid && store_tx_ready)$fdisplay(fd_storage,"TX %0t %02x %0d",$time,store_tx_data,store_tx_last);
  if(store_rx_valid && store_rx_ready)$fdisplay(fd_storage,"RX %0t %02x %0d",$time,store_rx_data,store_rx_last);
  if(store_cancel)$fdisplay(fd_storage,"CANCEL %0t",$time);
  if(store_event && store_event_kind==3 && media.bank==0)begin data_commits=data_commits+1;if(store_event_length==0)data_zero=data_zero+1;end
 end
 task c37_wide;begin
  lbus(1,22,6,0,dummy);lbus(1,18,32767,0,dummy);lbus(0,32,0,0,value);ck(value==8'ha1,"wide_actual_storage32767",8'ha1,value);
  lbus(0,33,0,0,value);ck(value==8'h6a,"wide_actual_storage32768_no_alias",8'h6a,value);
  lbus(1,18,65535,0,dummy);lbus(0,32,0,0,value);ck(value==8'h46,"wide_actual_storage65535",8'h46,value);lbus(0,33,0,1,value);
  lbus(1,19,77,1,dummy);lbus(1,22,0,0,dummy);lbus(1,18,0,0,dummy);dbus(1,0,2,dummy);dn_cancel=1;
  $fdisplay(fd_events,"WIDE_PROBE_CANCEL bytes512_expected_total65536 time_ns=%0d",$time);
 end endtask
 task epoch_recovery;integer n;reg [31:0] prior_stale;begin
  close_session;lbus(1,19,7,0,dummy);hold_completion=1;cbus(1,0,1,dummy);
  n=0;while(!store_tx_last && n<10000)begin @(negedge clk);n=n+1;end ck(n<10000,"pre_reset_actual_storage_request",1,n<10000);@(negedge clk);saved_old_tag=captured_tag;
  $fdisplay(fd_events,"RESET_EPOCH old_tag=%08x time_ns=%0d",saved_old_tag,$time);
  physical_reset_base=tx_frames;rst_n=0;pause(12);rst_n=1;model_epoch=model_epoch+1;init_counter=0;last_counter=0;last_dn_counter=0;qhead=qtail;pause(20);setup;media.preload_catalog;
  checkpoint_ready=1;
  if(CHECKPOINT_MODE)begin $display("C42_CONFIGURED checks=%0d cycles=%0d",checks,cycles);$stop;wait(resume_go);end
  cbus(1,0,1,dummy);n=0;while(!store_tx_last && n<10000)begin @(negedge clk);n=n+1;end ck(n<10000,"post_reset_actual_storage_request",1,n<10000);@(negedge clk);
  ck(captured_tag[15:0]==1 && captured_tag[31:16]==model_epoch+1,"new_epoch_prefix_on_real_device_link",(model_epoch+1)*65536+1,captured_tag);
  // Delayed response deliberately has the same low counter as the new one.
  ck(saved_old_tag==32'h00070001,"saved_real_pending_old_epoch_first_request",32'h00070001,saved_old_tag);
  $fdisplay(fd_events,"INJECT_PRE_RESET_TAG tag=%08x new_tag=%08x time_ns=%0d",saved_old_tag,captured_tag,$time);storage_inject=1;storage_inject_index=0;
  while(storage_inject_index<5)begin if(store_rx_ready)begin @(negedge clk);storage_inject_index=storage_inject_index+1;end else @(negedge clk);end
  storage_inject=0;pause(10);lbus(0,28,0,0,value);ck(value==1,"old_reset_epoch_not_matching_new_operation",1,value);
  hold_completion=0;n=0;value=0;while(!value[1] && n<1000)begin pause(30);cbus(0,0,0,value);n=n+1;end ck(value[1],"legitimate_storage_response_after_stale_recovers",1,value[1]);
  run_upload(0,1,0,0);
 end endtask
 initial begin
  for(k=0;k<65536;k=k+1)offered[k]=0;
  for(k=0;k<80;k=k+1)app_seen[k]=0;
  for(k=0;k<64;k=k+1)begin app_sent[k]=0;physical_mask[k]=0;app_first[k]=0;app_accept[k]=0;app_commit[k]=0;end
  for(k=0;k<4;k=k+1)last_rt_start[k]=0;lh[0]=0;lh[1]=0;lt[0]=0;lt[1]=0;
  fd_events=$fopen("events.log","w");fd_wire=$fopen("wire.log","w");fd_rx=$fopen("injections.log","w");fd_read=$fopen("readback.log","w");fd_peer=$fopen("peer.log","w");fd_storage=$fopen("storage_bus.log","w");fd_status=$fopen("status-files.log","w");fd_download=$fopen("download-files.log","w");fd_control=$fopen("download-control.log","w");
  fd_app=$fopen("app-events.log","w");fd_rtc=$fopen("rtc-events.log","w");fd_links=$fopen("link-events.log","w");
  $sformat(path,"%0s/payload.hex",APP_DIR);$readmemh(path,app_payload);$sformat(path,"%0s/wire_a.hex",APP_DIR);$readmemh(path,app_gold_a);$sformat(path,"%0s/wire_b.hex",APP_DIR);$readmemh(path,app_gold_b);
  $sformat(path,"%0s/meta.hex",APP_DIR);$readmemh(path,app_meta);$sformat(path,"%0s/config.hex",APP_DIR);$readmemh(path,app_config);$sformat(path,"%0s/snmp.hex",APP_DIR);$readmemh(path,snmp_gold);$sformat(path,"%0s/snmp_meta.hex",APP_DIR);$readmemh(path,snmp_lengths);
  $sformat(path,"%0s/lnl.hex",DOWNLOAD_DIR);$readmemh(path,list_gold,0,31);
  pause(12);rst_n=1;setup;media.preload_catalog;
  checkpoint_ready=1;
  if(CHECKPOINT_MODE)begin $display("C42_CONFIGURED checks=%0d cycles=%0d",checks,cycles);$stop;wait(resume_go);end
  begin_case("full_VLID_BAG_preparation_pending_APPLY_and_recovery");
  // Cancel a public VLID scan while the configuration request is in flight.
  @(negedge clk);app_tx_cmd_valid=1;app_tx_vlid=16'hffff;app_tx_cmd_length=16;
  @(posedge clk);while(!app_tx_cmd_ready)@(posedge clk);@(negedge clk);app_tx_cmd_valid=0;
  pause(4);app_tx_abort=1;pause(2);app_tx_abort=0;
  bus(0,0,0,0,127,7,0,0,value);ck(value[15:0]==16'h8001,"cancelled_lookup_does_not_lose_public_bus",16'h8001,value[15:0]);
  app_send(0);app_send(1);wait_app(0);wait_app(1);
  bus(0,1,1,0,0,4,0,0,value);ck(!value[8] && value[17] && value[26],"bad_FCS_never_initializes_A_IC",0,value[8]);
  // The second VL0001 frame is fully committed well before its 1ms BAG.
  app_send(2);
  bus(1,0,0,1,0,6,(559<<16)|16'h1001,0,dummy);
  $fdisplay(fd_events,"UPDATE_REQUEST time_ns=%0d old_frame=2 new_Lmax=559",$time);
  commit_config(0);wait_app(2);
  bus(0,1,1,0,0,4,0,0,value);ck(!value[8] && value[16:9]==1 && value[25:18]==1,"bad_IP_no_A_history_B_progress_independent",1,value[16:9]);
  bus(0,0,0,0,0,6,0,0,value);ck(value[31:16]==559,"actual_atomic_APPLY_new_Lmax",559,value[31:16]);
  unknown_command(16'h4001,16,14);
  unknown_command(1,1471,3); // New active limit affects actual command path.
  app_send(4);wait_app(4);
  // A whole A link frame is externally lost; B alone delivers the good frame.
  link_a_down=1;$fdisplay(fd_events,"A_LINK_DOWN time_ns=%0d",$time);
  app_send(3);wait_app(3);
  ck(physical_mask[3]==3,"both_MACs_work_while_external_A_lost",3,physical_mask[3]);
  link_a_down=0;$fdisplay(fd_events,"A_LINK_UP time_ns=%0d",$time);
  enqueue_app(0,3);enqueue_app(1,3);pause(3000);
  ck(app_seen[3]==1,"bounded_late_redundant_copy_no_second_delivery",1,app_seen[3]);
  begin_case("cross_bank_real_resource_fault_and_Trap");
  resource_burst;
  bus(0,1,1,0,2048,4,0,0,value);$fdisplay(fd_events,"PUBLIC_STATE RX2048_word4=%08x time_ns=%0d",value,$time);
  bus(0,1,1,0,4095,4,0,0,value);$fdisplay(fd_events,"PUBLIC_STATE RX4095_word4=%08x time_ns=%0d",value,$time);
  bus(0,1,0,0,127,4,0,0,value);$fdisplay(fd_events,"PUBLIC_STATE TX127_word4=%08x time_ns=%0d",value,$time);
  begin_case("real_state_GET_and_one_actual_SNTP_RTC_correction");
  enqueue_snmp(0);snmp_sent=1;
  tbus(1,0,1760000000,dummy);tbus(1,1,0,dummy);tbus(1,2,$time+500000,dummy);tbus(1,3,1,dummy);tbus(1,76,85899346,dummy);
  concurrent_active=1;sample_rtc;
  app_send(5);wait_app(5);
  bus(0,3,0,0,0,8,0,0,dummy);
  bus(0,3,0,0,0,9,0,0,post_candidate[31:0]);bus(0,3,0,0,0,10,0,0,post_candidate[63:32]);
  bus(0,3,0,0,0,11,0,0,post_decision[31:0]);bus(0,3,0,0,0,12,0,0,post_decision[63:32]);
  $fdisplay(fd_rtc,"POST_TIME_FRAME id=5 candidate=%0d decision=%0d time_ns=%0d",post_candidate,post_decision,$time);
  i=0;while(snmp_replies<snmp_sent && i<20000)begin pause(20);i=i+1;end
  ck(snmp_replies==1,"actual_B_network_GET_progress",1,snmp_replies);
  begin_case("A4_665_small_upload_then_independent_download");
  run_upload(0,1,0,0);
  start_download(0,1,0,0);finish_download(0);
  ck(trap_frames==1 && trap_received==1,"one_actual_event_Trap_independent_of_queries",1,trap_received);
  for(i=0;i<64;i=i+1)if(app_sent[i])wait_app(i);
  pause(1000);final_accounting;
  for(i=0;i<64;i=i+1)if(app_sent[i])ck(physical_mask[i]==3,"both_real_MAC_copies_sent_once",3,physical_mask[i]);
  bus(1,2,0,0,0,0,0,0,dummy);
  for(i=0;i<32;i=i+1)begin bus(0,2,0,0,i,0,0,0,value);$fdisplay(fd_events,"STATS index=%0d value=%0d time_ns=%0d",i,value,$time);if(i==18)ck(value==0,"no_ownership_error",0,value);if(i==28 || i==29)ck(value[15:0]==0,"all_payload_pools_reclaimed",0,value[15:0]);end
  ck(qhead==qtail && media.state==0 && media.pos==0 && media.locked_bank[6:5]==0,"final_resources_baseline",0,media.locked_bank[6:5]);
  $fdisplay(fd_events,"FINAL groups=%0d checks=%0d upload_attempts=%0d download_attempts=%0d TX=%0d RX=%0d epoch=1",cases,checks,upload_index,dn_id,tx_frames,rx_frames);
  $fdisplay(fd_app,"FINAL accepted=%0d unique=%0d errors=%0d time_ns=%0d",app_accepted,app_unique,app_errors,$time);
  done=1;$display("C42_SYSTEM_PASS cases=%0d checks=%0d apps=%0d tx=%0d rx=%0d",cases,checks,app_unique,tx_frames,rx_frames);$finish;
 end
 task automatic bus;
  input writing;input [1:0] kind;input bank,shadow;input integer index,word;
  input [31:0] value;input expected_error;output [31:0] answer;
  reg [32:0] held;integer k;
  begin
   while(host_lock)@(negedge clk);host_lock=1;
   @(negedge clk);cfg_valid=1;cfg_write=writing;cfg_kind=kind;cfg_bank=bank;cfg_shadow=shadow;
   cfg_index=index;cfg_word=word;cfg_data=value;cfg_resp_ready=0;
   @(posedge clk);while(!cfg_ready)@(posedge clk);#1;
   @(negedge clk);cfg_valid=0;
   while(!cfg_resp_valid)@(negedge clk);
   ck(cfg_resp_error===expected_error,"configuration_bus_response",expected_error,cfg_resp_error);
   $fdisplay(fd_events,"BUS write=%0d kind=%0d bank=%0d shadow=%0d index=%0d word=%0d input=%08x error=%0d output=%08x time_ns=%0d",writing,kind,bank,shadow,index,word,value,cfg_resp_error,cfg_resp_data,$time);
   answer=cfg_resp_data;held={cfg_resp_error,cfg_resp_data};
   repeat(2)begin @(posedge clk);#1;ck(cfg_resp_valid && {cfg_resp_error,cfg_resp_data}===held,"configuration_response_backpressure",held,{cfg_resp_error,cfg_resp_data});end
   @(negedge clk);cfg_resp_ready=1;
   @(posedge clk);#1;
   @(negedge clk);cfg_resp_ready=0;host_lock=0;
  end
 endtask
 task automatic commit_config;input integer expected_code;
  begin
   @(negedge clk);cfg_commit_valid=1;cfg_result_ready=0;
   while(!cfg_commit_ready)@(negedge clk);
   @(posedge clk);#1;
   @(negedge clk);cfg_commit_valid=0;
   while(!cfg_result_valid)@(negedge clk);
   ck(cfg_result_code===expected_code,"configuration_commit_reason",expected_code,cfg_result_code);
   ck(cfg_result_ok===(expected_code==0),"configuration_commit_success",expected_code==0,cfg_result_ok);
   @(negedge clk);cfg_result_ready=1;
   @(posedge clk);#1;
   @(negedge clk);cfg_result_ready=0;
  end
 endtask

 // C42 PASSIVE DIAGNOSTICS BEGIN
 integer diag_requests=0,diag_responses=0,diag_commits=0,diag_results=0,diag_applies=0;
 integer diag_phase=0,diag_fd=0;time diag_time_ns=0;
 initial diag_fd=$fopen("configuration-trace.log","w");
 always @(posedge clk)begin
  if(rst_n)begin
   if(cfg_valid===1'b1 && cfg_ready===1'b1)begin
    diag_requests=diag_requests+1;
    if(!checkpoint_ready)$fdisplay(diag_fd,"REQUEST cycle=%0d time_ns=%0d write=%0d kind=%0d bank=%0d shadow=%0d index=%0d word=%0d data=%08x",cycles,$time,cfg_write,cfg_kind,cfg_bank,cfg_shadow,cfg_index,cfg_word,cfg_data);
   end
   if(cfg_resp_valid===1'b1 && cfg_resp_ready===1'b1)begin
    diag_responses=diag_responses+1;
    if(!checkpoint_ready)$fdisplay(diag_fd,"RESPONSE cycle=%0d time_ns=%0d error=%0d data=%08x",cycles,$time,cfg_resp_error,cfg_resp_data);
   end
   if(cfg_commit_valid===1'b1 && cfg_commit_ready===1'b1)begin
    diag_commits=diag_commits+1;
    if(!checkpoint_ready)$fdisplay(diag_fd,"COMMIT cycle=%0d time_ns=%0d",cycles,$time);
   end
   if(cfg_result_valid===1'b1 && cfg_result_ready===1'b1)begin
    diag_results=diag_results+1;
    if(!checkpoint_ready)$fdisplay(diag_fd,"RESULT cycle=%0d time_ns=%0d ok=%0d code=%0d",cycles,$time,cfg_result_ok,cfg_result_code);
   end
   if(cfg_applied===1'b1)begin
    diag_applies=diag_applies+1;
    if(!checkpoint_ready)$fdisplay(diag_fd,"APPLY cycle=%0d time_ns=%0d",cycles,$time);
   end
  end
 end
 always @(negedge clk)begin
  diag_time_ns=$time;
  if(!rst_n)diag_phase=0;
  else if(checkpoint_ready)diag_phase=7+cases;
  else if(init_done!==1'b1)diag_phase=1;
  else if(diag_requests<41)diag_phase=2;
  else if(cfg_commit_valid)diag_phase=3;
  else if(diag_commits>diag_results)diag_phase=4;
  else if(cfg_pending)diag_phase=5;
  else diag_phase=6;
 end
 // Flush at 20us simulation intervals, never on every clock/byte.
 initial forever begin #20000;$fflush();end
 // C42 PASSIVE DIAGNOSTICS END

endmodule
