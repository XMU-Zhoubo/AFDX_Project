"""Strict bounded file model. Public implementation basis, not ARINC text.

LUI/LUR basis unchanged. LUS A4 uses the user-frozen ASCII contract supported
by Thomas Vogt a4367317... source/tests; original library tests are not run.
"""
import struct

VERSION=b'A4'
class FileError(ValueError):pass
def base(data,minimum):
 if not minimum<=len(data)<=512:raise FileError('physical length outside candidate range')
 n,version=struct.unpack('!I2s',data[:6])
 if n!=len(data):raise FileError('declared file length mismatch')
 if version!=VERSION:raise FileError('unsupported file protocol marker')
 return 6
def string(data,p,allow_empty=False):
 if p>=len(data):raise FileError('missing string length')
 n=data[p];p+=1
 if n==0:
  if allow_empty:return b'',p
  raise FileError('empty string unsupported')
 if p+n>len(data) or data[p+n-1]!=0 or 0 in data[p:p+n-1]:raise FileError('string length/NUL mismatch')
 return data[p:p+n-1],p+n
def parse_lui(data):
 p=base(data,9);status=int.from_bytes(data[p:p+2],'big');s,p=string(data,p+2,True)
 if p!=len(data):raise FileError('trailing file bytes')
 if status not in (1,0x1000,0x1002):raise FileError('unsupported initialization status')
 return dict(length=len(data),version='A4',status=status,description=s.decode('ascii'))
def parse_lur(data,max_entries=4,max_string=32):
 p=base(data,8);count=int.from_bytes(data[p:p+2],'big');p+=2
 if not 1<=count<=max_entries:raise FileError('entry count outside candidate range')
 entries=[]
 for i in range(count):
  a,p=string(data,p);b,p=string(data,p)
  if len(a)+1>max_string or len(b)+1>max_string:raise FileError('string exceeds candidate range')
  entries.append(dict(header=a.decode('ascii'),part=b.decode('ascii')))
 if p!=len(data):raise FileError('trailing file bytes')
 return dict(length=len(data),version='A4',entries=entries)
def lui(status,description=b''):
 if status not in (1,0x1000,0x1002) or len(description)>254 or 0 in description:raise FileError('unsupported LUI fields')
 s=(description+b'\0') if description else b''
 return struct.pack('!I2sHB',9+len(s),VERSION,status,len(s))+s
def lur(entries):
 if not 1<=len(entries)<=4:raise FileError('count')
 body=bytearray(struct.pack('!H',len(entries)))
 for a,b in entries:
  for s in (a,b):
   if not 1<=len(s)<=31 or 0 in s:raise FileError('string')
   body+=bytes([len(s)+1])+s+b'\0'
 return struct.pack('!I2s',6+len(body),VERSION)+body

def ratio_ascii(value):
 if type(value) is not int or not 0<=value<=100:raise FileError('ratio outside 0..100')
 return ('%3d'%value).encode('ascii')

def parse_lus(data,max_entries=4):
 """Strict independent cursor, including exact container and string bounds."""
 p=base(data,20)
 def u16():
  nonlocal p
  if p+2>len(data):raise FileError('truncated integer')
  v=int.from_bytes(data[p:p+2],'big');p+=2;return v
 def ratio():
  nonlocal p
  if p+3>len(data):raise FileError('truncated ratio')
  raw=data[p:p+3];p+=3
  try:v=int(raw.decode('ascii'))
  except (ValueError,UnicodeError):raise FileError('non decimal ASCII ratio')
  if raw!=ratio_ascii(v):raise FileError('noncanonical engineering ratio')
  return v
 status=u16()
 if status not in (1,2,3,0x1000,0x1002):raise FileError('unsupported bounded LUS status')
 description,p=string(data,p,True);counter=u16();exception=u16();estimated=u16();progress=ratio();count=u16()
 if count>max_entries:raise FileError('LUS count exceeds engineering bound')
 entries=[]
 for i in range(count):
  name,p=string(data,p);part,p=string(data,p);r=ratio();s=u16();desc,p=string(data,p,True)
  if len(name)>31 or len(part)>31:raise FileError('entry string exceeds engineering bound')
  entries.append(dict(header=name.decode('ascii'),part=part.decode('ascii'),ratio=r,status=s,description=desc.decode('ascii')))
 if p!=len(data):raise FileError('trailing LUS bytes')
 return dict(length=len(data),version='A4',status=status,description=description.decode('ascii'),counter=counter,
  exception_timer=exception,estimated_time=estimated if estimated<32768 else estimated-65536,ratio=progress,count=count,entries=entries)

def lus_initial(counter=1):
 if type(counter) is not int or not 0<=counter<=65535:raise FileError('counter range')
 return struct.pack('!I2sHBHHH',20,VERSION,1,0,counter,0,0)+ratio_ascii(0)+b'\0\0'
