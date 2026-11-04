"""Independent application/GMII/management/storage C38 accounting."""
import sys,json,re,csv,copy,shutil,hashlib,collections,bisect
from pathlib import Path
sys.dont_write_bytecode=True
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'models'))
from prepare_C38 import ROOT,REPORT,save,read,ref,protect
from check_C36 import frame
from check_C37 import check as loading_check
from snmp_crosscheck import parse as pyasn1_parse
from snmp_ref import decode as local_parse,BASE

def fields(line):return dict(re.findall(r'(\w+)=([^\s]+)',line))
def json_safe(value):
 if isinstance(value,bytes):return value.hex()
 if isinstance(value,dict):return {k:json_safe(v) for k,v in value.items()}
 if isinstance(value,(tuple,list)):return [json_safe(v) for v in value]
 return value
def app_check(events,gold,require_progress=True):
 records=collections.defaultdict(dict);byte_rows=collections.defaultdict(list);deliveries=[]
 for line in events.splitlines():
  if not line.strip():continue
  label=line.split()[0];v=fields(line)
  if 'id' not in v:continue
  i=int(v['id']);g=gold[i]
  if label=='BYTE':byte_rows[i].append((int(v['offset']),int(v['data'],16)))
  elif label=='DELIVER':
   assert 'DELIVER' not in records[i],('duplicate_delivery',i)
   assert int(v['bytes'])==g['length'];records[i][label]=v;deliveries.append((int(v['time_ns']),i,int(v['network'])))
  elif label in ('INPUT','ACCEPT','COMMIT','VISIBLE','CONSUME','DESC'):
   assert label not in records[i],('repeated_event',i,label);records[i][label]=v
 offered=[i for i,r in records.items() if 'INPUT' in r]
 assert offered
 for i,r in records.items():
  if i<64:
   assert all(n in r for n in ('INPUT','ACCEPT','COMMIT','DESC','VISIBLE','CONSUME','DELIVER')),('missing_frame_event',i,sorted(r))
   times=[int(r[n]['time_ns']) for n in ('INPUT','ACCEPT','COMMIT','VISIBLE','CONSUME','DELIVER')]
   assert times==sorted(times),('event_order',i,times)
   if require_progress:assert times[3]-times[0]<=5000000,('bounded_application_latency',i,times)
  if 'DELIVER' in r:
   seq=byte_rows[i];assert [a for a,b in seq]==list(range(gold[i]['length'])),('missing_or_duplicate_byte',i)
   data=bytes(b for a,b in seq);assert data.hex()==gold[i]['payload_hex'],('payload_mismatch',i)
 assert len([x for x in deliveries if x[1]<64])==len(offered)
 return records,deliveries

def isolated_checker_selftest():
 gold=[dict(id=0,length=2,payload_hex='00ff')]
 text='\n'.join(['INPUT id=0 vl=1 length=2 time_ns=0','ACCEPT id=0 time_ns=5','COMMIT id=0 time_ns=10','DESC id=0 network=1 time_ns=15','VISIBLE id=0 time_ns=20','CONSUME id=0 time_ns=20','BYTE id=0 offset=0 data=00 time_ns=20','BYTE id=0 offset=1 data=ff time_ns=30','DELIVER id=0 network=1 bytes=2 time_ns=30'])
 app_check(text,gold);bad=[('missing_byte',text.replace('BYTE id=0 offset=1 data=ff time_ns=30','')),('duplicate_delivery',text+'\nDELIVER id=0 network=1 bytes=2 time_ns=40'),('missing_completion',text.replace('DELIVER id=0 network=1 bytes=2 time_ns=30','')),('late_output',text.replace('VISIBLE id=0 time_ns=20','VISIBLE id=0 time_ns=6000020').replace('CONSUME id=0 time_ns=20','CONSUME id=0 time_ns=6000020').replace('DELIVER id=0 network=1 bytes=2 time_ns=30','DELIVER id=0 network=1 bytes=2 time_ns=6000030'))]
 rejected=[]
 for name,data in bad:
  try:app_check(data,gold)
  except AssertionError:rejected.append(name)
  else:raise AssertionError('A fabricated bad offline sample passed: '+name)
 save(REPORT/'checker-selftest.json',dict(accepted=True,kind='offline_checker_test_only',actual_simulator_exit=None,not_an_RTL_fault80=True,positive_cases=1,rejected=rejected,checker=ref(__file__)))
 return rejected

def wave_stalls(path):
 identifiers={};scope=[];values={};time=0;last=0;data_ns=0;desc_ns=0;prior=None
 with Path(path).open() as stream:
  for raw in stream:
   p=raw.split()
   if not p:continue
   if p[0]=='$scope':scope.append(p[2])
   elif p[0]=='$upscope':scope.pop()
   elif p[0]=='$var':
    name=p[4]
    if len(scope)==1 and name in ('app_rx_valid','app_rx_ready','app_rx_desc_valid','app_rx_desc_ready'):identifiers[p[3]]=name
   elif p[0]=='$enddefinitions':break
  for raw in stream:
   raw=raw.strip()
   if not raw:continue
   if raw[0]=='#':
    now=int(raw[1:]);duration=now-time
    if values.get('app_rx_valid')=='1' and values.get('app_rx_ready')=='0':data_ns+=duration
    if values.get('app_rx_desc_valid')=='1' and values.get('app_rx_desc_ready')=='0':desc_ns+=duration
    time=now
   elif raw[0] in '01xz' and raw[1:] in identifiers:values[identifiers[raw[1:]]]=raw[0]
 return dict(data_backpressure_ps=data_ns,descriptor_backpressure_ps=desc_ns)

def check(folder,stage):
 d=Path(folder);native=read(d/'result.json');process=read(d/'process.json');assert native['accepted'] and native['exit']==0 and not native['tool_errors']
 assert process['complete'] and process['exit']==0 and not process['wall_timeout']
 for x in native['sources']:assert ref(x['path'])['sha256']==x['sha256']==ref(x['snapshot'])['sha256'],x['path']
 manifest=read(d/'inputs/vectors/system/c38/manifest.json');gold=manifest['frames'];records,deliveries=app_check((d/'app-events.log').read_text(),gold)
 counts=collections.Counter(i for t,i,n in deliveries);normal_ids=sorted(i for i,r in records.items() if 'INPUT' in r)
 frames=[];rx=[];last={};physical=collections.Counter();snmp=[];traps=[];ntp=[];filtered_tx=[];filtered_rx=[]
 for direction,name in (('TX','wire.log'),('RX','injections.log')):
  for line in (d/name).read_text().splitlines():
   net,start,end,h=line.split();net,start,end=int(net),int(start),int(end);sp,dp,p=frame(h);raw=bytes.fromhex(h)
   row=dict(network=net,start_ns=start,end_ns=end if direction=='TX' else start+end*8,source=sp,destination=dp,payload=p.hex(),wire=h)
   if raw[8]==3:
    vl=int.from_bytes(raw[12:14],'big');sn=raw[-5];matches=[g for g in gold if g['vl']==vl and g['sn']==sn];assert len(matches)==1
    g=matches[0];assert h==g['wire_A' if net==0 else 'wire_B'];row.update(id=g['id'],vl=vl,sn=sn)
    if direction=='TX':
     assert g['id'] in normal_ids;physical[(g['id'],net)]+=1;key=(vl,net)
     if key in last:assert start-last[key]>=(1000000 if vl==1 else 2000000),('BAG',key,start,last[key])
     last[key]=start
   elif sp==161 and direction=='TX':
    decoded=pyasn1_parse(p);assert decoded==local_parse(p);row['decoded']=decoded
    if dp==162:
     assert net==0 and decoded['pdu']==0xa4 and decoded['generic']==6 and decoded['specific']==1
     assert bytes(raw[8:14])==bytes.fromhex('020000001002') and raw[38:42]==bytes([192,0,2,1]);traps.append(row)
    else:
     assert net==1 and decoded['pdu']==0xa2 and decoded['error_status']==0 and decoded['error_index']==0
     assert len(decoded['varbinds'])==1 and tuple(decoded['varbinds'][0]['oid'])==BASE+(3,0) and decoded['varbinds'][0]['tag']==0x41
     qid=decoded['request_id']-3800;assert 0<=qid<32 and dp==46000+qid
     row['request_index']=qid;snmp.append(row)
   elif sp==45000 or dp==45000:
    assert len(p)==48 and net==0
    if direction=='TX':assert sp==45000 and dp==123 and p[0]==0x23
    else:assert sp==123 and dp==45000 and p[0]==0x24
    ntp.append(dict(row,direction=direction))
   elif sp==161 or dp==161:
    assert direction=='RX' and net==1 and dp==161;row['request_index']=local_parse(p)['request_id']-3800
   else:
    (filtered_tx if direction=='TX' else filtered_rx).append(line)
   (frames if direction=='TX' else rx).append(row)
 for i in normal_ids:
  assert physical[(i,0)]==physical[(i,1)]==1,('physical_copy_count',i)
 # MIB application counter is sourced from actual whole-frame application
 # consumption. Independent event brackets account for concurrent snapshots.
 delivery_times=sorted(t for t,i,n in deliveries)
 for row in snmp:
  req=next(x for x in rx if x.get('request_index')==row['request_index'] and x['destination']==161)
  lower=bisect.bisect_left(delivery_times,req['start_ns']);upper=bisect.bisect_right(delivery_times,row['end_ns'])
  value=row['decoded']['varbinds'][0]['value'];assert lower<=value<=upper,('real_counter_event_bracket',value,lower,upper)
  row.update(event_lower=lower,event_upper=upper,response_ns=row['end_ns']-req['start_ns'])
 # Retain the same independent C37 loading grammar, byte/readback, final ACK,
 # tagged storage and lease checks on a precisely filtered public-link view.
 view=d/'loading-audit-view';view.mkdir(exist_ok=True)
 (view/'wire.log').write_text('\n'.join(filtered_tx)+'\n' if filtered_tx else '',encoding='utf8');(view/'injections.log').write_text('\n'.join(filtered_rx)+'\n' if filtered_rx else '',encoding='utf8')
 for name in ('events.log','readback.log','storage_bus.log'):shutil.copy2(d/name,view/name)
 for name in ('vectors/615a/c35/data0.bin','vectors/615a/c35/header0.bin','vectors/615a/c36/data_small.bin','vectors/615a/c36/data_big.bin'):
  src=d/'inputs'/name;dst=view/'inputs'/name;dst.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(src,dst)
 loading=loading_check(view,99)
 event_text=(d/'events.log').read_text();stats={int(i):int(v) for i,v in re.findall(r'STATS index=(\d+) value=(\d+)',event_text)}
 assert len(stats)==32
 assert stats[0]==len(normal_ids) and stats[24]==len(deliveries) and stats[25]==sum(gold[i]['length'] for t,i,n in deliveries)
 assert stats[14]==stats[15] and stats[16]==stats[17] and stats[18]==0
 assert stats[28]&65535==stats[29]&65535==0 and all(stats[i]==0 for i in (9,10,11,12))
 metrics=[]
 for i in normal_ids:
  r=records[i];g=gold[i];v=dict(id=i,VLID=g['vl'],payload_bytes=g['length'],SN=g['sn'])
  for label,key in [('INPUT','input_first_valid_ns'),('ACCEPT','input_first_accept_ns'),('COMMIT','input_commit_ns'),('VISIBLE','output_first_visible_ns'),('CONSUME','output_first_consume_ns'),('DELIVER','output_complete_ns')]:v[key]=int(r[label]['time_ns'])
  v['application_latency_ns']=v['output_first_visible_ns']-v['input_first_valid_ns'];metrics.append(v)
 with (d/'frames.csv').open('w',newline='',encoding='utf8') as f:
  w=csv.DictWriter(f,fieldnames=list(metrics[0]));w.writeheader();w.writerows(metrics)
 backpressure=wave_stalls(d/'key-interfaces.vcd');assert backpressure['data_backpressure_ps']>0 and backpressure['descriptor_backpressure_ps']>0
 rtc=[];overlap=[];fault=None
 if stage=='concurrent':
  assert len(loading['uploaded_files'])==len(loading['downloaded_files'])==1
  assert loading['uploaded_files'][0]['bytes']==loading['downloaded_files'][0]['bytes']==37
  begin=int(re.search(r'A_LINK_DOWN time_ns=(\d+)',event_text)[1]);end=int(re.search(r'A_LINK_UP time_ns=(\d+)',event_text)[1]);assert end-begin==6000000
  assert not any(x['network']==0 and begin<=x['start_ns']<end for x in rx),'A fault must discard outside the DUT'
  healthy=[(t,i,n) for t,i,n in deliveries if i<64 and begin<=t<end]
  assert len(healthy)>=2 and {gold[i]['vl'] for t,i,n in healthy}=={1,0x8001} and all(n==1 for t,i,n in healthy)
  assert any(begin<=r['start_ns']<end for r in snmp),'B management must progress while A is absent'
  assert any(x['network']==1 and begin<=x['start_ns']<end and x['source']!=161 and bytes.fromhex(x['wire'])[8]!=3 for x in frames),'B loading must physically progress'
  late=int(re.search(r'LATE_RECENT_COPY id=(\d+)',event_text)[1]);assert counts[late]==1 and any(t>end and i>late for t,i,n in deliveries)
  assert stats[7]>=1 and len(traps)>=1 and any(t['start_ns']<begin for t in traps)
  assert len(snmp)>=2 and max(x['decoded']['varbinds'][0]['value'] for x in snmp)>min(x['decoded']['varbinds'][0]['value'] for x in snmp)
  rtc_text=(d/'rtc-events.log').read_text();tick_origin=int(re.search(r'RTC_TICK_ORIGIN time_ns=(\d+)',rtc_text)[1]);requests=[fields(l) for l in rtc_text.splitlines() if l.startswith('REQUEST ')];samples=[fields(l) for l in rtc_text.splitlines() if l.startswith('SAMPLE ')]
  assert len(requests)==len(samples)==4
  last_candidate=-1;last_decision=-1
  for s in samples:
   ws=[int(s['w'+str(i)],16) for i in range(32)];status=ws[1]&15;before=int(s['correction_before']);after=int(s['correction_after'])
   stamps=[ws[2+i*2]|ws[3+i*2]<<32 for i in range(4)]
   if status==1:
    signed=lambda n:n-(1<<65) if n&(1<<64) else n
    theta=signed(ws[10]|ws[11]<<32|(ws[12]&1)<<64);delta=signed(ws[13]|ws[14]<<32|(ws[15]&1)<<64)
    assert theta==((stamps[1]-stamps[0])+(stamps[2]-stamps[3]))//2 and delta==(stamps[3]-stamps[0])-(stamps[2]-stamps[1])
    assert after==before+1 and (int(s['flags'])&7)==2
    request=next(r for r in requests if int(r['token'],16)==stamps[0]);reply=next(r for r in ntp if r['direction']=='RX' and int.from_bytes(bytes.fromhex(r['payload'])[24:32],'big')==stamps[0])
    assert int.from_bytes(bytes.fromhex(reply['payload'])[32:40],'big')==stamps[1] and int.from_bytes(bytes.fromhex(reply['payload'])[40:48],'big')==stamps[2]
   else:assert status==3 and after==before
   observed=int(s['snapshot_seconds'])*1000000000+int(s['snapshot_ns']);target=int(s['target_seconds'])*1000000000+int(s['target_ns'])
   assert observed==target+(int(s['snapshot_tick'])-int(s['apply_tick'])-1)*10,('actual_RTC_load_and_continued_count',s)
   physical=tick_origin+int(s['snapshot_tick'])*10;truth=1760000000000000000+physical
   candidate=int(s['sched_candidate']);decision=int(s['sched_decision']);meta=int(s['sched_meta'],16);vl=int(s['sched_vl']);sn=(meta>>13)&255;net=(meta>>21)&1
   assert candidate>=last_candidate and decision>=last_decision and decision>=candidate
   actual_rx=[r for r in rx if r.get('vl')==vl and r.get('sn')==sn and r['network']==net]
   assert actual_rx,('public_monotonic_record_frame_binding',vl,sn,net)
   closest=min(actual_rx,key=lambda r:abs(r['end_ns']-(tick_origin+candidate*10)))
   displacement=tick_origin+candidate*10-closest['end_ns'];assert -20000<=displacement<=200000,('scheduler_stamp_vs_real_RX_boundary',displacement)
   assert decision*10+tick_origin<=int(s['time_ns'])
   last_candidate=candidate;last_decision=decision
   rtc.append(dict(attempt=int(s['attempt']),status=status,corrections_before=before,corrections_after=after,physical_snapshot_ns=physical,RTC_ns=observed,truth_ns=truth,error_ns=observed-truth,scheduler_candidate_tick=candidate,scheduler_decision_tick=decision,matched_RX_VL=vl,matched_RX_SN=sn,matched_RX_network=net,scheduler_candidate_minus_RX_end_ns=displacement,complete_ns=int(s['time_ns'])))
  assert sum(r['status']==1 for r in rtc)>=2 and sum(r['status']==3 for r in rtc)>=1 and rtc[-1]['status']==1 and rtc[-1]['complete_ns']>end
  # A concrete overlap interval needs an application transaction, SNMP
  # request, SNTP request and an actual loading exchange all outstanding.
  load_windows=[]
  for notice in loading['control_statuses']:
   if notice['decoded']['status']!=3 or not notice['acknowledged']:continue
   init_name=b'AFDX_01.LUI' if notice['kind']=='LUS' else b'AFDX_01.LNO'
   candidates=[x for x in rx if x['network']==notice['network'] and bytes.fromhex(x['payload']).startswith(b'\0\1'+init_name+b'\0') and x['start_ns']<notice['wire_ns']]
   assert candidates
   load_windows.append(dict(kind=notice['kind'],start_ns=max(x['start_ns'] for x in candidates),end_ns=notice['ACK_end_ns']))
  assert {w['kind'] for w in load_windows}=={'LUS','LNS'}
  for m in metrics:
   for q in snmp:
    query=next(x for x in rx if x.get('request_index')==q['request_index'] and x['destination']==161)
    for j,r in enumerate(rtc):
     for w in load_windows:
      start=max(m['input_first_accept_ns'],query['start_ns'],int(requests[j]['time_ns']),w['start_ns']);stop=min(m['output_complete_ns'],q['end_ns'],r['complete_ns'],w['end_ns'])
      if start<stop:overlap.append(dict(start_ns=start,end_ns=stop,frame_id=m['id'],query=q['request_index'],RTC_attempt=j,loading_kind=w['kind'],integrity='Actual redundant physical copies and exactly one checked application delivery'))
  assert overlap,'No actual four-service transaction overlap was observed'
  fault=dict(A_down_ns=begin,A_up_ns=end,B_unique_deliveries=len(healthy),B_VLs=sorted({gold[i]['vl'] for t,i,n in healthy}),late_recent_id=late,late_deliveries=counts[late],fault_layer='Whole frame loss in both directions of external A link; clocks and DUT/B never stopped/reset')
  with (d/'rtc_error.csv').open('w',newline='',encoding='utf8') as f:
   w=csv.DictWriter(f,fieldnames=list(rtc[0]));w.writeheader();w.writerows(rtc)
 out=dict(accepted=True,stage=stage,run=str(d),native_exit=0,status=native['status'],input_frames=len(normal_ids),unique_application_frames=len([x for x in deliveries if x[1]<64]),external_resource_test_deliveries=len([x for x in deliveries if x[1]>=64]),payload_bytes=sum(gold[i]['length'] for t,i,n in deliveries if i<64),physical_TX=2*len(normal_ids),all_TX=len(frames),all_RX=len(rx),SNMP_GETs=len(snmp),Traps=len(traps),SNMP_independent_parses=snmp+traps,RTC=rtc,fault=fault,actual_overlap=overlap,storage=loading,stats=stats,backpressure=backpressure,frames_csv=ref(d/'frames.csv'),performance_certified=False)
 save(d/'independent-audit.json',json_safe(out));save(REPORT/('audit-'+stage+'.json'),json_safe(out));print('C38_INDEPENDENT_PASS',stage,'app_frames='+str(len(normal_ids)),'services='+str((len(snmp),len(traps),len(rtc))),flush=True)
 return out
if __name__=='__main__':
 import argparse
 p=argparse.ArgumentParser();p.add_argument('--stage',choices=('interface','concurrent'),required=True);a=p.parse_args();isolated_checker_selftest();r=read(REPORT/('latest-'+a.stage+'.json'));check(r['directory'],a.stage)
