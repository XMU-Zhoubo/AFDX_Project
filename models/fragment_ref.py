"""RFC791/RFC768 integer reference, independent from RTL state/eligibility."""
import hashlib,json,struct,zlib
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
def checksum(data):
 if len(data)%2:data+=b'\0'
 total=sum(struct.unpack('!%dH'%(len(data)//2),data))
 while total>>16:total=(total&65535)+(total>>16)
 return (~total)&65535
def payload(n,seed):return bytes(((j*73+(j>>8)*19+seed)&255) for j in range(n))
def udp(data,src=0x0a010101,dst=0xe0e00001,sport=0x1234,dport=0x5678):
 header=struct.pack('!HHHH',sport,dport,len(data)+8,0)
 c=checksum(struct.pack('!IIBBH',src,dst,0,17,len(data)+8)+header+data) or 65535
 return header[:6]+struct.pack('!H',c)+data
def split(data,step=1472):
 return [(p//8, p+step<len(data),data[p:p+step]) for p in range(0,len(data),step)]
def frame(raw,vl,seq,ident,offset,mf,network=0,src=0x0a010101):
 dest=0xe0e00000|vl
 header=struct.pack('!BBHHHBBHII',0x45,0,20+len(raw),ident,(8192 if mf else 0)|offset,1,17,0,src,dest)
 header=header[:10]+struct.pack('!H',checksum(header))+header[12:]
 body=bytes.fromhex('03000000')+vl.to_bytes(2,'big')+bytes.fromhex('0200000101')+bytes([0x40 if network else 0x20])+b'\x08\x00'+header+raw
 body+=bytes(max(0,59-len(body)))+bytes([seq])
 return b'\x55'*7+b'\xd5'+body+struct.pack('<I',zlib.crc32(body)&0xffffffff)
def main():
 out=ROOT/'vectors/fragment/c42s';out.mkdir(parents=True,exist_ok=True)
 for n,seed in [(4096,31),(1472,47),(1471,61),(1470,71),(3001,81),(1,91)]:
  p=payload(n,seed);u=udp(p)
  (out/f'p{n}.hex').write_text(''.join(f'{x:02x}\n' for x in p))
  (out/f'u{n}.hex').write_text(''.join(f'{x:02x}\n' for x in u))
 (out/'manifest.json').write_text(json.dumps({str(n):dict(seed=s,length=n,sha256=hashlib.sha256(payload(n,s)).hexdigest(),UDP_bytes=n+8,fragments=[dict(offset8=o,MF=m,bytes=len(p)) for o,m,p in split(udp(payload(n,s)))]) for n,s in [(4096,31),(1472,47),(1471,61),(1470,71),(3001,81),(1,91)]},indent=2)+'\n')
 independent=[];image=bytearray()
 raw=udp(payload(4096,131),dst=0xe0e00042)
 # SN follows arrival order, not IP offset: all candidates meet the frozen IC rule.
 for i,(off,n,more) in enumerate([(2944,1160,False),(1472,1472,True),(1472,1472,True),(0,1472,True)]):
  b=frame(raw[off:off+n],0x42,i,0x6001,off//8,more,1)
  image+=b+bytes(2048-len(b));independent.append(dict(index=i,bytes=len(b),VL=0x42,SN=i,ID=0x6001,offset=off,MF=more,SHA256=hashlib.sha256(b).hexdigest()))
 for ident,bad in [(0x6002,True),(0x6003,False)]:
  for off in (0,1472,2944):
   i=len(independent);part=raw[off:off+1472];more=off+len(part)<len(raw)
   if bad and not more:part=part[:-1]+bytes([part[-1]^128])
   b=frame(part,0x42,i,ident,off//8,more,1);image+=b+bytes(2048-len(b))
   independent.append(dict(index=i,bytes=len(b),VL=0x42,SN=i,ID=ident,offset=off,MF=more,bad_whole_UDP=bad,SHA256=hashlib.sha256(b).hexdigest()))
 (out/'independent.hex').write_text(''.join(f'{b:02x}\n' for b in image))
 (out/'independent.json').write_text(json.dumps(independent,indent=2)+'\n')
 print('C42S_REFERENCE_VECTORS')
if __name__=='__main__':main()
