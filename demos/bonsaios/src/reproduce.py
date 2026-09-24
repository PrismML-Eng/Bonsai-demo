#!/usr/bin/env python3
"""Generate a browser OS with real Bonsai inference and native Hermes tools."""
import argparse,codecs,fcntl,hashlib,json,os,pty,select,shutil,signal,socket,sqlite3,struct,subprocess,sys,tempfile,termios,threading,time
from pathlib import Path
from run import Capture,ThreadingHTTPServer,config,dump,fetch
from gpu_guard import check_assigned_gpu
ROOT=Path(__file__).resolve().parents[1]
def main():
 ap=argparse.ArgumentParser(description=__doc__)
 ap.add_argument('--config',type=Path,default=ROOT/'config.json')
 ap.add_argument('--output',type=Path,required=True,help='New directory; existing runs are never overwritten')
 ap.add_argument('--feedback',choices=['interactive','scripted','none'],default='interactive')
 ap.add_argument('--prompts',type=Path,default=ROOT/'prompts')
 ap.add_argument('--stages',type=int,default=None,help='Limit number of stages including initial generation')
 ap.add_argument('--model',type=Path,default=ROOT/'.deps/models/Ternary-Bonsai-2-27B-PQ2_0.gguf')
 ap.add_argument('--server',type=Path,default=ROOT/'.deps/runtime/llama-server')
 ap.add_argument('--hermes',type=Path,default=ROOT/'.deps/hermes-agent')
 a=ap.parse_args();cfg_input=json.loads(a.config.read_text());run=a.output.resolve();run.mkdir(parents=True,exist_ok=False)
 model=a.model.resolve();runtime=a.server.resolve();hermes=a.hermes.resolve();prompts=a.prompts.resolve()
 for path in [model,runtime,hermes/'hermes_cli/main.py',prompts/'00.txt',prompts/'AGENTS.txt']:
  if not path.exists():raise SystemExit(f'Missing dependency/input: {path}. Run setup.py first.')
 # Keep generated work outside any repository so its Git metadata cannot leak into the prompt.
 isolation=Path(tempfile.mkdtemp(prefix='bonsaios-'));work=isolation/'work';home=isolation/'hermes';work.mkdir();home.mkdir();(home/'skill-catalog').mkdir()
 (run/'inbox').mkdir();shutil.copy2(prompts/'AGENTS.txt',work/'AGENTS.md');dump(run/'config.json',cfg_input)
 gpu=check_assigned_gpu(run);os.environ['CUDA_VISIBLE_DEVICES']=gpu
 info=subprocess.check_output(['nvidia-smi','-i',gpu,'--query-gpu=name,uuid,driver_version,memory.total','--format=csv'],text=True)
 dump(run/'environment.json',{'python':sys.version,'gpu':info,'hermes_commit':subprocess.check_output(['git','-C',str(hermes),'rev-parse','HEAD'],text=True).strip(),'runtime':subprocess.check_output([str(runtime),'--version'],text=True,stderr=subprocess.STDOUT).strip(),'model':str(model),'feedback_mode':a.feedback,'workspace':str(work),'hermes_home':str(home),'pin_environment':cfg_input.get('pin_environment',False),'note':'Live generation with optional stable environment metadata. No recorded responses, checkpoints or output matching.'})
 with socket.socket() as sock:sock.bind(('127.0.0.1',0));port=sock.getsockname()[1]
 url=f'http://127.0.0.1:{port}'
 servercmd=[str(runtime),'-m',str(model),'--alias',cfg_input['model_alias'],'--host','127.0.0.1','--port',str(port),'--split-mode','none','--main-gpu','0','-ngl','99','-fa','on','-c',str(cfg_input['context_tokens']),'-np','1','-t',str(cfg_input['server_threads']),'-b',str(cfg_input['server_batch']),'-ub',str(cfg_input['server_ubatch']),'--jinja','--reasoning-format','deepseek','--reasoning-budget','-1']
 dump(run/'server-command.json',servercmd)
 server=None;agent=None;proxy=None
 state={'variant':'PQ2_0','budget':cfg_input['reasoning_budget_tokens'],'seed':cfg_input['seed'],'started':time.time(),'status':'loading','stage':0,'workspace':str(work),'run':str(run)}
 def update(**kw):state.update(kw);dump(run/'state.json',state)
 def stop(proc):
  if proc and proc.poll() is None:
   os.killpg(proc.pid,signal.SIGTERM)
   try:proc.wait(timeout=10)
   except subprocess.TimeoutExpired:os.killpg(proc.pid,signal.SIGKILL);proc.wait()
 def start_server(stage):
  nonlocal server
  stop(server);server=subprocess.Popen(servercmd,stdout=(run/f'server-{stage}.log').open('w'),stderr=subprocess.STDOUT,start_new_session=True)
  for _ in range(180):
   if server.poll() is not None:raise RuntimeError('Model server exited; inspect server log')
   try:
    if fetch(url+'/health')['status']=='ok':break
   except Exception:time.sleep(2)
  else:raise TimeoutError('Model load timeout')
  subprocess.run([sys.executable,str(ROOT/'src/verify_budget.py'),url,str(run/f'budget-probe-{stage}.json')],check=True,timeout=150)
 def interrupt(*args):raise KeyboardInterrupt()
 signal.signal(signal.SIGTERM,interrupt);update();print('RUN '+str(run),flush=True)
 try:
  start_server(0)
  proxy=ThreadingHTTPServer(('127.0.0.1',0),Capture);proxy.daemon_threads=True;proxy.upstream=url;proxy.run=run;proxy.counter=0;proxy.phase=0;proxy.lock=threading.Lock();proxy.request_timeout=cfg_input['stage_timeout_seconds'];proxy.compression_mode='current'
  if cfg_input.get('pin_environment',False):
   from environment import EnvironmentPins
   proxy.environment_pins=EnvironmentPins(work,home)
   shutil.copy2(ROOT/'repro/environment.json',run/'environment-pins.json')
  cfg=config(f'http://127.0.0.1:{proxy.server_port}/v1',work,cfg_input['reasoning_effort'],cfg_input['seed'],cfg_input['context_tokens'],cfg_input['stage_turns'][0])
  keys=['temperature','top_p','top_k','min_p','presence_penalty','repeat_penalty','frequency_penalty','seed','reasoning_effort','reasoning_budget_tokens','max_tokens']
  cfg['providers']['bonsai']['extra_body'].update({k:cfg_input[k] for k in keys});cfg['model']['default']=cfg_input['model_alias'];cfg['model']['reasoning_echo']=False;cfg['display']={'tool_progress':'all'};cfg['compression']=cfg_input['compression']
  dump(home/'config.yaml',cfg);dump(run/'hermes-config.json',cfg)
  threading.Thread(target=proxy.serve_forever,daemon=True).start()
  env=dict(os.environ,HERMES_HOME=str(home),TERMINAL_CWD=str(work),HERMES_BUNDLED_SKILLS=str(home/'skill-catalog'),HERMES_OPTIONAL_SKILLS=str(home/'skill-catalog'),BONSAIOS_HERMES=str(hermes),BONSAIOS_PIN_ENVIRONMENT='1' if cfg_input.get('pin_environment',False) else '0',PYTHONPATH=str(hermes),TERM='xterm-256color',COLUMNS='110',LINES='32',PYTHONUNBUFFERED='1')
  env['PATH']=str(Path(sys.executable).parent)+os.pathsep+env.get('PATH','')
  session=None;prompt=(prompts/'00.txt').read_text().strip();count=a.stages or len(cfg_input['stage_turns']);count=1 if a.feedback=='none' else count
  for stage in range(count):
   if stage in cfg_input['server_restarts_before_stages']:start_server(stage)
   if stage==5:shutil.copy2(ROOT/'assets/bonsai-logo.svg',work/'bonsai-logo.svg')
   proxy.phase=stage;folder=run/f'stage-{stage}';folder.mkdir();(folder/'prompt.txt').write_text(prompt+'\n')
   turns=cfg_input['stage_turns'][min(stage,len(cfg_input['stage_turns'])-1)];cfg['agent']['max_turns']=turns;dump(home/'config.yaml',cfg)
   cmd=[sys.executable,str(ROOT/'src/cli_entry.py'),'--cli','chat','--in',str(work),'--provider','bonsai','-m',cfg_input['model_alias'],'--reasoning',cfg_input['reasoning_effort'],'-t','file','--max-turns',str(turns),'--oneshot','--query-file',str(folder/'prompt.txt')]
   if session:cmd+=['--resume',session]
   dump(folder/'command.json',cmd);update(stage=stage,status='generating',session_id=session,prompt=prompt)
   print(f'\nStage {stage}: max {turns} turns\n{prompt}\n',flush=True)
   master,slave=pty.openpty();fcntl.ioctl(slave,termios.TIOCSWINSZ,struct.pack('HHHH',32,110,0,0));started=time.monotonic()
   timeline=(folder/'terminal.cast').open('w');timeline.write(json.dumps({'version':2,'width':110,'height':32,'timestamp':int(time.time()),'env':{'TERM':'xterm-256color'},'title':'Bonsai through Hermes'})+'\n')
   raw=(folder/'terminal.ansi').open('wb');decoder=codecs.getincrementaldecoder('utf-8')('replace')
   agent=subprocess.Popen(cmd,cwd=work,env=env,stdin=slave,stdout=slave,stderr=slave,start_new_session=True);os.close(slave);timed_out=False;last_hash=None;snap=0;(folder/'snapshots').mkdir()
   while True:
    if select.select([master],[],[],.25)[0]:
     try:data=os.read(master,65536)
     except OSError:data=b''
     if data:
      raw.write(data);raw.flush();text=decoder.decode(data);sys.stdout.write(text);sys.stdout.flush();timeline.write(json.dumps([time.monotonic()-started,'o',text])+'\n');timeline.flush()
     elif agent.poll() is not None:break
    if (work/'os.html').exists():
     data=(work/'os.html').read_bytes();h=hashlib.sha256(data).hexdigest()
     if h!=last_hash:
      snap+=1;last_hash=h;(folder/f'snapshots/{snap:03d}.html').write_bytes(data)
    if time.monotonic()-started>cfg_input['stage_timeout_seconds']:timed_out=True;stop(agent);break
    if agent.poll() is not None and not select.select([master],[],[],0)[0]:break
   raw.close();timeline.close();os.close(master);code=agent.wait(timeout=15);agent=None
   shutil.copytree(work,folder/'artifacts');shutil.copytree(home,folder/'home')
   if (work/'os.html').exists():shutil.copy2(work/'os.html',run/'os.html')
   db=sqlite3.connect(home/'state.db');db.row_factory=sqlite3.Row
   rows=[dict(r) for r in db.execute('SELECT id,parent_session_id,message_count,tool_call_count,api_call_count,end_reason,cwd FROM sessions ORDER BY started_at DESC')];db.close()
   if not rows:raise RuntimeError('No Hermes session persisted')
   session=rows[0]['id'];dump(folder/'result.json',{'exit_code':code,'timed_out':timed_out,'wall_seconds':time.monotonic()-started,'sessions':rows,'active_session':session,'artifact_sha256':last_hash,'requests_total':proxy.counter})
   # Hermes may return 1 after exhausting turns while delivering a valid artifact.
   # Log this result and continue feedback; do not compare to a reference trajectory.
   if timed_out:raise TimeoutError('Stage timeout; generated files and trace preserved')
   if stage==count-1:break
   if a.feedback=='scripted':prompt=(prompts/f'{stage+1:02d}.txt').read_text().strip()
   else:
    feedback=run/'inbox'/f'feedback-{stage+1}.txt';update(status='awaiting_feedback',session_id=session,next_feedback_file=str(feedback))
    print(f'\nInspect {run / "os.html"}. Submit feedback with:\n{sys.executable} {ROOT / "src/feedback.py"} {run} --text "Your feedback"\nOr create {run / "inbox/STOP"} to finish.\n',flush=True)
    deadline=time.monotonic()+cfg_input['feedback_timeout_seconds']
    while not feedback.exists() and not (run/'inbox/STOP').exists():
     if time.monotonic()>deadline:raise TimeoutError('Feedback wait ended; artifact and session preserved')
     time.sleep(1)
    if (run/'inbox/STOP').exists():break
    prompt=feedback.read_text().strip()
   if not prompt:raise ValueError('Feedback must not be empty')
  update(status='complete',finished=time.time(),artifact_exists=(run/'os.html').exists())
 except BaseException as exc:update(status='error',error=repr(exc),finished=time.time());raise
 finally:
  stop(agent)
  if proxy:proxy.shutdown()
  stop(server)
  shutil.copytree(home,run/'home',dirs_exist_ok=True);shutil.copytree(work,run/'work',dirs_exist_ok=True)
  subprocess.run([sys.executable,str(ROOT/'src/metrics.py'),str(run)],check=False)
  # Original live paths are logged; the complete persistent copies are under output/.
  shutil.rmtree(isolation)
if __name__=='__main__':main()
