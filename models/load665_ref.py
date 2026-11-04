"""C35 bounded genuine 665-3 (0x8004) package, from pinned serializers.

No optional checks, support files, positions, load type or user data. Mandatory
data/header CRC16 and whole-load CRC32 are retained. Units are not interchangeable.
"""
import binascii,struct
U16=lambda v:struct.pack('>H',v)
U32=lambda v:struct.pack('>I',v)
U64=lambda v:struct.pack('>Q',v)
def crc16(data):return binascii.crc_hqx(data,0xffff)
def crc32(data):
    # Byte table implementation, independent of the RTL serial bit recurrence.
    table=[]
    for b in range(256):
        x=b<<24
        for _ in range(8):x=((x<<1)^ (0x04c11db7 if x&0x80000000 else 0))&0xffffffff
        table.append(x)
    x=0xffffffff
    for b in data:x=((x<<8)&0xffffffff)^table[(x>>24)^b]
    return x^0xffffffff
def string(text):
    b=text.encode('ascii')
    if not 1<=len(b)<=31 or 0 in b:raise ValueError('profile string')
    return U16(len(b))+b+(b'\0' if len(b)&1 else b'')
def header(data,name='PAYLOAD.BIN',pn='C35-PN',data_pn='DATA-PN'):
    if not 0<=len(data)<=4096:raise ValueError('capacity')
    p=bytearray(40);p[4:8]=U16(0x8004)+U16(0)
    def section(offset,content):
        p[offset:offset+4]=U32(len(p)//2);p.extend(content)
    section(8,string(pn));section(12,U16(1)+string('AFDX'))
    section(16,U16(1)+U16(0)+string(name)+string(data_pn)+U32((len(data)+1)//2)+U16(crc16(data))+U64(len(data))+U16(0))
    section(36,U16(0));p[:4]=U32((len(p)+6)//2)
    p.extend(U16(crc16(p)));p.extend(U32(crc32(p+data)))
    return bytes(p)
def parse_header(raw):
    def u(n,k):
        if n<0 or n+k>len(raw):raise ValueError('bounds')
        return int.from_bytes(raw[n:n+k],'big')
    def text(pos):
        l=u(pos,2);pos+=2
        if not 1<=l<=31 or pos+l+(l&1)>len(raw):raise ValueError('string length')
        b=raw[pos:pos+l]
        if any(v<32 or v>126 for v in b) or l&1 and raw[pos+l]!=0:raise ValueError('string bytes/pad')
        return b.decode(),pos+l+(l&1)
    if len(raw)<48 or len(raw)>512 or u(0,4)*2!=len(raw) or u(4,2)!=0x8004 or u(6,2)!=0:raise ValueError('base')
    if any(u(n,4) for n in [20,24,28,32]):raise ValueError('outside profile')
    ptr=[u(n,4)*2 for n in [8,12,16,36]]
    if ptr[0]!=40:raise ValueError('canonical order')
    pn,end=text(ptr[0])
    if end!=ptr[1] or u(end,2)!=1:raise ValueError('hardware count')
    hw,end=text(end+2)
    if hw!='AFDX' or end!=ptr[2] or u(end,2)!=1 or u(end+2,2)!=0:raise ValueError('target/list')
    name,end=text(end+4);dpn,end=text(end)
    words=u(end,4);data_crc=u(end+4,2);size=u(end+6,8)
    if size>4096 or words!=(size+1)//2 or u(end+14,2)!=0:raise ValueError('size/check')
    if end+16!=ptr[3] or u(ptr[3],2)!=0 or ptr[3]+8!=len(raw):raise ValueError('trailer')
    if crc16(raw[:-6])!=u(len(raw)-6,2):raise ValueError('header crc')
    return dict(part_number=pn,hardware=hw,data_name=name,data_part_number=dpn,size=size,data_crc16=data_crc,load_crc32=u(len(raw)-4,4))
def validate_package(raw,data):
    m=parse_header(raw)
    if len(data)!=m['size'] or crc16(data)!=m['data_crc16'] or crc32(raw[:-4]+data)!=m['load_crc32']:raise ValueError('content check')
    return m
