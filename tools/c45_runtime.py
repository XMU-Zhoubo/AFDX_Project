"""C45 native simulation functions; submission CLI is run_simulation.py."""
from pathlib import Path
import argparse,collections,csv,datetime as dt,difflib,hashlib,importlib,json,os,re,shutil,subprocess,sys,time
ROOT=Path(__file__).resolve().parents[1]
sys.dont_write_bytecode=True

def read(p):return json.loads(Path(p).read_text(encoding='utf-8-sig'))

def sha(p):
 h=hashlib.sha256()
 with Path(p).open('rb') as f:
  for b in iter(lambda:f.read(4*1024*1024),b''):h.update(b)
 return h.hexdigest()

def ref(p):
 p=Path(p).resolve();return dict(path=str(p),sha256=sha(p),bytes=p.stat().st_size)

def save(p,x):
 p=Path(p);p.parent.mkdir(parents=True,exist_ok=True);q=p.with_name(p.name+'.writing');q.write_text(json.dumps(x,ensure_ascii=False,indent=2)+'\n',encoding='utf-8');q.replace(p)

def stamp():return dt.datetime.now().astimezone().isoformat()

def cleanup(top):
 # Copy the previously verified function definition, not an old runner import.
 namespace={};exec((ROOT/'tools/vendor_cleanup.py').read_text(),namespace)
 return namespace['cleanup'](top)

def local_ini(case,env):
 base=Path(env['modelsim']).resolve().parents[1]/'modelsim.ini';s=base.read_text(errors='strict');assert 'D:/AFDX_Project' not in s
 lib=s[s.index('[Library]'):s.index('[DefineOptionset]')];entries=[]
 for name,path in re.findall(r'(?m)^([\w]+)\s*=\s*([^;\r\n]+)',lib):
  if name.lower() in ('others','work'):continue
  path=path.strip().replace('$MODEL_TECH',str(Path(env['modelsim']).resolve().parent).replace('\\','/'))
  entries.append(name+' = '+path)
 block='[Library]\n'+'\n'.join(entries)+'\nwork = '+(case/'work').as_posix()+'\nelinx_lib = '+Path(env['official_library']).as_posix()+'\n\n'
 s=s[:s.index('[Library]')]+block+s[s.index('[DefineOptionset]'):]
 (case/'modelsim.ini').write_text(s,encoding='utf-8');return base

def native(argv,case,env,is_eq):
 start=time.monotonic();phase_start=start;phase='configuration' if is_eq else 'RTL';limit=8400 if is_eq else env['RTL_guard_seconds']
 with (case/'console.log').open('wb',buffering=0) as log:
  proc=subprocess.Popen(argv,cwd=case,stdout=log,stderr=subprocess.STDOUT,stdin=subprocess.DEVNULL,creationflags=getattr(subprocess,'CREATE_NO_WINDOW',0),env={**os.environ,'MODELSIM':str(case/'modelsim.ini')})
  record=dict(pid=proc.pid,started=stamp(),argv=argv,cwd=str(case),complete=False,host_guard_seconds=limit,not_DUT_protocol_deadline=True)
  save(case/'process.json',record);last=0;expired=False
  while proc.poll() is None:
   elapsed=time.monotonic()-start;progress={}
   if (case/'simulation-progress.json').exists():
    try:progress=read(case/'simulation-progress.json')
    except (ValueError,OSError):pass
   if is_eq and progress.get('phase')=='business' and phase!='business':phase='business';phase_start=time.monotonic();limit=11400
   if elapsed-last>=30 or last==0:
    save(case/'heartbeat.json',dict(updated=stamp(),native_pid=proc.pid,process_handle_alive=proc.poll() is None,elapsed_seconds=elapsed,phase=phase,phase_seconds=time.monotonic()-phase_start,phase_guard_seconds=limit,simulation=progress,stale_after_seconds=180));last=elapsed
   if time.monotonic()-phase_start>limit:
    expired=True
    # proc still owns the live handle; terminate only this invocation's tree.
    killed=subprocess.run(['taskkill','/PID',str(proc.pid),'/T','/F'],capture_output=True,creationflags=getattr(subprocess,'CREATE_NO_WINDOW',0),timeout=30)
    save(case/'host-timeout.json',dict(phase=phase,guard_seconds=limit,kill_returncode=killed.returncode,reason='Host wall guard, not DUT watchdog81',actual_native_exit_known=False));proc.wait(timeout=30);break
   try:proc.wait(timeout=2)
   except subprocess.TimeoutExpired:pass
  record.update(complete=True,finished=stamp(),exit=84 if expired else proc.returncode,actual_native_exit=proc.returncode,host_wall_expired=expired,wall_seconds=time.monotonic()-start)
  save(case/'process.json',record);save(case/'native-exit.json',record)
  save(case/'heartbeat.json',dict(updated=stamp(),native_pid=proc.pid,process_handle_alive=False,complete=True,
       elapsed_seconds=record['wall_seconds'],phase=phase,actual_native_exit=proc.returncode,host_wall_expired=expired))
 return record

def segment(case,phase):
 fields=['cycles','checks','cases','failures','done','checkpoint_ready','configured','txframes','rxframes','unique'];top='/c42s_system/'
 # The accepted C42S observer runs the time-zero delta before examining TB
 # integers. Elaboration alone leaves initial-block variables as X.
 lines=['onfinish stop','run 0 ns','set previous_cycles -1','while {1} {']
 for k in fields:
  lines.append(f' set {k} [examine -radix unsigned -noshowbase {top}{k}]')
  lines.append(f' if {{![regexp {{^[0-9]+$}} ${k}]}} {{puts "C45_OBSERVER_NONNUMERIC {k}=${k}";quit -force -code 83}}')
 lines+=[' set json [format {"phase":"'+phase+'","cycles":%s,"checks":%s,"cases":%s,"failures":%s,"done":%s,"checkpoint_ready":%s,"configured":%s} $cycles $checks $cases $failures $done $checkpoint_ready $configured]',f' set fd [open {{{(case/"simulation-progress.json").as_posix()}}} w]',' puts $fd [format "%c%s%c" 123 $json 125]',' close $fd',' puts "C45_EQ_PROGRESS '+phase+' cycles=$cycles checks=$checks failures=$failures done=$done configured=$configured"',' flush stdout',' if {$failures} {break}', ' if {$checkpoint_ready} {break}' if phase=='configuration' else ' if {$done} {break}',' if {$cycles == $previous_cycles} {puts C45_UNEXPECTED_STOP;quit -force -code 82}',' set previous_cycles $cycles',' run 20 us','}']
 return lines

def simulate(run,env,kind):
 case=run/kind;case.mkdir(exist_ok=False);is_eq=kind=='eq';unit=kind=='unit';top='c42s_unit' if unit else 'c42s_system'
 shutil.copytree(ROOT/'vectors',case/'vectors')
 ini_base=local_ini(case,env);compiled=[ROOT/x for x in (ROOT/'compile.f').read_text().splitlines() if x]
 if unit:files=[p for p in compiled if p.name in ('payload_buffer.v','message_tx.v','message_rx.v')]+[ROOT/'tb/fragment/c42s_unit.v']
 else:files=([ROOT/'netlist/functional/c42s_application_stats.vo'] if is_eq else compiled)+[ROOT/'tb/fragment'/n for n in ['c42s_system.v','c42s_configuration.v','c42s_application_source.v']]
 assert (not is_eq) or len(files)==4
 rows=[dict(**ref(p),snapshot=str(p)) for p in files];save(case/'inputs.json',dict(sources=rows,top=top,RTL_DUT_compiled=not is_eq,official_library=env['official_library'] if is_eq else None,clocks_ns=[10,8,8,8],shared_cold_initializations=1,old_work_or_checkpoint_imported=False))
 (case/'compile.f').write_text('\n'.join(p.as_posix() for p in files)+'\n')
 lines=['onerror {puts C45_TOOL_ERROR;quit -force -code 83}',f'transcript file {{{(case/"transcript.log").as_posix()}}}','transcript on','onbreak {}','vlib work','vmap work work']
 lines += [f'vlog -vlog01compat -work work {{{p.as_posix()}}}' for p in files]
 params='-gEQ_SHORT=1' if kind=='rtl-representative' else '-gEQ_SHORT=1 -gCHECKPOINT_MODE=1' if is_eq else ''
 library=f'-L {{{Path(env["official_library"]).as_posix()}}} +notimingchecks' if is_eq else ''
 lines += [f'vsim -t 1ps -voptargs=+acc=npr+{top} {params} {library} work.{top}','onfinish stop']+cleanup(top)
 if is_eq:
  lines+=segment(case,'configuration')+cleanup(top)+['if {![examine -radix unsigned -noshowbase /c42s_system/configured] || [examine -radix unsigned -noshowbase /c42s_system/failures]} {quit -force -code 80}',f'checkpoint {{{(case/"new-configured.chk").as_posix()}}}','puts C45_NEW_COLD_INITIALIZATION_COMPLETE', 'force -deposit /c42s_system/resume_go 1']+segment(case,'business')
 else:lines+=['run -all']
 lines+=cleanup(top)+[f'set failures [examine -radix unsigned -noshowbase /{top}/failures]',f'set done [examine -radix unsigned -noshowbase /{top}/done]',f'set checks [examine -radix unsigned -noshowbase /{top}/checks]','puts "C45_STATUS done=$done failures=$failures checks=$checks"','if {$failures} {quit -force -code 80}','if {!$done || !$checks} {quit -force -code 82}','quit -sim','update idletasks','update','quit -force -code 0']
 script=case/'run.do';script.write_text('\n'.join(lines)+'\n')
 argv=[env['modelsim'],'-c','-modelsimini',str(case/'modelsim.ini'),'-do','do {'+script.as_posix()+'}']
 save(case/'launch.json',dict(argv=argv,cwd=str(case),compiled=rows,case=kind,parameters=params,official_ini_source=ref(ini_base),local_ini=ref(case/'modelsim.ini'),runtime_vectors=[ref(p) for p in sorted((case/'vectors').rglob('*')) if p.is_file()],only_declared_sources_and_new_library=True,SDF_loaded=False))
 result=native(argv,case,env,is_eq);text=(case/'console.log').read_text(encoding='utf-8',errors='replace');status=re.findall(r'C45_STATUS done=(\d+) failures=(\d+) checks=(\d+)',text);errors=re.findall(r'^.*\*\* (?:Error|Fatal)(?:\s|:|\().*$',text,re.M)
 result.update(accepted=result['exit']==0 and not result['host_wall_expired'] and not errors and bool(status) and status[-1][:2]==('1','0'),status=status[-1] if status else None,tool_errors=errors,kind=kind,compile_inputs=ref(case/'inputs.json'));save(case/'result.json',result)
 assert sha(ini_base)==read(run/'preflight/result.json')['global_modelsim_ini']['sha256'],'Global modelsim.ini changed'
 assert result['accepted'],f'{kind} failed; see {case}'
 if not unit:
  sys.path.insert(0,str(ROOT/'tools/legacy'));audit=importlib.import_module('audit_C42S');audit.audit(case,publish=False)
 if is_eq:
  assert 'C45_NEW_COLD_INITIALIZATION_COMPLETE' in text and (case/'new-configured.chk').is_file()
  assert re.search(r'Loading (?:elinx_lib\.|.*elinx_lib)',text),'Official model loading not evidenced'
 print('C45_NATIVE_PASS',kind,result['status'],result['wall_seconds'],flush=True);return result

def compare(run):
 rtl=read(run/'rtl-representative/independent-audit.json');eq=read(run/'eq/independent-audit.json')
 fields=['id','VL','length','external','SHA256']
 assert [[x[k] for k in fields] for x in rtl['messages']]==[[x[k] for k in fields] for x in eq['messages']]
 for k in ['TX_fragments','TX_by_network','RX_physical_frames','actual_input_bytes','unique_output_bytes','reassembly','message_CSR','frame_and_MIB_CSR']:assert rtl[k]==eq[k],k
 result=dict(accepted=True,RTL=ref(run/'rtl-representative/independent-audit.json'),EQ=ref(run/'eq/independent-audit.json'),message_fields=fields,actual_fields_compared=['TX/RX','actual-input/unique-output bytes','reassembly fates','context/frame-pool/MIB CSR'],whole_rtl_scope=ref(run/'rtl-full/independent-audit.json'),internal_cycle_equivalence_required=False)
 save(run/'RTL-EQ-comparison.json',result);return result
