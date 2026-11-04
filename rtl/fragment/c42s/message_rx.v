// C42-S. Serial bounded range bookkeeping, two shared message RAM regions.
// Input is exclusively the protocol/IP/FCS/IC/RM-approved winner stream.
module message_rx #(
 parameter [32:0] TIMEOUT_CYCLES=33'd6000000000
)(
 input wire clk,rst_n,config_applied,
 input wire [127:0] s_fragment,input wire s_desc_valid,output wire s_desc_ready,
 input wire [15:0] s_length,s_vl,s_app,s_version,input wire [7:0] s_sn,
 input wire s_checked,s_network,input wire [7:0] s_data,input wire s_valid,s_sop,s_last,output wire s_ready,
 output wire m_desc_valid,input wire m_desc_ready,
 output wire [15:0] m_length,m_vl,m_app,m_version,output wire [7:0] m_sn,
 output wire m_checked,m_network,output wire [7:0] m_data,output wire m_valid,m_sop,m_last,input wire m_ready,
 output reg [31:0] allocated,released,rejected,completed,output wire [1:0] used,output reg [1:0] peak
);
 localparam IDLE=0,PASS=1,RANGES=2,DATA=3,DUP_REQ=4,DUP_WAIT=5,DUP_DATA=6,DROP=7,EVAL=8,SUM_REQ=9,SUM_WAIT=10,CHECK=11;
 reg [3:0] state;
 (* ramstyle="M4K" *) reg [7:0] ram[0:16383];
 reg [1:0] owned,complete_mask,checked_mask;
 reg [143:0] keys[0:1];
 reg [15:0] apps[0:1],totals[0:1],counts[0:1];
 reg [7:0] sns[0:1];reg [1:0] networks,first_seen,last_seen;
 reg [32:0] ages[0:1];
 reg [3:0] nranges[0:1];
 reg [15:0] range_start[0:15],range_end[0:15];
 reg [15:0] range_more;
 reg [143:0] tomb_keys[0:3];reg [3:0] tomb_valid;reg [32:0] tomb_age[0:3];reg [1:0] tomb_next;
 reg slot;reg [15:0] base,flen,ending,pos;reg mf,bad,duplicate;
 reg [3:0] range_scan;
 reg [31:0] sum;
 reg [7:0] high,dup_byte;
 reg [63:0] udp_head;
 reg out_active,out_read,out_wait,out_valid,out_slot;
 reg [15:0] out_pos;reg [7:0] out_byte;
 reg [7:0] q;reg rd_valid;reg [1:0] rd_tag;
 wire fragment=s_fragment[111:96]!=0;
 wire [143:0] input_key={s_vl,s_version,s_fragment[127:112],s_fragment[95:0]};
 wire match0=owned[0] && keys[0]==input_key,match1=owned[1] && keys[1]==input_key;
 wire hit=match0 || match1;
 wire pick=match1 || (!match0 && !match1 && owned[0]);
 wire [16:0] input_base={1'b0,s_fragment[108:96],3'b0};
 wire [16:0] input_end=input_base+{1'b0,s_length};
 wire late=(tomb_valid[0] && tomb_keys[0]==input_key) || (tomb_valid[1] && tomb_keys[1]==input_key) ||
    (tomb_valid[2] && tomb_keys[2]==input_key) || (tomb_valid[3] && tomb_keys[3]==input_key);
 wire invalid=s_length==0 || input_end>4104 || s_fragment[110] || s_fragment[111] ||
     (s_fragment[109] && s_length[2:0]!=0);
 wire choose_complete=complete_mask[1] && !complete_mask[0];
 wire expiry_pending=(owned[0] && !complete_mask[0] && !(out_active && !out_slot) && ages[0]>=TIMEOUT_CYCLES) ||
   (owned[1] && !complete_mask[1] && !(out_active && out_slot) && ages[1]>=TIMEOUT_CYCLES);
 wire pass_desc=state==IDLE && !out_active && complete_mask==0 && !fragment;
 wire frag_desc=state==IDLE && fragment;
 assign s_desc_ready=rst_n && !config_applied && !expiry_pending && (frag_desc || (pass_desc && m_desc_ready));
 assign s_ready=rst_n && (state==PASS ? m_ready:(state==DATA || state==DUP_DATA || state==DROP));
 assign m_desc_valid=rst_n && (out_active ? !out_read:(pass_desc && s_desc_valid && !config_applied && !expiry_pending));
 assign m_length=out_active ? totals[out_slot]-8:s_length;
 assign m_vl=out_active ? keys[out_slot][143:128]:s_vl;
 assign m_version=out_active ? keys[out_slot][127:112]:s_version;
 assign m_app=out_active ? apps[out_slot]:s_app;
 assign m_sn=out_active ? sns[out_slot]:s_sn;
 assign m_checked=out_active ? checked_mask[out_slot]:s_checked;
 // A validated long datagram may legally carry the IPv4 zero-checksum sentinel.
 assign m_network=out_active ? networks[out_slot]:s_network;
 assign m_valid=rst_n && (out_active ? (out_read && out_valid):(state==PASS && s_valid));
 assign m_data=out_active ? out_byte:s_data;
 assign m_sop=out_active ? out_pos==0:s_sop;
 assign m_last=out_active ? out_pos==totals[out_slot]-9:s_last;
 assign used={1'b0,owned[0]}+{1'b0,owned[1]};
 wire data_fire=s_valid && s_ready;
 wire out_fire=out_active && m_valid && m_ready;
 wire read_sum=state==SUM_REQ,read_dup=state==DUP_REQ;
 wire read_out=out_active && out_read && !out_valid && !out_wait && !read_sum && !read_dup;
 wire rd_en=read_sum || read_dup || read_out;
 wire [13:0] rd_address=read_sum ? {slot,13'd0}+pos:read_dup ? {slot,13'd0}+base+pos:{out_slot,13'd0}+out_pos+14'd8;
 wire [1:0] tag=read_sum ? 2'd1:read_dup ? 2'd2:2'd3;
 wire [4:0] range_address={slot,3'd0}+range_scan;
 wire exact=range_start[range_address]==base && range_end[range_address]==ending;
 wire overlap=base<range_end[range_address] && ending>range_start[range_address];
 wire [31:0] folded={16'd0,sum[15:0]}+{16'd0,sum[31:16]};
 integer i;
 reg [1:0] release_mask,tomb_cursor;reg [2:0] reject_bump;
 always @(posedge clk)begin
  if(state==DATA && data_fire)ram[{slot,13'd0}+base+pos]<=s_data;
  if(rd_en)q<=ram[rd_address];
 end
 task retire;input which;
 begin
  owned[which]<=0;complete_mask[which]<=0;release_mask[which]=1;
  tomb_keys[tomb_cursor]<=keys[which];tomb_valid[tomb_cursor]<=1;tomb_age[tomb_cursor]<=0;tomb_cursor=tomb_cursor+1'b1;
 end endtask
 always @(posedge clk)begin
  if(!rst_n)begin
   state<=IDLE;owned<=0;complete_mask<=0;slot<=0;base<=0;flen<=0;ending<=0;pos<=0;mf<=0;bad<=0;duplicate<=0;range_scan<=0;
   sum<=0;high<=0;dup_byte<=0;udp_head<=0;out_active<=0;out_read<=0;out_wait<=0;out_valid<=0;out_slot<=0;out_pos<=0;out_byte<=0;
   rd_valid<=0;rd_tag<=0;allocated<=0;released<=0;rejected<=0;completed<=0;peak<=0;networks<=0;first_seen<=0;last_seen<=0;checked_mask<=0;
   tomb_valid<=0;tomb_next<=0;range_more<=0;
   for(i=0;i<2;i=i+1)begin keys[i]<=0;apps[i]<=0;totals[i]<=0;counts[i]<=0;sns[i]<=0;ages[i]<=0;nranges[i]<=0;end
   for(i=0;i<16;i=i+1)begin range_start[i]<=0;range_end[i]<=0;end
   for(i=0;i<4;i=i+1)begin tomb_keys[i]<=0;tomb_age[i]<=0;end
  end else begin
   release_mask=0;reject_bump=0;tomb_cursor=tomb_next;
   rd_valid<=rd_en;if(rd_en)rd_tag<=tag;
   if(used>peak)peak<=used;
   for(i=0;i<4;i=i+1)if(tomb_valid[i])begin
    if(tomb_age[i]>=TIMEOUT_CYCLES)tomb_valid[i]<=0;else tomb_age[i]<=tomb_age[i]+1'b1;
   end
   for(i=0;i<2;i=i+1)if(owned[i] && !complete_mask[i] && !(out_active && out_slot==i))begin
    if(ages[i]<TIMEOUT_CYCLES)ages[i]<=ages[i]+1'b1;
    if(state==IDLE && ages[i]>=TIMEOUT_CYCLES)begin retire(i);reject_bump=reject_bump+1;end
   end
   if(read_out)out_wait<=1;
   if(rd_valid && rd_tag==3)begin out_byte<=q;out_valid<=1;out_wait<=0;end
   if(!out_active && state!=PASS && complete_mask!=0)begin
    out_active<=1;out_slot<=choose_complete;out_read<=0;out_pos<=0;out_valid<=0;out_wait<=0;
    complete_mask[choose_complete]<=0;
   end
   if(out_active && m_desc_valid && m_desc_ready)out_read<=1;
   if(out_fire)begin
    out_valid<=0;
    if(m_last)begin retire(out_slot);out_active<=0;out_read<=0;end
    else out_pos<=out_pos+1'b1;
   end
   case(state)
    IDLE:if(s_desc_valid && s_desc_ready)begin
     if(!fragment)state<=PASS;
     else if(invalid || late || (!hit && owned==3) || (hit && (complete_mask[pick] || (out_active && out_slot==pick))))begin
      state<=DROP;reject_bump=reject_bump+1;
     end else begin
      slot<=pick;base<=input_base[15:0];flen<=s_length;ending<=input_end[15:0];pos<=0;mf<=s_fragment[109];bad<=0;duplicate<=0;range_scan<=0;
      if(!hit)begin
       owned[pick]<=1;keys[pick]<=input_key;apps[pick]<=s_app;sns[pick]<=s_sn;networks[pick]<=s_network;
       counts[pick]<=0;nranges[pick]<=0;first_seen[pick]<=0;last_seen[pick]<=0;totals[pick]<=0;ages[pick]<=0;
       allocated<=allocated+1;
      end
      state<=RANGES;
     end
    end
    PASS:if(data_fire && s_last)state<=IDLE;
    RANGES:begin
     if(range_scan<nranges[slot])begin
      if(exact && mf==range_more[range_address])begin duplicate<=1;state<=DUP_REQ;end
      else if(overlap || (!mf && range_end[range_address]>ending))begin retire(slot);state<=DROP;reject_bump=reject_bump+1;end
      else range_scan<=range_scan+1'b1;
     end else if(nranges[slot]==8 || (last_seen[slot] && ending>totals[slot]) || (!mf && last_seen[slot] && ending!=totals[slot]))begin
      retire(slot);state<=DROP;reject_bump=reject_bump+1;
     end else begin
      // A new final end may not cut across a previously accepted range.
      if(!mf && counts[slot]>ending)begin retire(slot);state<=DROP;reject_bump=reject_bump+1;end
      else state<=DATA;
     end
    end
    DATA:if(data_fire)begin
     if(s_sop!=(pos==0) || s_last!=(pos==flen-1))bad<=1;
     if(s_last)begin
      if(bad || s_sop!=(pos==0) || pos!=flen-1)begin retire(slot);reject_bump=reject_bump+1;state<=IDLE;end
      else begin
       range_start[{slot,3'd0}+nranges[slot]]<=base;range_end[{slot,3'd0}+nranges[slot]]<=ending;
       range_more[{slot,3'd0}+nranges[slot]]<=mf;
       nranges[slot]<=nranges[slot]+1'b1;counts[slot]<=counts[slot]+flen;
       if(base==0)first_seen[slot]<=1;
       if(!mf)begin totals[slot]<=ending;last_seen[slot]<=1;end
       state<=EVAL;
      end
     end else if(pos>=flen-1)begin retire(slot);reject_bump=reject_bump+1;state<=DROP;end
     else pos<=pos+1;
    end
    DUP_REQ:state<=DUP_WAIT;
    DUP_WAIT:if(rd_valid && rd_tag==2)begin dup_byte<=q;state<=DUP_DATA;end
    DUP_DATA:if(data_fire)begin
     if(s_data!=dup_byte || s_sop!=(pos==0) || s_last!=(pos==flen-1))bad<=1;
     if(s_last)begin
      if(bad || s_data!=dup_byte || pos!=flen-1)begin retire(slot);reject_bump=reject_bump+1;end
      state<=IDLE;
     end else if(pos>=flen-1)begin retire(slot);reject_bump=reject_bump+1;state<=DROP;end
     else begin pos<=pos+1;state<=DUP_REQ;end
    end
    DROP:if(data_fire && s_last)state<=IDLE;
    EVAL:if(first_seen[slot] && last_seen[slot] && counts[slot]==totals[slot])begin
     pos<=0;udp_head<=0;
     sum<={16'd0,keys[slot][95:80]}+{16'd0,keys[slot][79:64]}+{16'd0,keys[slot][63:48]}+{16'd0,keys[slot][47:32]}+32'd17+{16'd0,totals[slot]};
     state<=SUM_REQ;
    end else state<=IDLE;
    SUM_REQ:state<=SUM_WAIT;
    SUM_WAIT:if(rd_valid && rd_tag==1)begin
     if(pos<8)udp_head<={udp_head[55:0],q};
     if(!pos[0])high<=q;
     if(pos[0])sum<=sum+{16'd0,high,q};else if(pos==totals[slot]-1)sum<=sum+{16'd0,q,8'd0};
     if(pos==totals[slot]-1)state<=CHECK;else begin pos<=pos+1;state<=SUM_REQ;end
    end
    CHECK:if(sum[31:16]!=0)sum<=folded;
     else begin
      if(totals[slot]<9 || totals[slot]>4104 || udp_head[63:32]!=keys[slot][31:0] || udp_head[31:16]!=totals[slot] ||
         (udp_head[15:0]!=0 && sum[15:0]!=16'hffff))begin retire(slot);reject_bump=reject_bump+1;end
      else begin complete_mask[slot]<=1;checked_mask[slot]<=udp_head[15:0]!=0;completed<=completed+1;end
      state<=IDLE;
     end
    default:state<=IDLE;
   endcase
   if(config_applied)begin
    for(i=0;i<2;i=i+1)if(owned[i] && !complete_mask[i] && !(out_active && out_slot==i))begin
     retire(i);reject_bump=reject_bump+1;
    end
    if(state!=IDLE && state!=PASS && state!=DROP)begin
     if(state==DATA || state==DUP_REQ || state==DUP_WAIT || state==DUP_DATA || state==RANGES)
      state<=(data_fire && s_last) ? IDLE:DROP;
     else state<=IDLE;
    end
   end
   released<=released+{30'd0,release_mask[0]}+{30'd0,release_mask[1]};
   rejected<=rejected+{29'd0,reject_bump};tomb_next<=tomb_cursor;
  end
 end
endmodule
