"""Pinned A4 ODD file grammar, independent of the DUT serializers."""
import struct

def string(v):
 if isinstance(v,str):v=v.encode('ascii')
 if not v:return b'\0'
 assert b'\0' not in v and len(v)<=254
 return bytes([len(v)+1])+v+b'\0'

def envelope(body):return struct.pack('>I',len(body)+6)+b'A4'+body
def lno(code=1,description='Ready'):return envelope(struct.pack('>H',code)+string(description))
def lnl(files):return envelope(struct.pack('>H',len(files))+b''.join(string(n)+string(d) for n,d in files))
def lna(files):return envelope(struct.pack('>H',len(files))+b''.join(string(n) for n in files))
def lns(code,counter,files=(),ratio=0,description='',exception=0,estimated=0):
 return envelope(struct.pack('>H',code)+string(description)+struct.pack('>HHh',counter,exception,estimated)+f'{ratio:3d}'.encode()+struct.pack('>H',len(files))+b''.join(string(n)+struct.pack('>H',c)+string(d) for n,c,d in files))

def parse(data,kind):
 assert len(data)>=8 and struct.unpack('>I',data[:4])[0]==len(data) and data[4:6]==b'A4'
 p=6
 def uint(n,signed=False):
  nonlocal p
  assert p+n<=len(data);v=int.from_bytes(data[p:p+n],'big',signed=signed);p+=n;return v
 def text():
  nonlocal p
  n=uint(1);assert p+n<=len(data)
  if n==0:return ''
  assert data[p+n-1]==0 and b'\0' not in data[p:p+n-1];s=data[p:p+n-1].decode('ascii');p+=n;return s
 if kind=='LNO':out=dict(status=uint(2),description=text())
 elif kind in ['LNL','LNA']:
  n=uint(2);assert n<=16
  out=dict(files=[(text(),text()) if kind=='LNL' else text() for _ in range(n)])
 else:
  assert kind=='LNS';out=dict(status=uint(2),description=text(),counter=0)
  out.update(counter=uint(2),exception=uint(2),estimated=uint(2,True))
  assert p+3<=len(data);r=data[p:p+3];p+=3;v=int(r);assert 0<=v<=100 and r==f'{v:3d}'.encode();out['ratio']=v
  n=uint(2);assert n<=16;out['files']=[dict(name=text(),status=uint(2),description=text()) for _ in range(n)]
 assert p==len(data);return out

def pattern(n,seed):return bytes((i*73+(i>>8)*91+(i>>15)*37+seed)&255 for i in range(n))
