"""C45 code-only submission entry; all outputs are newly generated per run."""
from pathlib import Path
import argparse
import ast
import hashlib
import importlib.metadata
import json
import os
import re
import shutil
import subprocess
import sys

sys.dont_write_bytecode = True
if not __debug__:
    raise RuntimeError('Run without -O: the independent checkers use assertions.')
sys.path.insert(0, str(Path(__file__).resolve().parent))
import c45_runtime as runtime

ROOT = runtime.ROOT
DUT_HASH = 'c6af30620c6ac1c4358ed136e12b683e5bbd109d2ce18dddd3ee3c19fde901ed'


def inputs_check():
    manifest = runtime.read(ROOT / 'simulation-inputs.json')
    for item in manifest['files']:
        path = (ROOT / item['relative']).resolve()
        if not path.is_relative_to(ROOT) or runtime.sha(path) != item['sha256']:
            raise RuntimeError('Simulation input changed: ' + item['relative'])
    sources = [ROOT / n for n in (ROOT / 'compile.f').read_text(encoding='utf-8').splitlines() if n]
    combined = hashlib.sha256(''.join(runtime.sha(p) for p in sources).encode()).hexdigest()
    if len(sources) != 83 or combined != DUT_HASH:
        raise RuntimeError('This package requires the frozen C45 83-source DUT.')
    tops = sum(len(re.findall(r'(?m)^\s*module\s+AFDX_top\b', p.read_text(encoding='utf-8'))) for p in sources)
    if tops != 1:
        raise RuntimeError('compile.f must contain exactly one AFDX_top.')
    return manifest


def preflight(run, env, require_eq):
    manifest = inputs_check()
    out = run / 'preflight'
    out.mkdir()
    simulator = Path(env['modelsim']).resolve()
    if not simulator.is_file():
        raise RuntimeError('Set modelsim to your installed vsim.exe in environment.local.json.')
    version = subprocess.run([str(simulator), '-version'], capture_output=True, timeout=30,
                             creationflags=getattr(subprocess, 'CREATE_NO_WINDOW', 0))
    text = (version.stdout + version.stderr).decode('utf-8', errors='replace')
    if version.returncode != 0 or '2020.4' not in text:
        raise RuntimeError('Expected ModelSim SE-64 2020.4: ' + text)
    if shutil.disk_usage(run).free < int(env['minimum_free_bytes']):
        raise RuntimeError('Insufficient free space; see minimum_free_bytes.')
    for path in (ROOT / 'tools').rglob('*.py'):
        ast.parse(path.read_text(encoding='utf-8'), filename=str(path))
    for path in (ROOT / 'tb').rglob('*.v'):
        source = path.read_text(encoding='utf-8')
        for name in re.findall(r'\$readmem[hb]\(\s*"([^"]+)"', source):
            if not (ROOT / name).is_file():
                raise RuntimeError('Missing test vector: ' + name)
    library_files = 0
    if require_eq:
        library = Path(env['official_library'])
        for item in runtime.read(ROOT / 'external-models.json')['files']:
            if runtime.sha(library / item['relative']) != item['sha256']:
                raise RuntimeError('Official model differs: ' + item['relative'])
            library_files += 1
    result = dict(accepted=True, DUT_files=83, DUT_hash=DUT_HASH,
                  input_files=len(manifest['files']), modelsim_version=text.strip(),
                  global_modelsim_ini=runtime.ref(simulator.parents[1] / 'modelsim.ini'),
                  official_library_verified=require_eq, official_model_files=library_files,
                  historical_evidence_required=False, HDL_executed=False)
    runtime.save(out / 'result.json', result)
    print('SUBMISSION_PREFLIGHT_PASS', len(manifest['files']), flush=True)
    return result


def services(run, env_path):
    argv = [sys.executable, '-I', '-B', '-X', 'utf8', str(ROOT / 'tools/run_services.py'),
            '--environment', str(env_path), '--output', str(run / 'management'), '--case', 'services']
    result = subprocess.run(argv, cwd=ROOT)
    if result.returncode != 0:
        raise RuntimeError('Management simulation/checker failed: ' + str(result.returncode))
    result_file = run / 'management/batch-result.json'
    if not runtime.read(result_file)['accepted']:
        raise RuntimeError('Management batch not accepted.')
    return runtime.ref(result_file)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--environment', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--cases', choices=['preflight', 'quick', 'services', 'eq', 'all'], default='quick')
    args = parser.parse_args()
    run = args.output.resolve()
    env_path = args.environment.resolve()
    env = runtime.read(env_path)
    checked_paths = [ROOT, run, env_path, Path(env['modelsim']), Path(env['official_library'])]
    if any(not str(path).isascii() for path in checked_paths):
        raise RuntimeError('ModelSim 2020.4 cannot reliably open non-ASCII paths. Copy the code package '
                           'to an English path such as D:/AFDX_C45_Run and use ASCII tool/output paths.')
    if not run.is_relative_to(ROOT / 'runs') or run == ROOT / 'runs':
        raise RuntimeError('Use a new output directory below this copy of the package: runs/<name>.')
    if args.cases == 'eq':
        if not runtime.read(run / 'quick-result.json')['accepted']:
            raise RuntimeError('Run quick first, then use the same --output for eq.')
    else:
        run.mkdir(parents=True, exist_ok=False)
    lock = run / 'controller.lock'
    fd = os.open(lock, os.O_CREAT | os.O_EXCL | os.O_WRONLY)
    os.write(fd, json.dumps(dict(pid=os.getpid(), started=runtime.stamp())).encode())
    os.close(fd)
    # Legacy independent auditor imports this explicitly; it never reads old runs.
    os.environ['C45_OUTPUT'] = str(run / 'auditor-control')
    try:
        inputs_check()
        if args.cases != 'eq':
            preflight(run, env, args.cases in ('preflight', 'all'))
        else:
            # Check the official models at the point they are actually needed.
            for item in runtime.read(ROOT / 'external-models.json')['files']:
                if runtime.sha(Path(env['official_library']) / item['relative']) != item['sha256']:
                    raise RuntimeError('Official model differs: ' + item['relative'])
        if args.cases in ('quick', 'all'):
            for kind in ['unit', 'rtl-full', 'rtl-representative']:
                runtime.simulate(run, env, kind)
            runtime.save(run / 'quick-result.json', dict(accepted=True, DUT_hash=DUT_HASH,
                         finished=runtime.stamp(), new_complete_EQ_done=False,
                         historical_metrics_recomputed=False))
        management = None
        if args.cases in ('services', 'all'):
            importlib.metadata.version('pyasn1')
            management = services(run, env_path)
        if args.cases in ('eq', 'all'):
            runtime.simulate(run, env, 'eq')
            runtime.compare(run)
        inputs_check()
        runtime.save(run / ('eq-suite-result.json' if args.cases == 'eq' else 'suite-result.json'),
                     dict(accepted=True, cases=args.cases, finished=runtime.stamp(), DUT_hash=DUT_HASH,
                          management=management, historical_evidence_required=False,
                          full_functional_EQ_run=args.cases in ('eq', 'all'), physical_timing_passed=False))
        print('SUBMISSION_SIMULATION_PASS', args.cases, str(run), flush=True)
    except BaseException as error:
        runtime.save(run / 'failure.json', dict(accepted=False, error=repr(error), finished=runtime.stamp()))
        raise
    finally:
        lock.unlink()


if __name__ == '__main__':
    main()
