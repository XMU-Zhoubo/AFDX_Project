"""Recompute bytes, IP/UDP/FCS, fragment intervals and unique message delivery."""
import argparse,csv,hashlib,json,re,struct,zlib
from collections import defaultdict
from pathlib import Path
from prepare_C42S import ROOT,REPORT,read,save,ref,digest
import sys
sys.path.insert(0,str(ROOT/'models'))
from fragment_ref import payload,checksum
def fields(line):return {k:int(v,16) if k in ('data','value') else int(v) for k,v in re.findall(r'(\w+)=([a-fA-F0-9]+)',line)}
def decode(raw):
 assert raw[:8]==b'\x55'*7+b'\xd5','preamble'
 b=raw[8:-4];assert struct.pack('<I',zlib.crc32(b)&0xffffffff)==raw[-4:],'FCS'
 assert b[12:14]==b'\x08\x00' and b[14]==0x45,'Ethernet/IPv4'
 h=b[14:34];assert checksum(h)==0,'IPv4 checksum'
 length=int.from_bytes(h[2:4],'big');flags=int.from_bytes(h[6:8],'big')
 assert length>=20 and len(b)==max(60,14+length+1),'IP/Ethernet length'
 assert not(flags&0x8000) and h[9]==17,'reserved/protocol'
 data=b[34:14+length];vl=int.from_bytes(b[4:6],'big')
 assert b[:4]==bytes.fromhex('03000000') and len(raw)<=1526,'Lmax'
 mf=bool(flags&8192);offset=(flags&8191)*8
 assert not mf or len(data)%8==0,'alignment'
 return dict(VL=vl,ID=int.from_bytes(h[4:6],'big'),offset=offset,MF=mf,DF=bool(flags&16384),SN=b[-1],src=int.from_bytes(h[12:16],'big'),dst=int.from_bytes(h[16:20],'big'),raw=data)
def datagram(data,src,dst):
 assert len(data)>=9 and int.from_bytes(data[4:6],'big')==len(data),'UDP length'
 assert data[:4]==bytes.fromhex('12345678'),'ports'
 assert data[6:8]!=b'\0\0','TX UDP checksum mandatory'
 assert checksum(struct.pack('!IIBBH',src,dst,0,17,len(data))+data)==0,'whole UDP checksum'
 return data[8:]
def audit(directory,publish=True,result_path=None):
 d=Path(directory);rp=Path(result_path) if result_path else d/'result.json';result=read(rp);assert result['accepted']
 for x in read(d/'inputs.json')['sources']:assert digest(x['snapshot'])==x['sha256'],'compiled snapshot'
 messages={};received=defaultdict(dict);outtimes={};visible={};desc={};done={}
 for line in (d/'application.log').read_text().splitlines():
  e=fields(line)
  if line.startswith(('INPUT ','EXTERNAL ')):messages[e['id']]=dict(**e,external=line.startswith('EXTERNAL '))
  elif line.startswith('DESC '):assert e['id'] not in desc;desc[e['id']]=e
  elif line.startswith('VISIBLE '):assert e['id'] not in visible;visible[e['id']]=e['time_ns']
  elif line.startswith('BYTE '):
   # data is hexadecimal even when it contains digits only.
   e['data']=int(re.search(r'\bdata=([0-9a-fA-F]+)',line)[1],16)
   assert e['offset'] not in received[e['id']],'duplicate output byte'
   received[e['id']][e['offset']]=e['data'];outtimes.setdefault(e['id'],e['time_ns'])
  elif line.startswith('DONE '):assert e['id'] not in done,'duplicate delivery';done[e['id']]=e
 assert set(messages)==set(done)==set(desc)==set(received),'message ledger'
 inputs=defaultdict(dict);offers={}
 for line in (d/'input.log').read_text().splitlines():
  e=fields(line)
  if line.startswith('OFFER '):offers[e['id']]=e
  if line.startswith('ACCEPT '):
   e['data']=int(re.search(r'\bdata=([0-9a-fA-F]+)',line)[1],16);assert e['offset'] not in inputs[e['id']]
   inputs[e['id']][e['offset']]=e['data']
 fragments=[];assembled={};last={};sequence={};previous_end={};copies=defaultdict(list);txpayloads=defaultdict(list);tx_net=defaultdict(int)
 for line in (d/'frames.log').read_text().splitlines():
  net,start,end,raw=line.split();net,start,end=int(net),int(start),int(end);wire=bytes.fromhex(raw);f=decode(wire);key=(net,f['VL'])
  assert wire[14:20]==bytes.fromhex('0200000101')+bytes([0x40 if net else 0x20]),'Network sourceMAC'
  expected_sn=0 if key not in sequence else 1 if sequence[key]==255 else sequence[key]+1
  assert f['SN']==expected_sn,'Per-VL SN consumed once per fragment'
  sequence[key]=f['SN']
  if net in previous_end:assert start-previous_end[net]>=96,'Actual IFG'
  previous_end[net]=end
  body=bytearray(wire[8:-4]);body[11]=0;copies[(net,f['VL'])].append(bytes(body))
  assert f['DF'] or f['MF'] or f['offset']>0,'fragment flags'
  assert f['src']==0x0a010101 and f['dst']==0xe0e00000+f['VL'],'IP endpoints'
  if key in last:assert start-last[key]>= (2000000 if f['VL']==0x8001 else 1000000),'real BAG'
  last[key]=start;tx_net[net]+=1
  fragments.append({**{k:v for k,v in f.items() if k!='raw'},'net':net,'start_ns':start,'end_ns':end,'IP_payload_bytes':len(f['raw'])})
  if f['DF']:
   p=datagram(f['raw'],f['src'],f['dst']);txpayloads[(net,f['VL'])].append(p)
  else:
   k=(net,f['VL'],f['ID']);a=assembled.setdefault(k,dict(parts={},end=None,src=f['src'],dst=f['dst']))
   for off,part in a['parts'].items():assert f['offset']+len(f['raw'])<=off or off+len(part)<=f['offset'],'TX no overlap'
   a['parts'][f['offset']]=f['raw']
   if not f['MF']:assert a['end'] is None;a['end']=f['offset']+len(f['raw'])
 for k,a in assembled.items():
  pos=0;raw=b''
  for off,part in sorted(a['parts'].items()):assert off==pos,'no missing TX fragment';raw+=part;pos+=len(part)
  assert pos==a['end'];txpayloads[k[:2]].append(datagram(raw,a['src'],a['dst']))
 for vl in {k[1] for k in copies}:assert copies[(0,vl)]==copies[(1,vl)],'A/B same logical frame fields and SN; source network byte is only legal difference'
 # Match each side against independent application events, not the DUT's descriptor.
 rows=[]
 for ident,m in sorted(messages.items()):
  n=m['length'];expected=payload(n,m['seed'])
  actual=bytes(received[ident][j] for j in range(n));assert len(received[ident])==n and actual==expected,'output payload'
  assert desc[ident]['vl']==m['vl'] and desc[ident]['length']==n
  if not m['external']:
   assert bytes(inputs[ident][j] for j in range(n))==expected and len(inputs[ident])==n,'actual app input'
   for net in (0,1):
    candidates=txpayloads[(net,m['vl'])];assert expected in candidates,'each actual MAC transmitted full message';candidates.remove(expected)
  rows.append(dict(id=ident,VL=m['vl'],length=n,external=m['external'],SHA256=hashlib.sha256(actual).hexdigest(),first_input_ns=offers[ident]['time_ns'] if ident in offers else None,first_output_visible_ns=visible.get(ident),first_output_consume_ns=outtimes[ident],whole_done_ns=done[ident]['time_ns']))
 assert not any(txpayloads.values()),'unexplained TX messages'
 rx=[];rx_datagrams={}
 for line in (d/'stimulus.log').read_text().splitlines():
  net,end,raw=line.split();f=decode(bytes.fromhex(raw));rx.append(dict(net=int(net),end_ns=int(end),**{k:v for k,v in f.items() if k!='raw'}))
  if f['MF'] or f['offset']:
   k=(f['VL'],f['src'],f['dst'],f['ID']);g=rx_datagrams.setdefault(k,dict(parts={},end=None))
   if f['offset'] in g['parts']:assert g['parts'][f['offset']]==f['raw'],'conflicting physical copies'
   g['parts'][f['offset']]=f['raw']
   if not f['MF']:
    e=f['offset']+len(f['raw']);assert g['end'] in (None,e);g['end']=e
 assert len(rx)>0 and any(f['net']==1 and f['VL']==0x8001 for f in rx),'B actual business'
 csr={};stats={}
 for line in (d/'configuration.log').read_text().splitlines():
  e=fields(line)
  if line.startswith('READ ') and e.get('kind')==3 and e.get('index')==15:csr[e['word']]=int(re.search(r'value=([0-9a-fA-F]+)',line)[1],16)
  if line.startswith('READ ') and e.get('kind')==2:stats[e['index']]=int(re.search(r'value=([0-9a-fA-F]+)',line)[1],16)
 dispositions=[]
 for k,g in rx_datagrams.items():
  off=0;body=b''
  for start,part in sorted(g['parts'].items()):
   if start!=off:break
   body+=part;off+=len(part)
  fate='incomplete_cancelled'
  if g['end']==off:
   try:datagram(body,k[1],k[2]);fate='whole_UDP_pass'
   except AssertionError:fate='whole_UDP_rejected'
  dispositions.append(dict(VL=k[0],ID=k[3],fate=fate,bytes=off))
 bad=sum(x['fate']=='whole_UDP_rejected' for x in dispositions);cancel=sum(x['fate']=='incomplete_cancelled' for x in dispositions)
 late=sum(line.startswith('LATE_A_REINJECT ') for line in (d/'links.log').read_text().splitlines())
 assert csr[1]==csr[2]==len(rx_datagrams),'message allocation/free independent ledger'
 assert csr[3]==bad+cancel+late and csr[4]==len(rx_datagrams)-bad-cancel,'message disposition counts'
 assert csr[5]&3==0 and stats[18]==0 and stats[28]==8<<16 and stats[29]==16<<16,'all pools and ownership'
 assert stats[24]==len(messages) and stats[25]==sum(m['length'] for m in messages.values()),'real application MIB boundary'
 (d/'message-audit.csv').write_text('')
 for name,table in [('message-audit.csv',rows),('fragment-audit.csv',fragments)]:
  with (d/name).open('w',newline='') as out:
   w=csv.DictWriter(out,fieldnames=table[0].keys());w.writeheader();w.writerows(table)
 answer=dict(accepted=True,directory=str(d),result=ref(rp),messages=rows,TX_fragments=len(fragments),TX_by_network=dict(tx_net),RX_physical_frames=len(rx),actual_input_bytes=sum(len(v) for v in inputs.values()),unique_output_bytes=sum(m['length'] for m in messages.values()),reassembly=dispositions,message_CSR=csr,frame_and_MIB_CSR=stats,late_tombstone_drops=late,checks='Independent RFC IP/UDP/FCS, payload/event/length/SHA, real BAG, actual two-MAC TX, output uniqueness and physical-fragment-derived allocation/free/disposition ledger')
 save(d/'independent-audit.json',answer)
 if publish:save(REPORT/'latest-system-audit.json',answer)
 print('C42S_INDEPENDENT_AUDIT_PASS',len(rows),len(fragments),len(rx));return answer
if __name__=='__main__':
 p=argparse.ArgumentParser();p.add_argument('--directory');a=p.parse_args();audit(a.directory or read(REPORT/'latest-system.json')['directory'])
