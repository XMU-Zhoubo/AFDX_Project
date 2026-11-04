`timescale 1ns/1ps
module c42s_system;
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
wire cfg_valid;
wire cfg_write;
wire [1:0] cfg_kind;
wire cfg_bank;
wire cfg_shadow;
wire [12:0] cfg_index;
wire [3:0] cfg_word;
wire [31:0] cfg_data;
wire cfg_ready;
wire cfg_resp_valid;
wire cfg_resp_ready;
wire cfg_resp_error;
wire [31:0] cfg_resp_data;
wire cfg_commit_valid;
wire cfg_commit_ready;
wire cfg_pending;
wire cfg_applied;
wire cfg_result_valid;
wire cfg_result_ok;
wire cfg_result_ready;
wire [2:0] cfg_result_code;
wire [15:0] cfg_version;
wire init_done;
wire app_tx_cmd_valid;
wire app_tx_cmd_ready;
reg [12:0] app_tx_cmd_index=0;
wire [15:0] app_tx_cmd_length;
wire [7:0] app_tx_data;
wire app_tx_valid;
wire app_tx_last;
wire app_tx_ready;
wire app_tx_commit_valid;
wire app_tx_abort;
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
 wire app_tx_sop;wire [15:0] app_tx_vlid;
 AFDX_top dut(.clk(clk),.rst_n(rst_n),.gtx_clk(gtx_clk),.phy_b_rx_clk(phy_b_rx_clk),.phy_b_rxd(phy_b_rxd),.phy_b_rx_dv(phy_b_rx_dv),.phy_b_rx_er(phy_b_rx_er),.phy_b_tx_clk(phy_b_tx_clk),.phy_b_txd(phy_b_txd),.phy_b_tx_en(phy_b_tx_en),.phy_b_tx_er(phy_b_tx_er),.rx_network(app_rx_network),.phy_a_rx_clk(phy_rx_clk),.phy_a_rxd(phy_rxd),.phy_a_rx_dv(phy_rx_dv),.phy_a_rx_er(phy_rx_er),.phy_a_tx_clk(phy_tx_clk),.phy_a_txd(phy_txd),.phy_a_tx_en(phy_tx_en),.phy_a_tx_er(phy_tx_er),.cfg_valid(cfg_valid),.cfg_write(cfg_write),.cfg_kind(cfg_kind),.cfg_bank(cfg_bank),.cfg_shadow(cfg_shadow),.cfg_index(cfg_index),.cfg_word(cfg_word),.cfg_data(cfg_data),.cfg_ready(cfg_ready),.cfg_resp_valid(cfg_resp_valid),.cfg_resp_ready(cfg_resp_ready),.cfg_resp_error(cfg_resp_error),.cfg_resp_data(cfg_resp_data),.cfg_commit_valid(cfg_commit_valid),.cfg_commit_ready(cfg_commit_ready),.cfg_pending(cfg_pending),.cfg_applied(cfg_applied),.cfg_result_valid(cfg_result_valid),.cfg_result_ok(cfg_result_ok),.cfg_result_ready(cfg_result_ready),.cfg_result_code(cfg_result_code),.init_done(init_done),.tx_cmd_valid(app_tx_cmd_valid),.tx_cmd_ready(app_tx_cmd_ready),.tx_vlid(app_tx_vlid),.tx_length(app_tx_cmd_length),.tx_data(app_tx_data),.tx_valid(app_tx_valid),.tx_sop(app_tx_sop),.tx_last(app_tx_last),.tx_ready(app_tx_ready),.tx_commit_valid(app_tx_commit_valid),.tx_abort(app_tx_abort),.tx_commit_ready(app_tx_commit_ready),.tx_error_valid(app_tx_error_valid),.tx_error_ready(app_tx_error_ready),.tx_error_code(app_tx_error_code),.rx_desc_valid(app_rx_desc_valid),.rx_desc_ready(app_rx_desc_ready),.rx_desc_length(app_rx_desc_length),.rx_desc_vl(app_rx_desc_vl),.rx_desc_app_id(app_rx_desc_app_id),.rx_desc_version(app_rx_desc_version),.rx_desc_sn(app_rx_desc_sn),.rx_desc_udp_checked(app_rx_desc_udp_checked),.rx_data(app_rx_data),.rx_valid(app_rx_valid),.rx_sop(app_rx_sop),.rx_last(app_rx_last),.rx_ready(app_rx_ready),.store_tx_data(store_tx_data),.store_tx_valid(store_tx_valid),.store_tx_last(store_tx_last),.store_tx_ready(store_tx_ready),.store_rx_data(store_rx_data),.store_rx_valid(store_rx_valid),.store_rx_last(store_rx_last),.store_rx_ready(store_rx_ready),.store_cancel(store_cancel),.events(events),.line_management(line_management));
 always #5 clk=~clk;
 always #4 gtx_clk=~gtx_clk;
 initial begin #2;forever #4 phy_rx_clk=~phy_rx_clk;end
 initial begin #3;forever #4 phy_b_rx_clk=~phy_b_rx_clk;end

 wire configured,config_failed;wire [31:0] input_count;
 c42s_configuration config_source(.clk(clk),.rst_n(rst_n),.init_done(init_done),.configured(configured),.failed(config_failed),
 .cfg_valid(cfg_valid),.cfg_write(cfg_write),.cfg_kind(cfg_kind),.cfg_bank(cfg_bank),.cfg_shadow(cfg_shadow),.cfg_index(cfg_index),.cfg_word(cfg_word),.cfg_data(cfg_data),
 .cfg_ready(cfg_ready),.cfg_resp_valid(cfg_resp_valid),.cfg_resp_error(cfg_resp_error),.cfg_resp_data(cfg_resp_data),.cfg_resp_ready(cfg_resp_ready),
 .cfg_commit_valid(cfg_commit_valid),.cfg_commit_ready(cfg_commit_ready),.cfg_result_valid(cfg_result_valid),.cfg_result_ok(cfg_result_ok),.cfg_result_code(cfg_result_code),.cfg_result_ready(cfg_result_ready));
 c42s_application_source app_source(.clk(clk),.rst_n(rst_n),.configured(configured),.cmd(app_tx_cmd_valid),.cmd_ready(app_tx_cmd_ready),
 .vlid(app_tx_vlid),.length(app_tx_cmd_length),.data(app_tx_data),.valid(app_tx_valid),.sop(app_tx_sop),.last(app_tx_last),.ready(app_tx_ready),
 .commit(app_tx_commit_valid),.abort(app_tx_abort),.commit_ready(app_tx_commit_ready),.error_valid(app_tx_error_valid),.accepted(input_count));
 assign store_tx_ready=1'b1;assign store_rx_data=0;assign store_rx_valid=0;assign store_rx_last=0;
 integer cycles=0,checks=0,failures=0,cases=0,unique=0,txframes=0,rxframes=0,app_error_count=0;
 reg done=0,drop_a=0;reg [511:0] label="startup";
 always @(posedge clk)cycles<=cycles+1;
 integer fd_wire,fd_app,fd_link,fd_events,fd_stimulus;
 task ck;input ok;input [255:0] what;input [63:0] expected,actual;
 begin checks=checks+1;if(ok!==1)begin failures=failures+1;$display("C42S_MISMATCH case=%0s item=%0s time_ns=%0d expected=%h actual=%h",label,what,$time,expected,actual);$finish;end end endtask
 task pause;input integer n;begin repeat(n)@(negedge clk);end endtask
 function [7:0] pattern;input integer pos,seed;begin pattern=(pos*73+(pos>>8)*19+seed)&255;end endfunction
 reg [7:0] link_bytes[0:65535];integer heads[0:1],tails[0:1],qlen[0:31];
 reg [7:0] late_copy[0:2047];integer late_length=0;
 wire [1:0] tc={phy_b_tx_clk,phy_tx_clk},te={phy_b_tx_en,phy_tx_en},terr={phy_b_tx_er,phy_tx_er};
 wire [7:0] td[0:1];assign td[0]=phy_txd;assign td[1]=phy_b_txd;
 genvar n;
 generate for(n=0;n<2;n=n+1)begin:links
  reg [7:0] cap[0:2047];integer cnt=0,k,slot,active=0;time first=0,previous=0,last_vl1=0,last_vl8=0;
  reg [31:0] crc;
  always @(posedge tc[n])begin
   if(!rst_n)begin cnt=0;active=0;end
   else if(te[n])begin
    if(!active)begin active=1;cnt=0;first=$time;ck(previous==0 || $time-previous>=96,"IFG",96,$time-previous);end
    ck(!terr[n] && cnt<2048,"GMII_no_error",0,terr[n]);cap[cnt]=td[n];cnt=cnt+1;
   end else if(active)begin
    active=0;previous=$time;txframes=txframes+1;crc=32'hffffffff;
    ck(cnt>=72,"wire_min_frame",72,cnt);
    for(k=0;k<8;k=k+1)ck(cap[k]==(k==7?8'hd5:8'h55),"preamble_SFD",k==7?8'hd5:8'h55,cap[k]);
    for(k=8;k<cnt-4;k=k+1)begin
     crc=crc^cap[k];repeat(8)begin if(crc[0])crc=(crc>>1)^32'hedb88320;else crc=crc>>1;end
    end
    ck({cap[cnt-1],cap[cnt-2],cap[cnt-3],cap[cnt-4]}==~crc,"independent_FCS",~crc,{cap[cnt-1],cap[cnt-2],cap[cnt-3],cap[cnt-4]});
    $fwrite(fd_wire,"%0d %0d %0d ",n,first,$time);for(k=0;k<cnt;k=k+1)$fwrite(fd_wire,"%02x",cap[k]);$fwrite(fd_wire,"\n");
    if(cap[8]==3)begin
     if({cap[12],cap[13]}==1)begin ck(last_vl1==0 || first-last_vl1>=1000000,"VL1_actual_BAG",1000000,first-last_vl1);last_vl1=first;end
     if({cap[12],cap[13]}==16'h8001)begin ck(last_vl8==0 || first-last_vl8>=2000000,"VL8001_actual_BAG",2000000,first-last_vl8);last_vl8=first;end
     if(n==0 && drop_a)begin
      $fdisplay(fd_link,"DROP net=0 time_ns=%0d",$time);late_length=cnt;
      for(k=0;k<cnt;k=k+1)late_copy[k]=cap[k];
     end
     else begin
      ck(tails[n]-heads[n]<16,"bounded_link_queue",16,tails[n]-heads[n]);slot=n*16+tails[n]%16;
      qlen[slot]=cnt;for(k=0;k<cnt;k=k+1)link_bytes[slot*2048+k]=cap[k];tails[n]=tails[n]+1;
     end
    end
   end
  end
  integer j,ticket,qs;
  initial begin
   wait(rst_n);
   forever begin
    if(n==0)@(negedge phy_rx_clk);else @(negedge phy_b_rx_clk);
    if(heads[n]<tails[n])begin
     ticket=heads[n];qs=n*16+ticket%16;
     // Delayed actual frame completion drives loopback, never a predetermined RX schedule.
     repeat(n==0?8:13)begin if(n==0)@(negedge phy_rx_clk);else @(negedge phy_b_rx_clk);end
     for(j=0;j<qlen[qs];j=j+1)begin
      if(n==0)begin phy_rxd=link_bytes[qs*2048+j];phy_rx_dv=1;@(negedge phy_rx_clk);end
      else begin phy_b_rxd=link_bytes[qs*2048+j];phy_b_rx_dv=1;@(negedge phy_b_rx_clk);end
     end
     if(n==0)begin phy_rx_dv=0;phy_rxd=0;end else begin phy_b_rx_dv=0;phy_b_rxd=0;end
     $fdisplay(fd_link,"RECEIVE net=%0d ticket=%0d bytes=%0d time_ns=%0d",n,ticket,qlen[qs],$time);
     $fwrite(fd_stimulus,"%0d %0d ",n,$time);for(j=0;j<qlen[qs];j=j+1)$fwrite(fd_stimulus,"%02x",link_bytes[qs*2048+j]);$fwrite(fd_stimulus,"\n");
     rxframes=rxframes+1;heads[n]=heads[n]+1;
    end
   end
  end
 end endgenerate
 integer expected_length[0:31],expected_seed[0:31],expected_vl[0:31],exp_head=0,exp_tail=0,app_pos=0;
 integer current_expected=-1;time offered[0:31],accepted[0:31],committed[0:31],visible[0:31],first_out[0:31];reg [31:0] csr;integer late_slot,late_j;
 integer late_i;reg visible_recorded=0;
 reg [15:0] held_len,held_vl,held_ver;reg [7:0] held_byte;reg stalled=0;reg rx_stalls=0;
 always @(posedge clk)if(rst_n)begin
  if(app_tx_error_valid && app_tx_error_ready)begin app_error_count=app_error_count+1;$fdisplay(fd_events,"APP_ERROR code=%0d time_ns=%0d",app_tx_error_code,$time);end
  if(app_rx_desc_valid && app_rx_desc_ready)begin
   ck(exp_head<exp_tail,"no_duplicate_message",exp_tail,exp_head);current_expected=exp_head;app_pos=0;visible_recorded=0;
   ck(app_rx_desc_length==expected_length[exp_head],"full_application_length",expected_length[exp_head],app_rx_desc_length);
   ck(app_rx_desc_vl==expected_vl[exp_head],"full_VLID",expected_vl[exp_head],app_rx_desc_vl);visible[exp_head]=$time;
   ck(app_rx_desc_app_id==(expected_vl[exp_head]==16'h8001 ? 16'hc001:expected_vl[exp_head]==16'h42 ? 16'h4242:16'h4001),"configured_app_id_snapshot",expected_vl[exp_head]==16'h8001 ? 16'hc001:expected_vl[exp_head]==16'h42 ? 16'h4242:16'h4001,app_rx_desc_app_id);
   ck(app_rx_desc_version==1,"atomic_config_version_snapshot",1,app_rx_desc_version);
   $fdisplay(fd_app,"DESC id=%0d vl=%0d length=%0d checked=%0d time_ns=%0d",exp_head,app_rx_desc_vl,app_rx_desc_length,app_rx_desc_udp_checked,$time);
   exp_head=exp_head+1;
  end
  if(app_rx_valid && current_expected>=0 && !visible_recorded)begin
   visible_recorded=1;$fdisplay(fd_app,"VISIBLE id=%0d data=%02x time_ns=%0d",current_expected,app_rx_data,$time);
  end
  if(stalled)ck(app_rx_valid && app_rx_data===held_byte,"response_backpressure_stable",held_byte,app_rx_data);
  stalled=app_rx_valid && !app_rx_ready;held_byte=app_rx_data;
  if(app_rx_valid && app_rx_ready)begin
   ck(current_expected>=0,"payload_has_descriptor",1,current_expected>=0);
   ck(app_rx_data==pattern(app_pos,expected_seed[current_expected]),"independent_full_message_byte",pattern(app_pos,expected_seed[current_expected]),app_rx_data);
   ck(app_rx_sop==(app_pos==0) && app_rx_last==(app_pos==expected_length[current_expected]-1),"message_boundaries",expected_length[current_expected],app_pos);
   if(app_pos==0)first_out[current_expected]=$time;
   $fdisplay(fd_app,"BYTE id=%0d offset=%0d data=%02x time_ns=%0d",current_expected,app_pos,app_rx_data,$time);
   app_pos=app_pos+1;
   if(app_rx_last)begin unique=unique+1;$fdisplay(fd_app,"DONE id=%0d time_ns=%0d",current_expected,$time);current_expected=-1;end
  end
 end
 always @(negedge clk)if(rst_n && rx_stalls)app_rx_ready=(cycles%11>2);
 task message;input integer vl,len,seed;integer id,t;
 begin
  id=exp_tail;expected_vl[id]=vl;expected_length[id]=len;expected_seed[id]=seed;exp_tail=exp_tail+1;offered[id]=$time;
  $fdisplay(fd_app,"INPUT id=%0d vl=%0d length=%0d seed=%0d time_ns=%0d",id,vl,len,seed,$time);
  app_source.send(vl,len,seed);committed[id]=$time;$fdisplay(fd_app,"COMMIT id=%0d time_ns=%0d",id,$time);
  if(len>1471)begin
   app_source.abort=1;pause(3);app_source.abort=0;
   $fdisplay(fd_events,"POST_COMMIT_ABORT_IGNORED id=%0d time_ns=%0d",id,$time);
  end
  t=0;while(unique<=id && t<1500000)begin pause(10);t=t+10;end
  ck(unique==id+1,"bounded_complete_message",id+1,unique);pause(100);
 end endtask
 reg [7:0] independent[0:20479],eq_extra[0:6143];
 task independent_receive;integer i,j,qs,t,id;begin
  id=exp_tail;expected_vl[id]=16'h42;expected_length[id]=4096;expected_seed[id]=131;exp_tail=exp_tail+1;
  $fdisplay(fd_app,"EXTERNAL id=%0d vl=66 length=4096 seed=131 time_ns=%0d",id,$time);
  for(i=0;i<4;i=i+1)begin
   qs=16+tails[1]%16;qlen[qs]=(i==0?1160:1472)+47;
   for(j=0;j<qlen[qs];j=j+1)link_bytes[qs*2048+j]=independent[i*2048+j];tails[1]=tails[1]+1;
   pause(180000);
  end
  t=0;while(unique<=id && t<100000)begin pause(10);t=t+10;end
  ck(unique==id+1,"independent_reordered_duplicate_IP_delivery",id+1,unique);pause(100);
  // Correct per-fragment IP/FCS cannot substitute for whole UDP verification.
  for(i=4;i<7;i=i+1)begin
   qs=16+tails[1]%16;qlen[qs]=(i==6?1160:1472)+47;
   for(j=0;j<qlen[qs];j=j+1)link_bytes[qs*2048+j]=independent[i*2048+j];tails[1]=tails[1]+1;pause(180000);
  end
  ck(unique==id+1,"bad_whole_UDP_zero_application_commit",id+1,unique);
  id=exp_tail;expected_vl[id]=16'h42;expected_length[id]=4096;expected_seed[id]=131;exp_tail=exp_tail+1;
  $fdisplay(fd_app,"EXTERNAL id=%0d vl=66 length=4096 seed=131 time_ns=%0d",id,$time);
  for(i=7;i<10;i=i+1)begin
   qs=16+tails[1]%16;qlen[qs]=(i==9?1160:1472)+47;
   for(j=0;j<qlen[qs];j=j+1)link_bytes[qs*2048+j]=independent[i*2048+j];tails[1]=tails[1]+1;pause(180000);
  end
  t=0;while(unique<=id && t<100000)begin pause(10);t=t+10;end
  ck(unique==id+1,"independent_recovery_after_whole_UDP_failure",id+1,unique);
 end endtask
 parameter EQ_SHORT=0,CHECKPOINT_MODE=0;
 reg checkpoint_ready=0,resume_go=0;
 initial begin
  fd_wire=$fopen("frames.log","w");fd_app=$fopen("application.log","w");fd_link=$fopen("links.log","w");fd_events=$fopen("events.log","w");fd_stimulus=$fopen("stimulus.log","w");
  $readmemh("vectors/fragment/c42s/independent.hex",independent);
  $readmemh("vectors/fragment/c42s/eq-extra.hex",eq_extra);
  heads[0]=0;heads[1]=0;tails[0]=0;tails[1]=0;
  pause(12);rst_n=1;wait(configured);ck(!config_failed,"public_configuration_complete",0,config_failed);pause(10);
  if(CHECKPOINT_MODE)begin checkpoint_ready=1;wait(resume_go);end
  app_tx_error_ready=1;app_rx_desc_ready=1;app_rx_ready=1;
  if(EQ_SHORT)begin
   cases=cases+1;label="new_complete_EQ_high_RAM_three_fragments_and_explicit_partial_cancel";
   // Hold one independently received context to force actual long traffic into bank1.
   late_slot=16+tails[1]%16;qlen[late_slot]=1519;
   for(late_j=0;late_j<1519;late_j=late_j+1)link_bytes[late_slot*2048+late_j]=independent[3*2048+late_j];tails[1]=tails[1]+1;
   pause(30000);config_source.read_word(3,15,1,csr);ck(csr==1,"independent_incomplete_context_owned",1,csr);
   message(16'h8001,1,91);message(1,4096,31);
   // Finish the older bank0 message AFTER different bank1 contents were read.
   expected_vl[exp_tail]=16'h42;expected_length[exp_tail]=4096;expected_seed[exp_tail]=131;
   $fdisplay(fd_app,"EXTERNAL id=%0d vl=66 length=4096 seed=131 time_ns=%0d",exp_tail,$time);exp_tail=exp_tail+1;
   for(late_j=0;late_j<3;late_j=late_j+1)begin
    late_slot=16+tails[1]%16;qlen[late_slot]=(late_j==0 ? 1160:1472)+47;
    for(late_i=0;late_i<qlen[late_slot];late_i=late_i+1)link_bytes[late_slot*2048+late_i]=eq_extra[late_j*2048+late_i];
    tails[1]=tails[1]+1;pause(30000);
   end
   ck(unique==3,"distinct_bank0_contents_survive_bank1",3,unique);
   config_source.write_word(3,0,0,15,7,1);
  end else begin
  cases=cases+1;label="short_compatibility_and_boundaries";
  message(1,1,91);message(1,1470,71);message(1,1471,61);
  cases=cases+1;label="actual_two_and_three_fragments";
  message(1,1472,47);rx_stalls=1;message(1,3001,81);rx_stalls=0;app_rx_ready=1;
  cases=cases+1;label="A_external_drop_B_actual_long_message";drop_a=1;message(16'h8001,4096,31);drop_a=0;
  // After RM's1ms recovery window, an actual late valid old frame reaches reassembly.
  pause(150000);late_slot=tails[0]%16;qlen[late_slot]=late_length;
  for(late_j=0;late_j<late_length;late_j=late_j+1)link_bytes[late_slot*2048+late_j]=late_copy[late_j];tails[0]=tails[0]+1;
  $fdisplay(fd_link,"LATE_A_REINJECT bytes=%0d time_ns=%0d",late_length,$time);pause(20000);
  ck(unique==input_count,"late_old_fragment_no_duplicate",input_count,unique);
  cases=cases+1;label="A_recovery_high_VLID_and_limits";message(1,4096,31);
  app_source.reject_command(1,0);app_source.reject_command(1,4097);app_source.reject_command(16'h4001,10);
  ck(app_error_count==3,"zero_oversize_unknown_reject",3,app_error_count);message(1,128,17);
  cases=cases+1;label="independent_server_reordered_and_duplicate_IP_fragments";independent_receive;
  end
  pause(2000);ck(heads[0]==tails[0] && heads[1]==tails[1],"links_drained",tails[0]+tails[1],heads[0]+heads[1]);
  ck(unique==input_count+(EQ_SHORT?1:2) && exp_head==exp_tail,"all_accepted_plus_external_unique_delivery",input_count+(EQ_SHORT?1:2),unique);
  config_source.read_word(3,15,1,csr);ck(csr==(EQ_SHORT?3:7),"actual_reassembly_allocations",EQ_SHORT?3:7,csr);
  config_source.read_word(3,15,2,csr);ck(csr==(EQ_SHORT?3:7),"actual_reassembly_releases",EQ_SHORT?3:7,csr);
  config_source.read_word(3,15,3,csr);ck(csr==(EQ_SHORT?1:2),"only_declared_late_UDP_or_cancel_rejections",EQ_SHORT?1:2,csr);
  config_source.read_word(3,15,4,csr);ck(csr==(EQ_SHORT?2:6),"actual_whole_UDP_completions",EQ_SHORT?2:6,csr);
  config_source.read_word(3,15,5,csr);ck(csr[1:0]==0,"all_message_slots_free",0,csr[1:0]);
  config_source.write_word(2,0,0,0,0,0);
  config_source.read_word(2,18,0,csr);ck(csr==0,"no_frame_pool_ownership_error",0,csr);
  config_source.read_word(2,28,0,csr);ck(csr[15:0]==0,"TX_pool_free",0,csr[15:0]);
  config_source.read_word(2,29,0,csr);ck(csr[15:0]==0,"RX_pool_free",0,csr[15:0]);
  config_source.read_word(2,24,0,csr);ck(csr==unique,"real_MIB_application_messages_not_fragments",unique,csr);
  config_source.read_word(2,25,0,csr);ck(csr==(EQ_SHORT?8193:23927),"real_MIB_application_bytes_exclude_UDP_headers",EQ_SHORT?8193:23927,csr);
  $fdisplay(fd_events,"FINAL cases=%0d input=%0d unique=%0d TX=%0d RX=%0d errors=%0d",cases,input_count,unique,txframes,rxframes,app_error_count);
  done=1;$display("C42S_SYSTEM_PASS cases=%0d checks=%0d input=%0d unique=%0d TX=%0d RX=%0d",cases,checks,input_count,unique,txframes,rxframes);$finish;
 end
 initial begin #100000000;ck(0,"system_function_deadline",0,1);end
 initial begin #5000000;if(CHECKPOINT_MODE && !checkpoint_ready)ck(0,"initialization_HDL_deadline",1,checkpoint_ready);end

endmodule
