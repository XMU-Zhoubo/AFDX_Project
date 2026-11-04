"""Read-only independent physical-wire, stored-file and event audit."""
import sys,json,zlib,hashlib,struct,re,bisect
from pathlib import Path
sys.dont_write_bytecode=True
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'models'))
from load665_ref import validate_package
from arinc615a_ref import base,string

def checksum(data):
 if len(data)%2:data+=b'\0'
 s=sum(struct.unpack('>'+str(len(data)//2)+'H',data))
 while s>>16:s=(s&65535)+(s>>16)
 return (~s)&65535

def parse_status(data):
 p=base(data,20)
 def uint(n):
  nonlocal p
  assert p+n<=len(data);v=int.from_bytes(data[p:p+n],'big');p+=n;return v
 def ratio():
  nonlocal p
  v=data[p:p+3];p+=3;n=int(v);assert 0<=n<=100 and v==f'{n:3d}'.encode();return n
 status=uint(2);assert status in [1,2,3,0x1003,0x1007]
 desc,p=string(data,p,True);counter=uint(2);exception=uint(2);estimated=uint(2);r=ratio();count=uint(2);assert count<=1
 entries=[]
 for _ in range(count):
  name,p=string(data,p);pn,p=string(data,p);progress=ratio();code=uint(2);description,p=string(data,p,True);entries.append(dict(name=name.decode(),part=pn.decode(),ratio=progress,status=code))
 assert p==len(data)
 return dict(status=status,counter=counter,ratio=r,count=count,entries=entries)

def check(folder):
 d=Path(folder);frames=[];lus=[]
 for line in (d/'wire.log').read_text().splitlines():
  net,start,end,h=line.split();f=bytes.fromhex(h);assert f[:8]==b'\x55'*7+b'\xd5';assert zlib.crc32(f[8:-4])==int.from_bytes(f[-4:],'little')
  if f[8]==3:continue
  ip=f[22:42];assert checksum(ip)==0;total=int.from_bytes(ip[2:4],'big');u=f[42:22+total];ul=int.from_bytes(u[4:6],'big');assert ul==len(u);assert checksum(ip[12:20]+b'\0\x11'+u[4:6]+u)==0
  sp,dp=struct.unpack('>HH',u[:4]);payload=u[8:];frames.append(dict(network=int(net),start=int(start),end=int(end),source=sp,destination=dp,length=len(payload),op=int.from_bytes(payload[:2],'big')))
  if 45001<=sp<=49151 and payload[:4]==b'\0\3\0\1':lus.append(parse_status(payload[4:]))
 statusrows=[]
 for line in (d/'status-files.log').read_text().splitlines():
  idx,t,n,h=line.split();data=bytes.fromhex(h);assert len(data)==int(n);statusrows.append(dict(upload=int(idx),time=int(t),decoded=parse_status(data),sha256=hashlib.sha256(data).hexdigest()))
 files={}
 for line in (d/'readback.log').read_text().splitlines():
  epoch,uid,offset,value=line.split();files.setdefault((int(epoch),int(uid)),{})[int(offset)]=int(value,16)
 results=[]
 for key,byteset in files.items():
  data=bytes(byteset[i] for i in range(len(byteset)));assert len(data) in [37,4096]
  v=0 if len(data)==37 else 1;gold=d/'inputs/vectors/615a/c35'/f'data{v}.bin';h=(gold.parent/f'header{v}.bin').read_bytes();assert data==gold.read_bytes();meta=validate_package(h,data)
  results.append(dict(key=key,length=len(data),sha256=hashlib.sha256(data).hexdigest(),metadata=meta))
 assert any(r['length']==4096 for r in results) and any(r['length']==37 for r in results)
 assert any(s['decoded']['status']==0x1003 for s in statusrows)
 assert any(s['decoded']['status']==3 and s['decoded']['ratio']==100 for s in statusrows)
 # The link and nonce are jointly reset by the public reset stimulus. A tag
 # identifies a transaction within that reset epoch, not across device resets.
 # events.log uses integer ns; the raw storage link uses ModelSim %t (ps).
 resets=[int(v)*1000 for v in re.findall(r'^RESET_CANCEL upload=\d+ time=(\d+)$',(d/'events.log').read_text(),re.M)]
 assert resets==sorted(set(resets))
 requests=[];packet=[];epoch=0;reset_partial_packets=0
 for line in (d/'storage_bus.log').read_text().splitlines():
  parts=line.split()
  next_epoch=bisect.bisect_right(resets,int(parts[1]))
  if next_epoch!=epoch:
   assert next_epoch>epoch
   reset_partial_packets+=bool(packet);packet=[];epoch=next_epoch
  if parts[0]=='TX':
   _,tick,b,last=parts;packet.append(int(b,16))
   if int(last):
    raw=bytes(packet);packet=[];assert len(raw)>=11
    op,obj=raw[:2];offset,length=struct.unpack('>HH',raw[2:6]);tag=int.from_bytes(raw[7:11],'big');assert len(raw)==11+(length if op==2 else 0)
    assert offset+length<=(4096 if obj==0 else 512);assert not(obj==0 and offset==4096 and length!=0)
    requests.append(dict(epoch=epoch,tick=int(tick),op=op,object=obj,offset=offset,length=length,final=raw[6],tag=tag))
  elif parts[0]=='CANCEL':packet=[]
 assert not packet, 'Unfinished storage request at normal end'
 assert len({(r['epoch'],r['tag']) for r in requests})==len(requests), 'Storage tag reused within one reset epoch'
 assert any(r['op']==2 and r['object']==0 and r['length']==0 and r['offset']==4096 and r['final'] for r in requests)
 assert any(r['op']==5 and r['object']==0 for r in requests)
 out=dict(accepted=True,physical_frames=len(frames),active_LUS_data=len(lus),status_files=statusrows,readback_files=results,storage_requests=requests,tag_identity='(public reset epoch, BE32 tag)',reset_times_ps=resets,reset_partial_packets=reset_partial_packets)
 (d/'independent-audit.json').write_text(json.dumps(out,indent=2),encoding='utf8');return out
