"""Independent GMII reconstruction, A4 grammar, storage/tag/lease audit."""
import sys,json,hashlib,zlib,struct,re
from pathlib import Path
sys.dont_write_bytecode=True
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'models'))
from download615a_ref import parse

def checksum(b):
 if len(b)%2:b+=b'\0'
 s=sum(struct.unpack('>'+str(len(b)//2)+'H',b))
 while s>>16:s=(s&65535)+(s>>16)
 return (~s)&65535

def frame(h):
 b=bytes.fromhex(h);assert b[:8]==b'\x55'*7+b'\xd5';assert zlib.crc32(b[8:-4])==int.from_bytes(b[-4:],'little')
 ip=b[22:42];assert len(ip)==20 and ip[0]==0x45 and checksum(ip)==0
 total=int.from_bytes(ip[2:4],'big');u=b[42:22+total];assert len(u)>=8 and int.from_bytes(u[4:6],'big')==len(u)
 assert checksum(ip[12:20]+b'\0\x11'+u[4:6]+u)==0
 return int.from_bytes(u[:2],'big'),int.from_bytes(u[2:4],'big'),u[8:]

def check(folder,smoke=False):
 d=Path(folder);contexts={};transfers=[];all_frames=[];acks=[]
 for line in (d/'injections.log').read_text().splitlines():
  net,t,n,h=line.split();sp,dp,p=frame(h)
  if p[:2]==b'\0\4' and len(p)==4:acks.append(dict(net=int(net),source=sp,destination=dp,block=int.from_bytes(p[2:],'big'),start_ns=int(t),end_ns=int(t)+int(n)*8+8))
 for line in (d/'wire.log').read_text().splitlines():
  net,start,end,h=line.split();net,start,end=int(net),int(start),int(end);sp,dp,p=frame(h);op=int.from_bytes(p[:2],'big');all_frames.append(dict(network=net,start_ns=start,end_ns=end,source=sp,destination=dp,op=op))
  if op==2:
   assert dp==59;parts=p[2:].split(b'\0');assert len(parts)==3 and parts[1].lower()==b'octet' and parts[2]==b''
   name=parts[0].decode('ascii');key=(net,sp);assert key not in contexts
   assert (35000<=sp<=39999 and name in ['SMALL.BIN','BIG64.BIN']) or (45001<=sp<=49151 and name in ['AFDX_01.LNL','AFDX_01.LNS'])
   c=dict(network=net,tid=sp,name=name,blocks={},transmissions=[],WRQ_ns=start);contexts[key]=c;transfers.append(c)
  elif op==3 and sp<49152:
   c=contexts[(net,sp)];block=int.from_bytes(p[2:4],'big');payload=p[4:];assert dp==(42010 if sp<40000 else 41000)
   if block in c['blocks']:assert c['blocks'][block]==payload
   else:assert block==len(c['blocks'])+1;c['blocks'][block]=payload
   c['transmissions'].append(dict(block=block,start_ns=start,end_ns=end,bytes=len(payload)))
 accepted=[];statuses=[];lists=[];wire_status_bytes={}
 for c in transfers:
  if not c['blocks']:continue # explicitly cancelled before ACK0/data
  data=b''.join(c['blocks'].values());last=max(c['blocks']);assert len(c['blocks'][last])<512
  matching=[a for a in acks if a['net']==c['network'] and a['destination']==c['tid'] and a['block']==last and a['source']==(42010 if c['tid']<40000 else 41000)]
  assert matching,'No actual matching final ACK'
  c['final_ACK_ns']=matching[-1]['end_ns'];c['bytes']=len(data);c['sha256']=hashlib.sha256(data).hexdigest()
  if c['name']=='AFDX_01.LNL':
   x=parse(data,'LNL');assert x['files']==[('SMALL.BIN',''),('BIG64.BIN','')];lists.append(x)
  elif c['name']=='AFDX_01.LNS':
   x=parse(data,'LNS');assert x['status'] in [1,2,3,0x1003] and x['exception']==0 and x['estimated']==0
   assert x['ratio']==(100 if x['status']==3 else 0)
   assert all(f['status']==x['status'] and f['description']=='' and f['name'] in ['SMALL.BIN','BIG64.BIN'] for f in x['files'])
   if x['status']==3:
    assert len(x['files'])==1
    prior=[f for f in accepted if f['network']==c['network'] and f['name']==x['files'][0]['name'] and f['final_ACK_ns']<c['WRQ_ns']]
    assert prior,'Completed LNS precedes data final ACK'
   statuses.append(x)
   assert x['counter'] not in wire_status_bytes
   wire_status_bytes[x['counter']]=data
  else:
   expected=d/'inputs/vectors/615a/c36'/('data_big.bin' if c['name']=='BIG64.BIN' else 'data_small.bin');assert data==expected.read_bytes()
   assert len(data) in [37,65536]
   if len(data)==65536:
    assert last==129 and c['blocks'][129]==b'' and all(len(c['blocks'][b])==512 for b in range(1,129))
    assert sum(t['block']==65 for t in c['transmissions'])==2 and sum(t['block']==129 for t in c['transmissions'])==2
   accepted.append(c)
 assert len(accepted)==(1 if smoke else 4)
 if not smoke:assert any(x['bytes']==65536 and x['network']==1 for x in accepted) and {x['network'] for x in accepted}=={0,1}
 # Parse the actual byte storage link; no DUT internal-state expectation.
 packets={'TX':[],'RX':[]};requests={};responses=set();leases=set();read_bytes={5:0,6:0};read_ops={5:0,6:0};stored_status={}
 for line in (d/'storage_bus.log').read_text().splitlines():
  v=line.split()
  if v[0]=='CANCEL':packets={'TX':[],'RX':[]};continue
  stream,t,b,last=v;packets[stream].append(int(b,16))
  if not int(last):continue
  b=bytes(packets[stream]);packets[stream]=[]
  if stream=='TX':
   wide=bool(b[0]&128);head=13 if wide else 11;assert len(b)>=head;op=b[0]&127;obj=b[1];off=int.from_bytes(b[2:6] if wide else b[2:4],'big');ln=int.from_bytes(b[6:8] if wide else b[4:6],'big');tag=int.from_bytes(b[head-4:head],'big')
   assert tag not in requests and wide==(obj>=5);assert len(b)==head+(ln if op==2 else 0)
   cap=65536 if obj==6 else 37 if obj==5 else 4096 if obj==0 else 512;assert off+ln<=cap
   if obj in [5,6]:
    assert op in [3,4,6,7]
    if op==6:assert obj not in leases;leases.add(obj)
    elif op==7:assert obj in leases;leases.remove(obj)
    elif op==3:assert obj in leases and 1<=ln<=512 and off<cap;read_bytes[obj]+=ln;read_ops[obj]+=1
   requests[tag]=dict(op=op,object=obj,offset=off,length=ln,request_ps=int(t))
   if obj==10 and op==2:
    raw=b[head:];snap=parse(raw,'LNS');count=snap['counter']
    assert count==len(stored_status)+1,'Exactly one counter per generated immutable snapshot'
    stored_status[count]=raw
  else:
   assert len(b)>=5;tag=int.from_bytes(b[:4],'big');assert tag in requests and tag not in responses;responses.add(tag)
   x=requests[tag];assert b[4]==0;expected=x['length'] if x['op']==3 else (5 if x['object']>=5 else 3) if x['op']==4 else 0;assert len(b)==5+expected
 assert not leases and not any(packets.values()) and len(requests)==len(responses)
 assert read_bytes[6]==(0 if smoke else 65536) and read_ops[6]==(0 if smoke else 128)
 assert read_bytes[5]==sum(c['bytes'] for c in accepted if c['name']=='SMALL.BIN')
 assert all(stored_status[n]==b for n,b in wire_status_bytes.items()),'Wire LNS is its actual stored snapshot'
 cancelled=[int(n) for n in re.findall(r'CANCELLED_LNS snapshot=(\d+) next=\d+', (d/'events.log').read_text())]
 assert set(stored_status)-set(wire_status_bytes)==set(cancelled)
 assert len(cancelled)==(0 if smoke else 1)
 out=dict(accepted=True,files=[{k:v for k,v in c.items() if k!='blocks'} for c in accepted],LNL_count=len(lists),LNS=statuses,generated_LNS_count=len(stored_status),cancelled_LNS_counters=cancelled,TX_frames=len(all_frames),RX_frames=len((d/'injections.log').read_text().splitlines()),storage_requests=len(requests),storage_completions=len(responses),data_READ_bytes=read_bytes,data_READ_operations=read_ops,remaining_leases=[],source='Actual GMII bytes and tagged device transactions; independent vectors/source grammar')
 (d/'independent-audit.json').write_text(json.dumps(out,indent=2),encoding='utf8');return out
