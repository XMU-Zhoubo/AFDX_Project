"""Independent pyasn1 BER schemas, not the project's encoder/decoder algorithm."""
from pyasn1.codec.ber.decoder import decode
from pyasn1.type import univ,namedtype,tag
import pyasn1
class Binding(univ.Sequence):
    componentType=namedtype.NamedTypes(namedtype.NamedType('name',univ.ObjectIdentifier()),namedtype.NamedType('value',univ.Any()))
class Bindings(univ.SequenceOf):componentType=Binding()
class Common(univ.Sequence):
    componentType=namedtype.NamedTypes(namedtype.NamedType('request',univ.Integer()),namedtype.NamedType('status',univ.Integer()),namedtype.NamedType('index',univ.Integer()),namedtype.NamedType('bindings',Bindings()))
def app(obj,n):return obj.subtype(implicitTag=tag.Tag(tag.tagClassApplication,tag.tagFormatSimple,n))
class Trap(univ.Sequence):
    componentType=namedtype.NamedTypes(namedtype.NamedType('enterprise',univ.ObjectIdentifier()),namedtype.NamedType('agent',app(univ.OctetString(),0)),namedtype.NamedType('generic',univ.Integer()),namedtype.NamedType('specific',univ.Integer()),namedtype.NamedType('ticks',app(univ.Integer(),3)),namedtype.NamedType('bindings',Bindings()))
class Message(univ.Sequence):
    componentType=namedtype.NamedTypes(namedtype.NamedType('version',univ.Integer()),namedtype.NamedType('community',univ.OctetString()),namedtype.NamedType('pdu',univ.Any()))
def parse(raw):
    m,left=decode(raw,asn1Spec=Message());assert not left and int(m['version'])==0
    encoded=bytes(m['pdu']);t=encoded[0]
    schema=(Trap() if t==0xa4 else Common()).subtype(implicitTag=tag.Tag(tag.tagClassContext,tag.tagFormatConstructed,t-0xa0))
    p,left=decode(encoded,asn1Spec=schema);assert not left
    out=dict(pdu=t,community=bytes(m['community']),varbinds=[])
    if t==0xa4:out.update(enterprise=tuple(p['enterprise']),agent=bytes(p['agent']),generic=int(p['generic']),specific=int(p['specific']),ticks=int(p['ticks']))
    else:out.update(request_id=int(p['request']),error_status=int(p['status']),error_index=int(p['index']))
    for b in p['bindings']:
        data=bytes(b['value']);vt=data[0]
        spec={2:univ.Integer(),4:univ.OctetString(),5:univ.Null(),6:univ.ObjectIdentifier(),0x40:app(univ.OctetString(),0),0x41:app(univ.Integer(),1),0x42:app(univ.Integer(),2),0x43:app(univ.Integer(),3),0x44:app(univ.OctetString(),4)}[vt]
        v,left=decode(data,asn1Spec=spec);assert not left
        v=None if vt==5 else tuple(v) if vt==6 else int(v) if vt in (2,0x41,0x42,0x43) else bytes(v)
        out['varbinds'].append(dict(oid=tuple(b['name']),tag=vt,value=v))
    return out
