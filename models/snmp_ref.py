"""Independent, bounded SNMPv1 reference; no RTL imports or DUT observations.

RFC1157 sections 3.2.2,4,5; RFC1155 3.2/6. Scalar object IDs in
docs/mib_objects.json are an UNREGISTERED, isolated demonstration namespace.
The encoder emits shortest definite lengths; decoder also accepts non-shortest
definite length forms. INTEGER/OID content constraints are BER, not DER rules.
"""
MAX_MESSAGE=512
MAX_COMMUNITY=32
MAX_VARBINDS=8
MAX_STRING=256
MAX_ARCS=32
BASE=(1,3,6,1,3,664,2026,1)
TAGS={2,4,5,6,0x40,0x41,0x42,0x43,0x44}
class CodecError(ValueError):
    def __init__(self, code, text): super().__init__(text); self.code=code
def fail(code,text): raise CodecError(code,text)
def length(n):
    if n<0: fail(3,'negative length')
    return bytes([n]) if n<128 else bytes([0x81,n]) if n<256 else bytes([0x82,n>>8,n&255])
def tlv(tag,b): return bytes([tag])+length(len(b))+b
def integer(n,unsigned=False):
    if not (0<=n<2**32 if unsigned else -2**31<=n<2**31): fail(3,'integer range')
    if unsigned:
        b=n.to_bytes(max(1,(n.bit_length()+7)//8),'big')
        return b'\0'+b if b[0]&128 else b
    for size in range(1,5):
        if -(1<<(8*size-1))<=n<(1<<(8*size-1)): return n.to_bytes(size,'big',signed=True)
def base128(n):
    out=[n&127]; n>>=7
    while n: out.insert(0,0x80|(n&127));n>>=7
    return bytes(out)
def oid(arcs):
    if not 2<=len(arcs)<=MAX_ARCS or arcs[0] not in (0,1,2): fail(3,'OID arity/root')
    if not all(type(a) is int and 0<=a<2**32 for a in arcs) or (arcs[0]<2 and arcs[1]>39): fail(3,'OID arc range')
    return base128(40*arcs[0]+arcs[1])+b''.join(base128(a) for a in arcs[2:])
def value(tag,v):
    if tag not in TAGS: fail(4,'unsupported value syntax')
    if tag==2: b=integer(v)
    elif tag in (0x41,0x42,0x43): b=integer(v,True)
    elif tag==6: b=oid(v)
    elif tag==5:
        if v is not None: fail(2,'NULL value')
        b=b''
    else:
        b=bytes(v)
        if tag==0x40 and len(b)!=4: fail(2,'IpAddress length')
        if len(b)>MAX_STRING: fail(3,'string length')
    return tlv(tag,b)
def encode(m, enforce=True):
    community=bytes(m.get('community',b'public'));vbs=m.get('varbinds',[]);tag=m['pdu']
    if enforce and (len(community)>32 or len(vbs)>8): fail(3,'object limit')
    vb=b''.join(tlv(0x30,tlv(6,oid(tuple(v['oid'])))+value(v['tag'],v['value'])) for v in vbs)
    if tag==0xa4:
        fields=tlv(6,oid(tuple(m['enterprise'])))+tlv(0x40,bytes(m['agent']))
        fields+=value(2,m['generic'])+value(2,m['specific'])+value(0x43,m['ticks'])
    elif tag in (0xa0,0xa1,0xa2,0xa3):
        fields=value(2,m.get('request_id',0))+value(2,m.get('error_status',0))+value(2,m.get('error_index',0))
    else: fail(4,'PDU not SNMPv1')
    b=tlv(0x30,value(2,0)+tlv(4,community)+tlv(tag,fields+tlv(0x30,vb)))
    if enforce and len(b)>512: fail(3,'message limit')
    return b

def decode(data):
    """Cursor/recursive container reference, distinct from clocked hardware FSM."""
    data=bytes(data)
    if len(data)>512: fail(3,'message limit')
    def item(pos,limit,expected=None):
        if pos+2>limit: fail(1,'truncated TLV')
        tag=data[pos]; n=data[pos+1]; pos+=2
        if n&128:
            count=n&127
            if count==0 or count==127: fail(2,'indefinite/reserved length')
            if count>2: fail(3,'length-of-length limit')
            if pos+count>limit: fail(1,'truncated length')
            n=int.from_bytes(data[pos:pos+count],'big');pos+=count
        if pos+n>limit: fail(1,'TLV exceeds container')
        if expected is not None and tag!=expected: fail(5,'wrong tag')
        return tag,pos,pos+n
    def number(tag,a,b,unsigned=False):
        raw=data[a:b]
        if not raw: fail(2,'empty INTEGER')
        if len(raw)>1 and ((raw[0]==0 and not raw[1]&128) or (raw[0]==255 and raw[1]&128)): fail(2,'redundant sign')
        n=int.from_bytes(raw,'big',signed=True)
        if not (0<=n<2**32 if unsigned else -2**31<=n<2**31): fail(3,'numeric range')
        return n
    def read_oid(a,b):
        if a==b: fail(2,'empty OID')
        subs=[];n=0;first=True
        for c in data[a:b]:
            if first and c==0x80: fail(2,'nonminimal OID subidentifier')
            n=n*128+(c&127)
            if n>(2**32+79 if not subs else 2**32-1): fail(3,'OID overflow')
            first=not bool(c&128)
            if first:subs.append(n);n=0
        if not first: fail(2,'unterminated OID')
        n=subs.pop(0);r=[0,n] if n<40 else [1,n-40] if n<80 else [2,n-80]
        r+=subs
        if len(r)>32: fail(3,'OID arc limit')
        return tuple(r)
    def read_value(tag,a,b):
        if tag==2:return number(tag,a,b)
        if tag in (0x41,0x42,0x43):return number(tag,a,b,True)
        if tag==6:return read_oid(a,b)
        if tag==5:
            if a!=b:fail(2,'nonempty NULL')
            return None
        if tag in (4,0x40,0x44):
            if tag==0x40 and b-a!=4:fail(2,'IpAddress length')
            if b-a>256:fail(3,'string limit')
            return data[a:b]
        fail(4,'unsupported ObjectSyntax')
    tag,pos,outer=item(0,len(data),0x30)
    if outer!=len(data):fail(1,'trailing bytes')
    tag,a,pos=item(pos,outer,2)
    if number(tag,a,pos)!=0:fail(6,'version not v1')
    tag,a,pos=item(pos,outer,4);community=data[a:pos]
    if len(community)>32:fail(3,'community limit')
    tag,p,pdu_end=item(pos,outer)
    if pdu_end!=outer:fail(1,'extra after PDU')
    m=dict(pdu=tag,community=community,varbinds=[])
    if tag==0xa4:
        _,a,p=item(p,pdu_end,6);m['enterprise']=read_oid(a,p)
        _,a,p=item(p,pdu_end,0x40)
        if p-a!=4:fail(2,'agent IpAddress size')
        m['agent']=data[a:p]
        for name,t in [('generic',2),('specific',2),('ticks',0x43)]:
            _,a,p=item(p,pdu_end,t);m[name]=number(t,a,p,t==0x43)
        if not 0<=m['generic']<=6 or m['specific']<0:fail(3,'Trap range')
    elif tag in (0xa0,0xa1,0xa2,0xa3):
        for name in ('request_id','error_status','error_index'):
            _,a,p=item(p,pdu_end,2);m[name]=number(2,a,p)
        if not 0<=m['error_status']<=5:fail(3,'error-status range')
    else:fail(4,'PDU outside profile')
    _,p,end=item(p,pdu_end,0x30)
    if end!=pdu_end:fail(1,'extra PDU fields')
    while p<end:
        if len(m['varbinds'])==8:fail(3,'VarBind count')
        _,q,e=item(p,end,0x30)
        _,a,q=item(q,e,6);name=read_oid(a,q)
        t,a,q=item(q,e);v=read_value(t,a,q)
        if q!=e:fail(1,'extra VarBind field')
        m['varbinds'].append(dict(oid=name,tag=t,value=v));p=e
    return m

def record(m):
    """Public 32-bit word object file; only used words have defined contents."""
    c=bytes(m.get('community',b'public'));vbs=m.get('varbinds',[])
    r={0:m['pdu'],1:m.get('request_id',0)&0xffffffff,2:m.get('error_status',0),3:m.get('error_index',0)&0xffffffff,
       4:len(c),5:len(vbs),6:len(m.get('enterprise',())),7:int.from_bytes(m.get('agent',b'\0'*4),'big'),
       8:m.get('generic',0),9:m.get('specific',0),10:m.get('ticks',0)}
    r.update({16+i:b for i,b in enumerate(c)})
    r.update({48+i:a for i,a in enumerate(m.get('enterprise',()))})
    for i,v in enumerate(vbs):
        base=128+i*384;t=v['tag'];x=v['value']
        size=len(x) if t in (4,6,0x40,0x44) else 0
        r.update({base:len(v['oid']),base+1:t,base+2:size,base+3:(x&0xffffffff) if t in (2,0x41,0x42,0x43) else 0})
        r.update({base+4+j:a for j,a in enumerate(v['oid'])})
        if t==6:r.update({base+36+j:a for j,a in enumerate(x)})
        elif t in (4,0x40,0x44):r.update({base+68+j:b for j,b in enumerate(x)})
    return dict(sorted(r.items()))
