"""Portable C46 short, full83 RTL demos. Explicit new libraries; no EDA/EQ."""
from pathlib import Path
import argparse, datetime as dt, hashlib, importlib, json, os, re, shutil, subprocess, sys, time, types
sys.dont_write_bytecode=True
ROOT=Path(__file__).resolve().parents[1]
H='c6af30620c6ac1c4358ed136e12b683e5bbd109d2ce18dddd3ee3c19fde901ed'
def stamp():return dt.datetime.now().astimezone().isoformat()
def read(p):return json.loads(Path(p).read_text(encoding='utf-8-sig'))
def sha(p):
 h=hashlib.sha256()
 with Path(p).open('rb') as f:
  for b in iter(lambda:f.read(4194304),b''):h.update(b)
 return h.hexdigest()
def ref(p):
 p=Path(p).resolve();return dict(path=str(p),sha256=sha(p),bytes=p.stat().st_size)
def save(p,x):
 p=Path(p);p.parent.mkdir(parents=True,exist_ok=True);p.write_text(json.dumps(x,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
def local_ini(case,env):
 base=Path(env['modelsim']).resolve().parents[1]/'modelsim.ini';s=base.read_text();block=s[s.index('[Library]'):s.index('[DefineOptionset]')];rows=[]
 for name,path in re.findall(r'(?m)^([\w]+)\s*=\s*([^;\r\n]+)',block):
  if name.lower() not in ('others','work'):
   rows.append(name+' = '+path.strip().replace('$MODEL_TECH',Path(env['modelsim']).resolve().parent.as_posix()))
 s=s[:s.index('[Library]')]+'[Library]\n'+'\n'.join(rows)+'\nwork = '+(case/'work').as_posix()+'\nelinx_lib = '+Path(env['official_library']).as_posix()+'\n\n'+s[s.index('[DefineOptionset]'):]
 (case/'modelsim.ini').write_text(s,encoding='utf-8');return ref(base)
def native(case,argv,limit):
 start=time.monotonic();record=dict(pid=None,argv=argv,cwd=str(case),started=stamp(),complete=False,host_guard_seconds=limit,not_DUT_watchdog=True)
 save(case/'launch-native.json',record)
 with (case/'console.log').open('wb',buffering=0) as f:
  p=subprocess.Popen(argv,cwd=case,stdout=f,stderr=subprocess.STDOUT,stdin=subprocess.DEVNULL,creationflags=getattr(subprocess,'CREATE_NO_WINDOW',0),env={**os.environ,'MODELSIM':str(case/'modelsim.ini')})
  record['pid']=p.pid;save(case/'process.json',record);expired=False
  while p.poll() is None:
   save(case/'heartbeat.json',dict(updated=stamp(),pid=p.pid,elapsed_seconds=time.monotonic()-start,process_handle_alive=True,stale_after_seconds=90))
   try:p.wait(timeout=15)
   except subprocess.TimeoutExpired:pass
   if p.poll() is None and time.monotonic()-start>limit:
    expired=True
    kill=subprocess.run(['taskkill','/PID',str(p.pid),'/T','/F'],capture_output=True,timeout=30,creationflags=getattr(subprocess,'CREATE_NO_WINDOW',0))
    save(case/'host-timeout.json',dict(reason='host wall guard, not functional watchdog81',kill_exit=kill.returncode));p.wait(timeout=30)
  record.update(complete=True,finished=stamp(),actual_native_exit=p.returncode,exit=p.returncode,host_wall_expired=expired,wall_timeout=expired,wall_seconds=time.monotonic()-start)
  save(case/'native-exit.json',record);save(case/'process.json',record);save(case/'heartbeat.json',dict(updated=stamp(),complete=True,process_handle_alive=False,actual_native_exit=p.returncode))
 return record
def audit(case,kind):
 sys.path.insert(0,str(ROOT/'models'));sys.path.insert(0,str(ROOT/'tools/legacy'))
 control=case/'audit-control'
 for name in ['prepare_C42S','prepare_C42','prepare_C38']:
  mod=types.ModuleType(name)
  for k,v in dict(ROOT=ROOT,REPORT=control,read=read,save=save,ref=ref,digest=sha,protect=lambda:None).items():setattr(mod,k,v)
  sys.modules[name]=mod
 if kind=='fragment':return importlib.import_module('audit_C42S').audit(case,publish=False)
 forbid=types.ModuleType('c42_approved_evidence')
 def no_old_exception():raise AssertionError('C46 may not borrow old tool-exit exceptions')
 forbid.approved_EQ_evidence=no_old_exception;sys.modules['c42_approved_evidence']=forbid
 save(control/'latest-rtl.json',read(case/'result.json'))
 return importlib.import_module('check_C42').check('rtl')
def simulate(out,env,kind):
 case=out/kind;case.mkdir(exist_ok=False)
 top='c42s_system' if kind=='fragment' else 'c42_system'
 files=[ROOT/n for n in (ROOT/'compile.f').read_text().splitlines() if n]
 assert len(files)==83 and hashlib.sha256(''.join(sha(p) for p in files).encode()).hexdigest()==H
 files += ([ROOT/'tb/fragment'/n for n in ['c42s_system.v','c42s_configuration.v','c42s_application_source.v']] if kind=='fragment' else [ROOT/n for n in ['tb/load/storage_download_model.v','tb/system/c42_system.v','tb/common/tb_watchdog.v']])
 rows=[];compiled=[];relocation=[]
 for p in files:
  q=case/'inputs'/p.relative_to(ROOT);q.parent.mkdir(parents=True,exist_ok=True)
  original=p.read_bytes();actual=original.replace(b'"vectors/',b'"inputs/vectors/') if '/tb/' in p.as_posix() else original;q.write_bytes(actual)
  assert actual==original or actual.replace(b'"inputs/vectors/',b'"vectors/')==original
  rows.append(dict(**ref(q),snapshot=str(q),original=ref(p)));compiled.append(q)
  if actual!=original:relocation.append(dict(original=ref(p),snapshot=ref(q),change='TB literal runtime vector prefix vectors/ -> inputs/vectors/ only'))
 shutil.copytree(ROOT/'vectors',case/'inputs/vectors')
 (case/'compile.f').write_text('\n'.join(p.as_posix() for p in compiled)+'\n')
 save(case/'inputs.json',dict(sources=rows,DUT_hash=H,DUT_files=83,top=top,model='complete RTL, no RTL substitution',clocks_ns=[10,8,8,8],relocation=relocation))
 ini=local_ini(case,env);namespace={};exec((ROOT/'tools/vendor_cleanup.py').read_text(),namespace);cleanup=namespace['cleanup']
 args=''
 if kind=='services':args=' '.join('{' + f'-g{k}={(case/"inputs"/v).as_posix()}' + '}' for k,v in [('APP_DIR','vectors/system/c42'),('CONTROL_DIR','vectors/615a/c34'),('UPLOAD_DIR','vectors/615a/c35'),('DOWNLOAD_DIR','vectors/615a/c36'),('VECTOR_DIR','vectors/tftp/c33')])
 lines=['onerror {puts C46_TOOL_ERROR;quit -force -code 83}',f'transcript file {{{(case/"transcript.log").as_posix()}}}','transcript on','onbreak {}','vlib work','vmap work work']
 lines += [f'vlog -vlog01compat -work work {{{p.as_posix()}}}' for p in compiled]
 lines += [f'vsim -t 1ps -voptargs=+acc=npr+{top} {args} work.{top}','onfinish stop','run 0 ns']+cleanup(top)
 signals=(['rst_n','configured','app_tx_cmd_valid','app_tx_cmd_ready','app_tx_vlid','app_tx_cmd_length','app_tx_valid','app_tx_ready','app_tx_last','app_tx_commit_valid','app_tx_commit_ready','app_rx_desc_valid','app_rx_desc_ready','app_rx_desc_length','app_rx_desc_vl','app_rx_valid','app_rx_ready','app_rx_last','phy_tx_en','phy_b_tx_en','drop_a'] if kind=='fragment' else ['rst_n','init_done','app_tx_cmd_valid','app_tx_cmd_ready','app_tx_vlid','app_tx_cmd_length','app_tx_commit_valid','app_tx_commit_ready','app_rx_desc_valid','app_rx_desc_vl','app_rx_valid','app_rx_ready','app_rx_last','phy_tx_en','phy_b_tx_en','store_tx_valid','store_tx_ready','store_tx_last','store_rx_valid','store_rx_ready','store_rx_last','store_cancel','rtc_success','rtc_transactions','trap_frames'])
 lines += [f'vcd file {{{(case/"key-interfaces.vcd").as_posix()}}}','vcd add '+' '.join('/'+top+'/'+s for s in signals),'run -all']+cleanup(top)
 lines += [f'set failures [examine -radix unsigned -noshowbase /{top}/failures]',f'set done [examine -radix unsigned -noshowbase /{top}/done]',f'set checks [examine -radix unsigned -noshowbase /{top}/checks]','puts "C46_STATUS done=$done failures=$failures checks=$checks"','if {$failures} {quit -force -code 80}','if {!$done || !$checks} {quit -force -code 82}','quit -sim','update idletasks','update','quit -force -code 0']
 script=case/'run.do';script.write_text('\n'.join(lines)+'\n');argv=[env['modelsim'],'-c','-modelsimini',str(case/'modelsim.ini'),'-do','do {'+script.as_posix()+'}']
 save(case/'launch.json',dict(argv=argv,cwd=str(case),sources=rows,parameters=args,local_ini=ref(case/'modelsim.ini'),global_ini=ini,run_do=ref(script),vectors=[ref(p) for p in sorted((case/'inputs/vectors').rglob('*')) if p.is_file()],runner=ref(__file__),DUT_hash=H,scope='new short fullRTL batch shared by three demo scenes, not six independent runs'))
 print('C46_NATIVE_START',kind,str(case),flush=True);r=native(case,argv,int(env['RTL_guard_seconds']))
 log=(case/'console.log').read_text(encoding='utf-8',errors='replace')
 errors=re.findall(r'^.*\*\* (?:Error|Fatal)(?:\s|:|\().*$',log,re.M)
 markers=re.findall(r'(?m)^[ \t]*(?:#[ \t]*)?(C46_TOOL_ERROR)(?:[ \t]+[^\r\n]*)?[ \t]*\r?$',log)
 status=re.findall(r'C46_STATUS done=(\d+) failures=(\d+) checks=(\d+)',log)
 r.update(accepted=r['exit']==0 and not r['wall_timeout'] and not errors and not markers and bool(status) and status[-1][:2]==('1','0'),directory=str(case),status=status[-1] if status else None,tool_errors=errors,executed_error_markers=markers,DUT_hash=H)
 save(case/'result.json',r);assert sha(ini['path'])==ini['sha256'],'Global modelsim.ini changed'
 assert r['accepted'],f'Actual native or HDL check failed: {case}'
 a=audit(case,kind);assert a['accepted'];print('C46_NATIVE_AND_INDEPENDENT_PASS',kind,r['status'],r['wall_seconds'],flush=True)
 return dict(result=ref(case/'result.json'),audit=ref(case/'independent-audit.json'),native_exit=ref(case/'native-exit.json'))
def main():
 p=argparse.ArgumentParser();p.add_argument('--environment',type=Path,default=ROOT/'environment.example.json');p.add_argument('--output',type=Path);p.add_argument('--case',choices=['fragment','services','all'],default='all');p.add_argument('--scene',type=int,choices=range(1,7));a=p.parse_args()
 out=(a.output or ROOT/'runs'/dt.datetime.now().strftime('%Y%m%d-%H%M%S')).resolve();out.mkdir(parents=True,exist_ok=False)
 env=read(a.environment);assert Path(env['modelsim']).is_file() and Path(env['python']).is_file()
 lock=out/'controller.lock';lock.write_text(json.dumps(dict(pid=os.getpid(),started=stamp(),argv=sys.argv)))
 save(out/'controller.json',dict(pid=os.getpid(),started=stamp(),argv=sys.argv,cwd=str(Path.cwd()),runner=ref(__file__),complete=False))
 try:
  version=subprocess.run([env['modelsim'],'-version'],capture_output=True,text=True,timeout=30,creationflags=getattr(subprocess,'CREATE_NO_WINDOW',0))
  save(out/'environment.json',dict(config=ref(a.environment),values=env,python=sys.version,modelsim_version_exit=version.returncode,modelsim_version=version.stdout+version.stderr,pyasn1=importlib.import_module('pyasn1').__version__))
  assert version.returncode==0
  selected=('fragment' if a.scene<=3 else 'services') if a.scene else a.case
  results={kind:simulate(out,env,kind) for kind in (['fragment','services'] if selected=='all' else [selected])}
  save(out/'batch-result.json',dict(accepted=True,finished=stamp(),DUT_hash=H,batches=results,requested_scene=a.scene,shared_executions=len(results),new_complete_EQ=False,new_EDA=False))
  print('C46_SHORT_BATCHES_PASS',str(out),flush=True)
 finally:
  save(out/'controller.json',dict(pid=os.getpid(),finished=stamp(),argv=sys.argv,runner=ref(__file__),complete=True,result_exists=(out/'batch-result.json').exists()))
  lock.unlink()
if __name__=='__main__':main()
