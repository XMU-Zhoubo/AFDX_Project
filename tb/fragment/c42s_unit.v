`timescale 1ns/1ps
module c42s_unit;
 reg clk=0,rst_n=0;always #5 clk=~clk;
 integer cycles=0,checks=0,failures=0;reg done=0;
 always @(posedge clk)cycles<=cycles+1;
 integer txpos=0;
 reg start=0,abort=0,iv=0,il=0,commit=0;reg [7:0] idata=0;wire start_ready,ir,cr;
 wire fv,fr,mv,mr,ml,txidle,txerror;wire [7:0] md;wire [15:0] flen,fid,flags;
 wire [31:0] txacc,txcomplete,txcancel;
 reg inject=0,cancel_at_last=0;reg dv=0,v=0,sp=0,last=0;reg [7:0] data=0;reg [15:0] len=0,vl=1,version=1,ident=16'h8888,fflags=0;
 wire dr,rdy;reg fc=0;
 localparam [95:0] EP=96'h0a010101e0e0000112345678;
 message_tx sender(.clk(clk),.rst_n(rst_n),.abort(abort),.seed_valid(1'b1),.seed(16'h1000),.seed_ready(),.start_valid(start),.start_ready(start_ready),.length(16'd4096),.endpoints(EP),
 .s_data(idata),.s_valid(iv),.s_last(il),.s_ready(ir),.commit_valid(commit),.commit_ready(cr),
 .fragment_valid(fv),.fragment_ready(fr),.fragment_length(flen),.fragment_id(fid),.fragment_flags(flags),
 .m_data(md),.m_valid(mv),.m_last(ml),.m_ready(mr),.fragment_committed(fc),.idle(txidle),.error_event(txerror),.accepted_count(txacc),.completed_count(txcomplete),.cancel_count(txcancel));
 reg outready=0,desc_ready=1,apply=0;wire desc,ov,os,ol;wire [7:0] od,osn;wire [15:0] olen,ovl,oapp,over;
 wire checked,network;wire [31:0] alloc,release_count,rejects,complete;wire [1:0] used,peak;
 wire [127:0] frag=inject ? {ident,fflags,EP}:{fid,flags,EP};
 message_rx #(.TIMEOUT_CYCLES(100000)) receiver(.clk(clk),.rst_n(rst_n),.config_applied(apply),
 .s_fragment(frag),.s_desc_valid(inject ? dv:fv),.s_desc_ready(dr),.s_length(inject ? len:flen),.s_vl(vl),.s_app(16'h1234),.s_version(version),.s_sn(8'd5),.s_checked(1'b1),.s_network(1'b0),
 .s_data(inject ? data:md),.s_valid(inject ? v:mv),.s_ready(rdy),.s_sop(inject ? sp:txpos==0),.s_last(inject ? last:ml),
 .m_desc_valid(desc),.m_desc_ready(desc_ready),.m_length(olen),.m_vl(ovl),.m_app(oapp),.m_version(over),.m_sn(osn),.m_checked(checked),.m_network(network),
 .m_data(od),.m_valid(ov),.m_ready(outready),.m_sop(os),.m_last(ol),.allocated(alloc),.released(release_count),.rejected(rejects),.completed(complete),.used(used),.peak(peak));
 assign fr=!inject && dr;assign mr=!inject && rdy;
 reg [7:0] gold[0:4103],gold_alt[0:4103],app[0:4095];integer i,j,k,totalpos=0,part=0,delivered=0,outpos=0,descriptors=0;reg txwaiting=0;
 reg input_alt=0,output_alt=0;reg [7:0] expected_byte;
 reg [15:0] expected_vl[0:8],expected_version[0:8];
 reg desc_stalled=0;reg [63:0] held_desc;
 task ck;input ok;input [255:0] what;input [63:0] expected,actual;
 begin checks=checks+1;if(ok!==1)begin failures=failures+1;$display("C42S_MISMATCH %0s cycle=%0d expected=%h actual=%h",what,cycles,expected,actual);$finish;end end endtask
 always @(negedge clk)begin
  fc=txwaiting;txwaiting=0;
 end
 always @(posedge clk)if(rst_n)begin
  if(!inject && fv && fr)begin
   ck(fid==16'h1000,"one_message_ID",16'h1000,fid);ck(flags[12:0]*8==totalpos,"offset8",totalpos,flags[12:0]*8);
   ck(flen==(part<2 ? 1472:1160),"fragment_length",part<2 ? 1472:1160,flen);txpos=0;part=part+1;
  end
  if(!inject && mv && mr)begin
   ck(md==gold[totalpos],"independent_IP_payload_byte",gold[totalpos],md);txpos=txpos+1;totalpos=totalpos+1;
   if(ml)txwaiting=1;
  end
  if(desc_stalled)ck(desc && {olen,ovl,oapp,over}===held_desc,"descriptor_backpressure_stable",held_desc,{olen,ovl,oapp,over});
  desc_stalled=desc && !desc_ready;held_desc={olen,ovl,oapp,over};
  if(desc && desc_ready)begin outpos=0;output_alt=descriptors==4;ck(olen==4096,"whole_message_length",4096,olen);
   ck(ovl==expected_vl[descriptors] && over==expected_version[descriptors] && oapp==16'h1234,"VL_version_app_snapshot",{expected_vl[descriptors],16'h1234,expected_version[descriptors]},{ovl,oapp,over});descriptors=descriptors+1;end
  if(ov && outready)begin
   expected_byte=output_alt ? (outpos*73+(outpos>>8)*19+131)&255:app[outpos];
   ck(od==expected_byte,"whole_application_byte",expected_byte,od);ck(os==(outpos==0),"output_SOP",outpos==0,os);ck(ol==(outpos==4095),"output_LAST",outpos==4095,ol);
   outpos=outpos+1;if(ol)delivered=delivered+1;
  end
 end
 task pause;input integer n;begin repeat(n)@(negedge clk);end endtask
 task piece;input integer off,n;input more;input integer corrupt;
 begin
  @(negedge clk);fflags=(more ? 16'h2000:0)|(off/8);len=n;dv=1;
  @(posedge clk);while(!dr)@(posedge clk);@(negedge clk);dv=0;
  for(j=0;j<n;j=j+1)begin
   data=(input_alt ? gold_alt[off+j]:gold[off+j])^(corrupt && j==n-1 ? 8'h80:0);sp=j==0;last=j==n-1;v=1;
   if(cancel_at_last && j==n-1)apply=1;
   @(posedge clk);while(!rdy)@(posedge clk);@(negedge clk);v=0;
  end
  sp=0;last=0;apply=0;cancel_at_last=0;pause(3);
 end endtask
 task wait_delivery;input integer wanted;integer n;
 begin n=0;while(delivered<wanted && n<60000)begin pause(1);n=n+1;end ck(delivered==wanted,"bounded_delivery",wanted,delivered);end endtask
 initial begin
  for(i=0;i<9;i=i+1)begin expected_vl[i]=1;expected_version[i]=1;end
  expected_vl[4]=16'h8001;expected_version[5]=3;
  $readmemh("vectors/fragment/c42s/u4096.hex",gold);$readmemh("vectors/fragment/c42s/u4096-alt.hex",gold_alt);$readmemh("vectors/fragment/c42s/p4096.hex",app);
  pause(4);rst_n=1;pause(4);start=1;@(posedge clk);while(!start_ready)@(posedge clk);@(negedge clk);start=0;
  for(i=0;i<4096;i=i+1)begin idata=app[i];iv=1;il=i==4095;@(posedge clk);while(!ir)@(posedge clk);@(negedge clk);iv=0;if(i%17==0)pause(2);end
  il=0;commit=1;@(posedge clk);while(!cr)@(posedge clk);@(negedge clk);commit=0;
  pause(2);abort=1;pause(3);abort=0;
  pause(30000);ck(totalpos==4104,"actual_three_fragments",4104,totalpos);ck(complete==1,"whole_UDP_verified",1,complete);
  ck(used==1,"output_backpressure_owns_slot",1,used);outready=1;wait_delivery(1);pause(5);ck(used==0 && alloc==release_count,"resources_return",alloc,release_count);
  inject=1;ident=16'h8888;
  piece(2944,1160,0,0);piece(1472,1472,1,0);piece(1472,1472,1,0);piece(0,1472,1,0);wait_delivery(2);
  pause(5);ck(alloc==release_count && used==0,"reorder_duplicate_no_leak",alloc,release_count);
  ident=16'h8889;piece(0,1472,1,0);piece(1464,1472,1,0);pause(5);ck(delivered==2 && used==0,"overlap_reject",0,used);
  ident=16'h8890;piece(0,1472,1,0);piece(1472,1472,1,0);piece(2944,1160,0,1);pause(30000);ck(delivered==2 && used==0,"bad_whole_checksum",0,used);
  ident=16'h8891;piece(0,1472,1,0);pause(100010);ck(used==0 && delivered==2,"missing_timeout",0,used);
  ident=16'h8892;piece(0,1472,1,0);piece(1472,1472,1,0);piece(2944,1160,0,0);wait_delivery(3);
  pause(5);outready=0;desc_ready=0;
  ident=16'h8900;vl=1;piece(0,1472,1,0);vl=16'h8001;input_alt=1;piece(0,1472,1,0);
  ck(used==2,"both_shared_contexts",2,used);
  ident=16'h8902;piece(0,1472,1,0);ck(used==2,"full_pool_preserves_owners",2,used);
  ident=16'h8900;vl=1;input_alt=0;piece(1472,1472,1,0);piece(2944,1160,0,0);pause(16000);
  vl=16'h8001;input_alt=1;piece(2944,1160,0,0);piece(1472,1472,1,0);pause(16000);input_alt=0;
  ck(complete==5,"two_independent_complete",5,complete);desc_ready=1;outready=1;wait_delivery(5);
  ident=16'h8910;vl=1;version=1;piece(0,1472,1,0);version=2;piece(0,1472,1,0);
  ck(used==2,"same_ID_different_config_versions_isolated",2,used);
  apply=1;pause(1);apply=0;pause(3);ck(used==0 && alloc==release_count,"APPLY_reclaims_both_same_cycle",alloc,release_count);
  ident=16'h8912;version=3;piece(0,1472,1,0);piece(1472,1472,1,0);piece(2944,1160,0,0);wait_delivery(6);version=1;
  pause(8);ck(alloc==release_count && used==0,"final_resource_conservation",alloc,release_count);
  ck(txacc==1 && txcomplete==1 && txcancel==0 && !txerror,"TX_lifecycle",1,txcomplete);
  // A partially supplied long input is never visible to the frame queues.
  start=1;@(posedge clk);while(!start_ready)@(posedge clk);@(negedge clk);start=0;
  for(i=0;i<16;i=i+1)begin idata=app[i];iv=1;il=0;@(posedge clk);while(!ir)@(posedge clk);@(negedge clk);iv=0;end
  abort=1;pause(1);abort=0;pause(3);ck(txidle && txcancel==1 && part==3,"partial_long_cancel_no_fragments",1,txcancel);
  ident=16'h8920;piece(0,1472,1,0);piece(1472,1472,1,0);piece(1472,1472,0,0);
  ck(used==0,"conflicting_final_flag_reclaims",0,used);
  ident=16'h8930;piece(4096,16,0,0);ck(used==0,"oversize_offset_no_allocation",0,used);
  ident=16'h8931;cancel_at_last=1;piece(0,1472,1,0);
  ck(dr && used==0,"cancel_with_LAST_accepts_next_descriptor",1,dr);
  ident=16'h8940;piece(0,1472,1,0);piece(1472,1472,1,0);piece(2944,1160,0,0);
  outready=0;pause(16000);ck(used==1,"published_message_held_before_reset",1,used);
  $display("C42S_UNIT_PRE_RESET alloc=%0d released=%0d reset_cancel=%0d delivered=%0d",alloc,release_count,used,delivered);
  rst_n=0;pause(3);rst_n=1;pause(3);ck(used==0 && !ov && !desc,"reset_clears_old_response",0,used);
  outready=1;ident=16'h8941;piece(0,1472,1,0);piece(1472,1472,1,0);piece(2944,1160,0,0);wait_delivery(7);
  pause(5);ck(alloc==1 && release_count==1 && used==0,"post_reset_new_transaction_recovers",1,release_count);
  done=1;$display("C42S_UNIT_PASS checks=%0d fragments=%0d delivered=%0d alloc=%0d free=%0d rejects=%0d",checks,part,delivered,alloc,release_count,rejects);$finish;
 end
 initial begin #5000000;ck(0,"unit_function_deadline",0,1);end
endmodule
