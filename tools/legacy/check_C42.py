"""Independent public application, raw GMII, RTC and storage audit for C42."""
import bisect,collections,csv,json,re,shutil,sys,zlib
from pathlib import Path
sys.dont_write_bytecode=True
from prepare_C42 import ROOT,REPORT,save,read,ref,digest
sys.path.insert(0,str(ROOT/'models'))
from check_C38 import app_check,fields,json_safe,wave_stalls
from check_C36 import frame
from check_C37 import check as loading_check
from snmp_crosscheck import parse as asn1_parse
from snmp_ref import BASE
from c42_approved_evidence import approved_EQ_evidence
def check(kind,diagnostic_tool_exit=False):
 approved=approved_EQ_evidence() if kind=='netlist-normal' and not diagnostic_tool_exit else None
 result=approved['result'] if approved else read(REPORT/('latest-'+kind+'.json'));assert result['exit']==0
 if diagnostic_tool_exit:
  # Diagnose completed business evidence without converting a tool-affected
  # run into PASS. Formal calls below still require the original clean gate.
  assert kind=='netlist-normal' and not result['accepted']
  assert result['status']['done']==1 and result['status']['failures']==result['status']['timeout_seen']==0
  assert result['tool_errors'] and result['first_mismatch'] is None
 elif not approved:assert result['accepted']
 run=Path(result['directory']);d=approved['directory'] if approved else Path(result.get('output_directory',run));p=read(run/'process.json');assert p['complete'] and p['exit']==0 and not p['wall_timeout']
 launch=read(run/'launch.json')
 for r in launch['sources']:assert digest(r['path'])==r['sha256']==digest(r['snapshot'])
 manifest=read(d/'inputs/vectors/system/c42/manifest.json');gold={g['id']:g for g in manifest['frames']}
 records,delivered=app_check((d/'app-events.log').read_text(),gold)
 normal=sorted(i for i,r in records.items() if 'INPUT' in r);assert normal==[0,1,2,3,4,5]
 for i in normal:assert int(records[i]['DESC']['version'])==(1 if i<2 else 2),('RX_SOP_configuration_snapshot',i,records[i]['DESC'])
 assert {i for t,i,n in delivered if i>=64}==set(range(64,72)),'Eight pool slots delivered and two resource drops required'
 for i in (0,2,3):assert next(n for t,j,n in delivered if i==j)==1,('B must win when A is invalid or externally lost',i)
 physical=collections.Counter();last={};rows=[];rx=[];queries=[];traps=[];ntp=[];filtered={'TX':[],'RX':[]};damaged=[]
 for direction,name in [('TX','wire.log'),('RX','injections.log')]:
  for line in (d/name).read_text().splitlines():
   net,start,third,h=line.split();net,start,third=int(net),int(start),int(third);raw=bytes.fromhex(h);end=third if direction=='TX' else start+8*third
   if raw[8]==3:
    vl=int.from_bytes(raw[12:14],'big');sn=raw[-5];match=[g for g in gold.values() if g['vl']==vl and g['sn']==sn];assert len(match)==1
    g=match[0];expected=bytes.fromhex(g['wire_A' if net==0 else 'wire_B'])
    row=dict(direction=direction,network=net,id=g['id'],VLID=vl,SN=sn,start_ns=start,end_ns=end)
    if direction=='RX' and net==0 and g['id'] in [0,2]:
     expected=bytearray(expected)
     if g['id']==0:expected[-1]^=1
     else:expected[32]^=1;expected[-4:]=zlib.crc32(expected[8:-4]).to_bytes(4,'little')
     assert raw==expected,'Corruption is fixed in the external link, not a DUT bypass'
     if g['id']==0:assert zlib.crc32(raw[8:-4])!=int.from_bytes(raw[-4:],'little')
     else:
      assert zlib.crc32(raw[8:-4])==int.from_bytes(raw[-4:],'little')
      words=[int.from_bytes(raw[j:j+2],'big') for j in range(22,42,2)];s=sum(words);s=(s&65535)+(s>>16);s=(s&65535)+(s>>16);assert s!=65535
     damaged.append(row)
    else:assert raw==expected;frame(h)
    if direction=='TX':
     physical[(g['id'],net)]+=1;key=(vl,net)
     if key in last:assert start-last[key]>=(1000000 if vl==1 else 2000000),('BAG early',row,last[key])
     last[key]=start
    (rows if direction=='TX' else rx).append(row);continue
   sp,dp,payload=frame(h);row=dict(direction=direction,network=net,start_ns=start,end_ns=end,source=sp,destination=dp,payload=payload.hex())
   if sp==161 and direction=='TX':
    decoded=asn1_parse(payload);row['decoded']=decoded
    if dp==162:
     assert decoded['pdu']==0xa4 and decoded['generic']==6 and decoded['specific']==1;traps.append(row)
    else:
     assert net==1 and dp==46000 and decoded['request_id']==3800 and decoded['pdu']==0xa2
     assert decoded['error_status']==decoded['error_index']==0 and len(decoded['varbinds'])==1
     v=decoded['varbinds'][0];assert tuple(v['oid'])==BASE+(3,0) and v['tag']==0x41;queries.append(row)
   elif sp==45000 or dp==45000:
    assert net==0 and len(payload)==48;ntp.append(row)
   elif dp==161 and direction=='RX':
    assert net==1;row['decoded']=asn1_parse(payload)
   else:filtered[direction].append(line)
   (rows if direction=='TX' else rx).append(row)
 assert len(damaged)==2
 assert len(queries)==len(traps)==1 and len(ntp)==2
 for i in normal:assert physical[i,0]==physical[i,1]==1
 request=next(r for r in rx if r.get('destination')==161)
 times=sorted(t for t,i,n in delivered);lo=bisect.bisect_left(times,request['end_ns']);hi=bisect.bisect_right(times,queries[0]['start_ns']);counter=queries[0]['decoded']['varbinds'][0]['value'];assert lo<=counter<=hi
 queries[0]['independent_event_counter_range']=[lo,hi]
 view=d/'loading-audit-view';view.mkdir(exist_ok=True)
 for direction,name in [('TX','wire.log'),('RX','injections.log')]: (view/name).write_text('\n'.join(filtered[direction])+'\n')
 for name in ('events.log','storage_bus.log','readback.log'):shutil.copy2(d/name,view/name)
 for name in ('vectors/615a/c35/data0.bin','vectors/615a/c35/header0.bin','vectors/615a/c36/data_small.bin','vectors/615a/c36/data_big.bin'):
  dst=view/'inputs'/name;dst.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(d/'inputs'/name,dst)
 loading=loading_check(view,99);assert len(loading['uploaded_files'])==len(loading['downloaded_files'])==1
 assert loading['uploaded_files'][0]['bytes']==loading['downloaded_files'][0]['bytes']==37
 events=(d/'events.log').read_text();stats={int(i):int(v) for i,v in re.findall(r'STATS index=(\d+) value=(\d+)',events)}
 assert len(stats)==32 and stats[0]==6 and stats[24]==14 and stats[7]==2
 assert stats[14]==stats[15]==6 and stats[16]==stats[17] and stats[18]==0
 assert stats[28]&65535==stats[29]&65535==0
 assert stats[9]==1 and stats[11]==stats[12]==0
 # Pre-APPLY committed frame2 retains its old 1471-byte TX snapshot. The new
 # active limit559 is independently read over the real public configuration bus.
 update=int(re.search(r'UPDATE_REQUEST time_ns=(\d+)',events)[1]);apply=[int(t) for t in re.findall(r'PUBLIC_APPLY time_ns=(\d+)',events)]
 assert len(apply)==2 and update<apply[1]
 old=[r for r in rows if r.get('id')==2];assert len(old)==2 and all(r['end_ns']<=apply[1]+10 for r in old)
 assert re.search(r'BUS write=0 kind=0 bank=0 shadow=0 index=0 word=6 input=00000000 error=0 output=022f1001',events)
 state={k:int(v,16) for k,v in re.findall(r'PUBLIC_STATE (\w+)=([0-9a-f]+)',events)}
 assert (state['TX127_word4']>>16)==0x8001
 assert (state['RX4095_word4']>>18)&255==1 and (state['RX2048_word4']>>18)&255==10
 rtc_text=(d/'rtc-events.log').read_text();samples=[fields(l) for l in rtc_text.splitlines() if l.startswith('SAMPLE ')];assert len(samples)==1
 x=samples[0];w=[int(x['w'+str(i)],16) for i in range(32)];assert w[1]&15==1
 stamps=[w[2+i*2]|w[3+i*2]<<32 for i in range(4)];signed=lambda n:n-(1<<65) if n&(1<<64) else n
 theta=signed(w[10]|w[11]<<32|(w[12]&1)<<64);delta=signed(w[13]|w[14]<<32|(w[15]&1)<<64)
 assert theta==((stamps[1]-stamps[0])+(stamps[2]-stamps[3]))//2 and delta==(stamps[3]-stamps[0])-(stamps[2]-stamps[1])
 assert int(x['correction_after'])==int(x['correction_before'])+1 and int(x['flags'])&7==2
 tx=next(r for r in ntp if r['direction']=='TX');rsp=next(r for r in ntp if r['direction']=='RX');a=bytes.fromhex(tx['payload']);b=bytes.fromhex(rsp['payload'])
 assert int.from_bytes(a[40:48],'big')==int.from_bytes(b[24:32],'big')==stamps[0]
 assert [int.from_bytes(b[j:j+8],'big') for j in (32,40)]==stamps[1:3]
 observed=int(x['snapshot_seconds'])*1000000000+int(x['snapshot_ns']);target=int(x['target_seconds'])*1000000000+int(x['target_ns'])
 assert observed==target+(int(x['snapshot_tick'])-int(x['apply_tick'])-1)*10
 origin=int(re.search(r'RTC_TICK_ORIGIN time_ns=(\d+)',rtc_text)[1]);truth=1760000000000000000+origin+int(x['snapshot_tick'])*10
 rtc=dict(timestamps_Q32=stamps,theta_Q32=theta,delta_Q32=delta,RTC_ns=observed,truth_ns=truth,error_ns=observed-truth,correction_count=int(x['correction_after']),not_a_1ms_accuracy_claim=True)
 post=fields(next(l for l in rtc_text.splitlines() if l.startswith('POST_TIME_FRAME ')))
 assert int(post['candidate'])>=int(x['sched_candidate']) and int(post['decision'])>=int(post['candidate'])
 after_time_frame=next(t for t,i,n in delivered if i==5);assert after_time_frame>int(x['time_ns'])
 assert int(post['decision'])*10+origin<=int(post['time_ns'])
 rtc['post_correction_actual_business']=post
 csvrows=[]
 for i in normal:
  r=records[i];g=gold[i];v=dict(id=i,VLID=g['vl'],payload_length=g['length'])
  for label,key in [('INPUT','first_input_ns'),('ACCEPT','first_accept_ns'),('COMMIT','commit_ns'),('VISIBLE','first_output_ns'),('CONSUME','first_consume_ns'),('DELIVER','complete_ns')]:v[key]=int(r[label]['time_ns'])
  csvrows.append(v)
 with (d/'frames.csv').open('w',newline='') as f:c=csv.DictWriter(f,fieldnames=list(csvrows[0]));c.writeheader();c.writerows(csvrows)
 out=dict(accepted=not diagnostic_tool_exit,functional_checks_passed=True,diagnostic_tool_exit=diagnostic_tool_exit,source_result=ref(run/'result.json'),kind=kind,run=str(d),checker=ref(__file__),native_process=ref(run/'process.json'),input_frames=6,unique_app_frames=6,resource_probe_delivered=8,resource_probe_dropped=2,TX=len(rows),RX=len(rx),counter=counter,GET=queries,Trap=traps,RTC=rtc,storage=loading,stats=stats,states=state,APPLY_ns=apply,damaged_RX=damaged,frames=ref(d/'frames.csv'),shared_init_count=1,physical_timing_passed=False)
 if approved:out['execution_disposition']=dict(user_authorized_review=approved['review'],original_raw_accepted=False,raw_native_exit=0,raw_tool_errors=result['tool_errors'],clean_full_repeat_completed=False,original_raw_result_unchanged=True)
 if kind!='rtl':
  stalls=wave_stalls(run/'key-interfaces.vcd');assert stalls['data_backpressure_ps']>0 and stalls['descriptor_backpressure_ps']>0
  out['backpressure']=stalls;out['waveform']=ref(run/'key-interfaces.vcd')
 prior=d/('tool-exit-diagnostic-audit.json' if diagnostic_tool_exit else 'independent-audit.json')
 if prior.exists():
  q=d/'audit-history'/('independent-'+digest(prior)+'.json');q.parent.mkdir(exist_ok=True)
  if not q.exists():shutil.copy2(prior,q)
 save(prior,json_safe(out));save(REPORT/('netlist-tool-exit-diagnostic-audit.json' if diagnostic_tool_exit else 'rtl-independent-audit.json' if kind=='rtl' else 'netlist-independent-audit.json'),json_safe(out));print('C42_DIAGNOSTIC_FUNCTIONS_OK_NOT_ACCEPTED' if diagnostic_tool_exit else 'C42_INDEPENDENT_PASS',kind,'TX',len(rows),'RX',len(rx),'stored37B',loading['uploaded_files'][0]['sha256']);return out
if __name__=='__main__':check(sys.argv[1] if len(sys.argv)>1 else 'rtl','--diagnostic-tool-exit' in sys.argv)
