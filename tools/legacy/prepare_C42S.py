from pathlib import Path
import hashlib,json,os
ROOT=Path(__file__).resolve().parents[2]
REPORT=Path(os.environ['C45_OUTPUT'])
O=REPORT
def digest(p):
 h=hashlib.sha256()
 with Path(p).open('rb') as f:
  for b in iter(lambda:f.read(4194304),b''):h.update(b)
 return h.hexdigest()
def read(p):return json.loads(Path(p).read_text(encoding='utf-8-sig'))
def save(p,x):
 p=Path(p);p.parent.mkdir(parents=True,exist_ok=True);p.write_text(json.dumps(x,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
def ref(p):
 p=Path(p).resolve();return dict(path=str(p),sha256=digest(p),bytes=p.stat().st_size)
