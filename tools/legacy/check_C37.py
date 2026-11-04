"""Independent public GMII/device-link file and reset-epoch accounting."""
import sys,json,re,hashlib,bisect
from pathlib import Path
sys.dont_write_bytecode=True
from check_C36 import frame,parse as download_parse
from check_C35 import parse_status
from load665_ref import validate_package

def check(folder,group=0):
 d=Path(folder);events=(d/'events.log').read_text();reset=[int(x)*1000 for x in re.findall(r'RESET_EPOCH old_tag=[0-9a-f]+ time_ns=(\d+)',events)]
 contexts={};frames=[];status=[];ACK=[];peer_errors=[];raw_files={}
 for line in (d/'injections.log').read_text().splitlines():
  net,t,n,h=line.split();sp,dp,p=frame(h)
  if p[:2]==b'\0\4':ACK.append(dict(net=int(net),source=sp,destination=dp,block=int.from_bytes(p[2:4],'big'),end_ns=int(t)+int(n)*8+8))
  if p[:2]==b'\0\5':peer_errors.append(dict(net=int(net),source=sp,destination=dp,code=int.from_bytes(p[2:4],'big'),end_ns=int(t)+int(n)*8+8))
 for line in (d/'wire.log').read_text().splitlines():
  net,start,end,h=line.split();net,start,end=int(net),int(start),int(end);sp,dp,p=frame(h);op=int.from_bytes(p[:2],'big');frames.append((net,start,end,sp,dp,op))
  if op==2:
   name=p[2:].split(b'\0')[0].decode();key=(bisect.bisect_right(reset,start*1000),net,sp);assert key not in contexts;contexts[key]=dict(name=name,network=net,TID=sp,WRQ_ns=start,blocks={},last_ns=end,physical_DATA=0)
  if op==3 and sp<49152:
   key=(bisect.bisect_right(reset,start*1000),net,sp);c=contexts[key];block=int.from_bytes(p[2:4],'big');b=p[4:]
   if block in c['blocks']:assert c['blocks'][block]==b
   else:assert block==len(c['blocks'])+1;c['blocks'][block]=b
   c['last_ns']=end;c['physical_DATA']+=1
   if c['name'].endswith(('.LUS','.LNS')):
    kind='LUS' if c['name'].endswith('.LUS') else 'LNS';x=parse_status(b) if kind=='LUS' else download_parse(b,'LNS')
    a=[a for a in ACK if a['net']==net and a['destination']==sp and a['source']==dp and a['block']==block and a['end_ns']>end]
    status.append(dict(kind=kind,decoded=x,wire_ns=start,wire_end_ns=end,raw=b.hex(),epoch=key[0],network=net,TID=sp,acknowledged=bool(a),ACK_end_ns=a[0]['end_ns'] if a else None))
   elif c['name'].endswith('.LNL'):assert download_parse(b,'LNL')['files']==[('SMALL.BIN',''),('BIG64.BIN','')]
 downloaded=[];unfinished=[]
 for c in contexts.values():
  if c['name'] not in ['SMALL.BIN','BIG64.BIN']:continue
  b=b''.join(c['blocks'].values());gold=(d/'inputs/vectors/615a/c36'/('data_big.bin' if c['name']=='BIG64.BIN' else 'data_small.bin')).read_bytes();assert b==gold[:len(b)]
  final=max(c['blocks']) if c['blocks'] else None;matches=[a for a in ACK if a['net']==c['network'] and a['destination']==c['TID'] and a['source']==42010 and a['block']==final and a['end_ns']>c['last_ns']]
  x={k:v for k,v in c.items() if k!='blocks'};x.update(bytes=len(b),sha256=hashlib.sha256(b).hexdigest())
  if matches and len(b)==len(gold) and len(c['blocks'][final])<512:x['data_final_ACK_ns']=min(a['end_ns'] for a in matches);downloaded.append(x)
  else:unfinished.append(x)
 # Actual DUT storage-readback bytes, never a TB-preloaded return value.
 readback={}
 for line in (d/'readback.log').read_text().splitlines():
  epoch,uid,off,b=line.split();readback.setdefault((int(epoch),int(uid)),{})[int(off)]=int(b,16)
 uploaded=[]
 for key,x in readback.items():
  b=bytes(x[i] for i in range(len(x)));gold=(d/'inputs/vectors/615a/c35/data0.bin').read_bytes();assert b==gold
  h=(d/'inputs/vectors/615a/c35/header0.bin').read_bytes();validate_package(h,b);uploaded.append(dict(key=key,bytes=len(b),sha256=hashlib.sha256(b).hexdigest()))
 packets={'TX':[],'RX':[]};requests={};responses=set();stale=[];current_epoch=0;cancelled_partial=0;generated=[];leases=set();commits=[]
 for line in (d/'storage_bus.log').read_text().splitlines():
  v=line.split();epoch=bisect.bisect_right(reset,int(v[1]))
  if epoch!=current_epoch:cancelled_partial+=sum(bool(x) for x in packets.values());packets={'TX':[],'RX':[]};leases=set();current_epoch=epoch
  if v[0]=='CANCEL':cancelled_partial+=sum(bool(x) for x in packets.values());packets={'TX':[],'RX':[]};continue
  stream,t,b,last=v;packets[stream].append(int(b,16))
  if last!='1':continue
  b=bytes(packets[stream]);packets[stream]=[]
  if stream=='TX':
   wide=bool(b[0]&128);head=13 if wide else 11;op=b[0]&127;obj=b[1];off=int.from_bytes(b[2:6] if wide else b[2:4],'big');n=int.from_bytes(b[6:8] if wide else b[4:6],'big');tag=int.from_bytes(b[head-4:head],'big');fin=b[head-5]
   assert tag not in requests and wide==(obj>=5) and len(b)==head+(n if op==2 else 0)
   cap=65536 if obj==6 else 37 if obj==5 else 4096 if obj==0 else 512;assert off+n<=cap
   assert tag>>16!=0
   requests[tag]=dict(epoch=epoch,tag=tag,op=op,object=obj,offset=off,length=n,final=fin,time_ps=int(t))
   if obj in [5,6]:
    if op==6:assert obj not in leases;leases.add(obj)
    elif op==7:assert obj in leases;leases.remove(obj)
    elif op==3:assert obj in leases and n>0 and off<cap
   if op==2 and obj in [2,10]:generated.append(dict(epoch=epoch,object=obj,raw=b[head:].hex(),time_ps=int(t)))
  else:
   assert len(b)>=5;tag=int.from_bytes(b[:4],'big');assert tag in requests
   x=requests[tag]
   if x['epoch']!=epoch:stale.append(dict(tag=tag,old_epoch=x['epoch'],arrival_epoch=epoch,time_ps=int(t)));continue
   assert tag not in responses;responses.add(tag)
   x['status']=b[4];x['response_ps']=int(t)
   if b[4]==0:
    expected=x['length'] if x['op']==3 else (5 if x['object']>=5 else 3) if x['op']==4 else 0;assert len(b)==5+expected
    if x['object']==0 and x['op']==2 and x['final']:assert x['length']==0;commits.append(x)
 unmatched=[x for tag,x in requests.items() if tag not in responses];assert all(x['epoch']<current_epoch for x in unmatched),unmatched
 assert not leases and not any(packets.values())
 for s in status:
  assert any(g['epoch']==s['epoch'] and g['raw']==s['raw'] and g['object']==(10 if s['kind']=='LNS' else 2) and g['time_ps']<s['wire_ns']*1000 for g in generated)
 # A generated counter may be absent on wire only with the specific cancelled
 # snapshot recorded by the public cancellation trace. Never waive arbitrary gaps.
 decoded_generated=[];missing=[]
 for g in generated:
  kind='LNS' if g['object']==10 else 'LUS';x=download_parse(bytes.fromhex(g['raw']),'LNS') if kind=='LNS' else parse_status(bytes.fromhex(g['raw']))
  r=dict(g,kind=kind,decoded=x);decoded_generated.append(r)
  if not any(s['epoch']==g['epoch'] and s['kind']==kind and s['raw']==g['raw'] for s in status):
   if kind=='LUS':
    rejected=[(c,e) for key,c in contexts.items() if key[0]==g['epoch'] and c['name'].endswith('.LUS') and not c['blocks'] and c['WRQ_ns']*1000>=g['time_ps'] for e in peer_errors if e['net']==c['network'] and e['destination']==c['TID'] and e['source']==41000 and e['code']==2 and e['end_ns']>c['WRQ_ns']]
    assert len(rejected)==1,('untransmitted_LUS_must_have_specific_WRQ_refusal',r)
    r['disposition']='generated snapshot, active WRQ refused by actual peer ERROR2, no DATA sent';r['refusing_ERROR']=rejected[0][1]
   else:r['disposition']='specific local cancellation, matched below to exact counter'
   missing.append(r)
 cancelled={(bisect.bisect_right(reset,int(t)*1000),int(counter)) for counter,t in re.findall(r'CANCELLED_LNS snapshot=(\d+) next=\d+ time_ns=(\d+)',events)}
 assert {(g['epoch'],g['decoded']['counter']) for g in missing if g['kind']=='LNS'}==cancelled
 for epoch in range(current_epoch+1):
  cs=[g['decoded']['counter'] for g in decoded_generated if g['kind']=='LNS' and g['epoch']==epoch]
  assert cs==list(range(1,len(cs)+1)),('generated_LNS_counter_sequence',epoch,cs)
 public=re.findall(r'PUBLIC_COUNTS submit=(\d+) client=(\d+) line=(\d+) physical_epoch=(\d+) last_context=([0-9a-f]+) last_tick=(\d+) time_ns=(\d+)',events)
 assert len(public)==1 and len(set(public[0][:4]))==1,'Public command/client/line/physical accounting must agree at quiescence'
 completed=[s for s in status if s['kind']=='LUS' and s['decoded']['status']==3]
 assert len(completed)==len(commits)==len(uploaded)
 for commit,s in zip(commits,completed):assert commit['response_ps']<s['wire_ns']*1000
 for f in downloaded:
  ss=[s for s in status if s['kind']=='LNS' and s['network']==f['network'] and s['decoded']['status']==3 and s['decoded']['files'][0]['name']==f['name'] and s['wire_ns']>f['data_final_ACK_ns']]
  assert ss and ss[0]['acknowledged'],'Successful data ACK and final LNS ACK are separate requirements'
  obj=6 if f['name']=='BIG64.BIN' else 5
  unlocks=[x for x in requests.values() if x['object']==obj and x['op']==7 and x['time_ps']>f['data_final_ACK_ns']*1000]
  assert unlocks and unlocks[0]['time_ps']>=ss[0]['ACK_end_ns']*1000,'Lease released before final LNS matching ACK'
  f.update(final_LNS_ACK_ns=ss[0]['ACK_end_ns'],UNLOCK_request_ps=unlocks[0]['time_ps'])
 if group in [0,1]:assert uploaded and downloaded and any(s['kind']=='LUS' and s['decoded']['status']==0x1003 for s in status)
 if group in [0,2]:assert unfinished and any(s['kind']=='LNS' and s['decoded']['status']==0x1003 for s in status)
 if group in [0,3]:assert any(x['object']==6 and x['op']==3 and x['offset']==65535 for x in requests.values())
 if group in [0,4]:assert len(stale)==1 and len(unmatched)==1 and uploaded
 out=dict(accepted=True,group=group,TX=len(frames),RX=len((d/'injections.log').read_text().splitlines()),uploaded_files=uploaded,downloaded_files=downloaded,unconfirmed_downloads=unfinished,validity_commits=commits,control_statuses=status,generated_control_snapshots=decoded_generated,untransmitted_snapshots=missing,public_transmit_accounting=public,storage_requests=len(requests),storage_completions=len(responses),reset_cancelled_requests=unmatched,stale_after_reset=stale,cancelled_partial_packets=cancelled_partial,remaining_leases=[])
 (d/'independent-audit.json').write_text(json.dumps(out,indent=2),encoding='utf8');return out
