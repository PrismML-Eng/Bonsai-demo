#!/usr/bin/env python3
"""Install the pinned demo dependencies. Requires Python 3.11+, uv, git, Linux x86_64."""
import argparse,hashlib,json,os,platform,shutil,subprocess,tarfile,urllib.request
from pathlib import Path
ROOT=Path(__file__).resolve().parent
PINS=json.loads((ROOT/'repro/versions.json').read_text())
def command(*args):subprocess.run([str(a) for a in args],check=True)
def sha(path):
 with path.open('rb') as f:return hashlib.file_digest(f,'sha256').hexdigest()
def download(url,dest,expected):
 if dest.exists() and sha(dest)==expected:return
 dest.parent.mkdir(parents=True,exist_ok=True);part=dest.with_suffix(dest.suffix+'.part')
 print(f'Downloading {dest.name}',flush=True)
 with urllib.request.urlopen(url,timeout=300) as response,part.open('wb') as out:shutil.copyfileobj(response,out,8*1024*1024)
 if sha(part)!=expected:raise RuntimeError(f'Download checksum mismatch: {dest.name}')
 part.replace(dest)
def main():
 ap=argparse.ArgumentParser(description=__doc__);ap.add_argument('--model-path',type=Path,help='Use an existing matching GGUF');ap.add_argument('--runtime-dir',type=Path,help='Use existing matching runtime binaries');ap.add_argument('--hermes-source',type=Path,help='Clone a local checkout instead of downloading it');a=ap.parse_args()
 if platform.system()!='Linux' or platform.machine()!='x86_64':ap.error('Bundled runtime is Linux x86_64 CUDA 12.8. Adapt versions/setup for other platforms.')
 uv=shutil.which('uv')
 if not uv:ap.error('Install uv first: https://docs.astral.sh/uv/getting-started/installation/')
 dep=ROOT/'.deps';dep.mkdir(exist_ok=True);hermes=dep/'hermes-agent'
 if not hermes.exists():
  command('git','clone','--no-checkout',a.hermes_source.resolve() if a.hermes_source else PINS['hermes_repository'],hermes)
  command('git','-C',hermes,'remote','set-url','origin',PINS['hermes_repository'])
 if subprocess.run(['git','-C',str(hermes),'cat-file','-e',PINS['hermes_commit']+'^{commit}'],capture_output=True).returncode:
  command('git','-C',hermes,'fetch','origin',PINS['hermes_commit'])
 if subprocess.check_output(['git','-C',str(hermes),'status','--porcelain','--untracked-files=no'],text=True) and (hermes/'pyproject.toml').exists():raise RuntimeError('Existing Hermes checkout has changes; preserve them before setup')
 command('git','-C',hermes,'checkout','--detach',PINS['hermes_commit'])
 venv=ROOT/'.venv'
 if not venv.exists():command(uv,'venv','--python',PINS['python'],venv)
 py=venv/'bin/python';actual=subprocess.check_output([str(py),'-c','import platform;print(platform.python_version())'],text=True).strip()
 if actual!=PINS['python']:raise RuntimeError('Existing .venv has the wrong Python version')
 command(uv,'pip','install','--python',py,'--no-deps','-r',ROOT/'repro/requirements.lock')
 command(uv,'pip','install','--python',py,'--no-deps','setuptools==83.0.0','wheel==0.45.1')
 command(uv,'pip','install','--python',py,'--no-deps','--no-build-isolation','-e',hermes)
 model=dep/'models'/PINS['model_file'];model.parent.mkdir(exist_ok=True)
 if a.model_path:
  source=a.model_path.resolve()
  if sha(source)!=PINS['model_sha256']:raise RuntimeError('Existing model checksum mismatch')
  if not model.exists():model.symlink_to(source)
  elif sha(model)!=PINS['model_sha256']:raise RuntimeError('Installed model checksum mismatch')
 else:download('https://huggingface.co/'+PINS['model_repository']+'/resolve/'+PINS['model_revision']+'/'+PINS['model_file'],model,PINS['model_sha256'])
 runtime=dep/'runtime'
 if a.runtime_dir:
  source=a.runtime_dir.resolve()
  for name,expected in PINS['runtime_files'].items():
   if sha(source/name)!=expected:raise RuntimeError(f'Existing runtime checksum mismatch: {name}')
  if not runtime.exists():runtime.symlink_to(source,target_is_directory=True)
 else:
  archive=dep/'runtime.tar.gz';download(PINS['runtime_url'],archive,PINS['runtime_archive_sha256'])
  if not runtime.exists():
   unpack=dep/'runtime-unpack';unpack.mkdir(exist_ok=True)
   with tarfile.open(archive) as tar:tar.extractall(unpack,filter='data')
   binary=next(unpack.rglob('llama-server'));shutil.move(binary.parent,runtime)
 for name,expected in PINS['runtime_files'].items():
  if sha(runtime/name)!=expected:raise RuntimeError(f'Runtime checksum mismatch: {name}')
 print('\nSetup complete. From the repository root run:\n./scripts/run_bonsaios.sh --output bonsaios-runs/my-os\n',flush=True)
if __name__=='__main__':main()
