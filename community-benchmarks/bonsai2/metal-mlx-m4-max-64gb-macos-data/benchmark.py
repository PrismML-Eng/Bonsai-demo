#!/usr/bin/env python3
"""Local-only, sequential 3-backend benchmark. No real tool execution."""
import argparse, base64, ctypes, hashlib, json, os, pathlib, re, signal
import socket, subprocess, threading, time, urllib.request, urllib.error
import psutil
from PIL import Image, ImageDraw, ImageFont

ROOT = pathlib.Path(__file__).resolve().parent
PY = ROOT / 'venv/bin/python'
MODEL = 'qwen3.8:27b-mlx'
ITEMS = [dict(name='장미 레드나오미', quantity=3, unit='단'),
         dict(name='리시안셔스 보라', quantity=12, unit='대'),
         dict(name='카네이션 핑크', quantity=2, unit='단'),
         dict(name='유칼립투스', quantity=5, unit='대')]
SYSTEM = '꽃 도매 자료에서 품명, 수량, 단위를 정확히 추출하세요. 입력에 없는 값을 만들지 마세요. 생각 과정이나 설명을 쓰지 마세요. 일반 답변은 {"items":[{"name":"품명","quantity":숫자,"unit":"단 또는 대"}]} JSON만 출력하세요. 도구가 제공되면 extract_order를 정확히 한 번 호출하세요.'
CONTEXT = '\n'.join(f'참고 규칙 {i:02d}: 품명은 원문대로, 수량은 숫자로, 단과 대를 구별하며 환산하지 않는다.' for i in range(1, 13))
ORDER = '주문 확정: 장미 레드나오미 3단, 리시안셔스 보라 12대, 카네이션 핑크 2단, 유칼립투스 5대. 취소한 해바라기 9대는 제외해 주세요.'
TOOLS = [{'type':'function','function':{'name':'extract_order','description':'주문 추출 결과를 모의 검수에 전달한다. 실제 주문을 생성하지 않는다.','parameters':{'type':'object','properties':{'items':{'type':'array','items':{'type':'object','properties':{'name':{'type':'string'},'quantity':{'type':'number'},'unit':{'type':'string','enum':['단','대']}},'required':['name','quantity','unit'],'additionalProperties':False}}},'required':['items'],'additionalProperties':False}}}]
MODELS = {
 'ollama': {'port':19434, 'kind':'ollama','model':MODEL},
 'pq2': {'port':19435,'kind':'openai','model':'bonsai-pq2'},
 'mlx2': {'port':19436,'kind':'openai','model':str(ROOT/'models/Ternary-Bonsai-2-27B-mlx-2bit')},
}

def write_json(p, d):
 p.parent.mkdir(parents=True,exist_ok=True); p.write_text(json.dumps(d,ensure_ascii=False,indent=2))

def fixture():
 p=ROOT/'fixtures/statement.png'; p.parent.mkdir(exist_ok=True)
 im=Image.new('RGB',(1200,760),'white'); draw=ImageDraw.Draw(im)
 font='/System/Library/Fonts/AppleSDGothicNeo.ttc'
 title=ImageFont.truetype(font,48); body=ImageFont.truetype(font,38)
 draw.text((80,45),'거래명세서 — 합성 검증용',font=title,fill='black')
 draw.text((80,115),'실제 고객·거래 정보 없음',font=body,fill='black')
 xs=[80,750,970]; ys=[220,310,400,490,580]
 for y in [200,285,375,465,555,645]:draw.line((65,y,1135,y),fill='black',width=2)
 for x in [65,720,940,1135]:draw.line((x,200,x,645),fill='black',width=2)
 for x,t in zip(xs,['품명','수량','단위']):draw.text((x,ys[0]),t,font=body,fill='black')
 for y,it in zip(ys[1:],ITEMS):
  for x,t in zip(xs,[it['name'],str(it['quantity']),it['unit']]):draw.text((x,y),t,font=body,fill='black')
 im.save(p)
 write_json(ROOT/'fixtures/manifest.json',{'items':ITEMS,'system':SYSTEM,'context':CONTEXT,'order':ORDER,'tools':TOOLS,'image_sha256':hashlib.sha256(p.read_bytes()).hexdigest(),'image_size':[1200,760],'synthetic':True,'max_context':4096,'max_output_tokens':512,'thinking':False,'temperature':0,'seed':42})
 return p

LIB=ctypes.CDLL('/usr/lib/libproc.dylib')
LIB.proc_pid_rusage.argtypes=[ctypes.c_int,ctypes.c_int,ctypes.c_void_p]
def footprint(pid):
 # rusage_info_v2: uuid[16] followed by UInt64 fields; phys_footprint index 7.
 buf=ctypes.create_string_buffer(512)
 if LIB.proc_pid_rusage(pid,2,ctypes.byref(buf)) != 0:return 0
 return ctypes.c_uint64.from_buffer(buf,16+7*8).value

def memory(pid):
 procs=[]
 try:
  p=psutil.Process(pid); procs=[p]+p.children(recursive=True)
 except psutil.Error:pass
 rss=phys=0
 for p in procs:
  try:rss+=p.memory_info().rss;phys+=footprint(p.pid)
  except psutil.Error:pass
 sw=psutil.swap_memory()
 return {'t':time.time(),'rss_bytes':rss,'physical_footprint_bytes':phys,'system_swap_used_bytes':sw.used,'system_swap_total_bytes':sw.total,'system_available_bytes':psutil.virtual_memory().available,'pids':[p.pid for p in procs]}

class Monitor:
 def __init__(self,pid,path):self.pid=pid;self.path=path;self.rows=[];self.stopflag=threading.Event()
 def start(self):
  self.thread=threading.Thread(target=self.loop,daemon=True);self.thread.start();return self
 def loop(self):
  with self.path.open('w') as f:
   while not self.stopflag.is_set():
    d=memory(self.pid);self.rows.append(d);f.write(json.dumps(d)+'\n');f.flush();self.stopflag.wait(.5)
 def stop(self):self.stopflag.set();self.thread.join()
 def summary(self):
  rows=self.rows or [memory(self.pid)]
  return {'samples':len(rows),'max_rss_bytes':max(x['rss_bytes'] for x in rows),'max_physical_footprint_bytes':max(x['physical_footprint_bytes'] for x in rows),'swap_start_bytes':rows[0]['system_swap_used_bytes'],'swap_peak_bytes':max(x['system_swap_used_bytes'] for x in rows),'swap_end_bytes':rows[-1]['system_swap_used_bytes'],'swap_peak_delta_bytes':max(x['system_swap_used_bytes'] for x in rows)-rows[0]['system_swap_used_bytes'],'min_system_available_bytes':min(x['system_available_bytes'] for x in rows)}

def request(url,payload=None,timeout=600):
 req=urllib.request.Request(url,data=json.dumps(payload,ensure_ascii=False).encode() if payload is not None else None,headers={'Content-Type':'application/json'})
 return urllib.request.urlopen(req,timeout=timeout)

def commands(key):
 env=dict(os.environ);env['HF_HOME']=str(ROOT/'hf-cache');env['TOKENIZERS_PARALLELISM']='false'
 if key=='ollama':
  env.update(OLLAMA_HOST='127.0.0.1:19434',OLLAMA_MODELS=os.environ.get('OLLAMA_MODELS',str(pathlib.Path.home()/'.ollama/models')),OLLAMA_KEEP_ALIVE='-1',OLLAMA_NUM_PARALLEL='1',OLLAMA_MAX_LOADED_MODELS='1',OLLAMA_LOAD_TIMEOUT='10m')
  cmd=['/Applications/Ollama.app/Contents/Resources/ollama','serve']
 elif key=='pq2':
  cmd=[str(ROOT/'Bonsai-demo/bin/mac/llama-server'),'-m',str(ROOT/'models/Ternary-Bonsai-2-27B-gguf/Ternary-Bonsai-2-27B-PQ2_0.gguf'),'--mmproj',str(ROOT/'models/Ternary-Bonsai-2-27B-gguf/Ternary-Bonsai-2-27B-mmproj-BF16.gguf'),'--host','127.0.0.1','--port','19435','-ngl','99','-fa','on','-c','4096','-np','1','--jinja','--reasoning','off','--chat-template-kwargs','{"enable_thinking":false}','--cache-type-k','f16','--cache-type-v','f16','--cache-prompt','--cache-ram','0','--image-max-tokens','1024','--seed','42']
 else:
  cmd=[str(PY),'-m','mlx_vlm.server','--model',MODELS[key]['model'],'--host','127.0.0.1','--port','19436','--max-tokens','512','--max-kv-size','4096','--vision-cache-size','20','--max-num-seqs','1']
 return cmd,env

def payload(key,case,image):
 user=CONTEXT+'\n\n'+(ORDER if case!='image' else '이미지의 거래명세서에서 모든 행의 품명, 수량, 단위를 추출하세요.')
 msgs=[{'role':'system','content':SYSTEM},{'role':'user','content':user}]
 tool=case=='tool'
 if key=='ollama':
  if case=='image':msgs[-1]['images']=[base64.b64encode(image.read_bytes()).decode()]
  d={'model':MODEL,'messages':msgs,'stream':True,'think':False,'keep_alive':-1,'options':{'num_ctx':4096,'num_predict':512,'temperature':0,'seed':42,'top_k':20,'top_p':.95,'min_p':0,'repeat_penalty':1}}
 else:
  if case=='image':msgs[-1]['content']=[{'type':'text','text':user},{'type':'image_url','image_url':{'url':'data:image/png;base64,'+base64.b64encode(image.read_bytes()).decode()}}]
  d={'model':MODELS[key]['model'],'messages':msgs,'stream':True,'stream_options':{'include_usage':True},'max_tokens':512,'temperature':0,'seed':42,'top_p':.95,'top_k':20,'min_p':0,'repeat_penalty':1,'enable_thinking':False,'chat_template_kwargs':{'enable_thinking':False},'cache_prompt':True}
 if tool:d['tools']=TOOLS
 return d

def score(text,tools,finish,thinking,case):
 parsed=None;err=None;native=False;raw_json=True
 try:
  if case=='tool':
   native=len(tools)==1 and tools[0].get('function',{}).get('name')=='extract_order'
   args=tools[0]['function']['arguments'] if native else None
   parsed=json.loads(args) if isinstance(args,str) else args
  else:parsed=json.loads(text)
 except (ValueError,KeyError,IndexError,TypeError) as e:
  err=str(e);raw_json=False
  if case!='tool':
   fenced=re.fullmatch(r'\s*```(?:json)?\s*(.*?)\s*```\s*',text,flags=re.S)
   if fenced:
    try:parsed=json.loads(fenced.group(1))
    except ValueError:pass
 schema_ok=isinstance(parsed,dict) and set(parsed)=={'items'} and isinstance(parsed['items'],list) and all(isinstance(x,dict) and set(x)=={'name','quantity','unit'} and isinstance(x['name'],str) and isinstance(x['quantity'],(int,float)) and not isinstance(x['quantity'],bool) and x['unit'] in ['단','대'] for x in parsed['items'])
 strict=raw_json and schema_ok
 items=parsed.get('items',[]) if isinstance(parsed,dict) else []
 correct=sum(1 for expected in ITEMS if expected in items)
 field_correct={k:sum(any(it.get('name')==ex['name'] and it.get(k)==ex[k] for it in items if isinstance(it,dict)) for ex in ITEMS) for k in ['name','quantity','unit']}
 # Exact correctness includes extras and duplicate rows; field recall alone does not.
 exact=schema_ok and len(items)==len(ITEMS) and correct==len(ITEMS)
 grams=[text[i:i+100] for i in range(0,max(0,len(text)-99),25)]
 repetitive=any(grams.count(g)>=3 for g in set(grams)) or (len(items)>0 and len({json.dumps(x,sort_keys=True,ensure_ascii=False) for x in items})<len(items))
 return {'strict_json_or_arguments':strict,'native_tool_call':native if case=='tool' else None,'exact_items':exact,'correct_rows':correct,'expected_rows':len(ITEMS),'field_correct':field_correct,'extra_or_missing_rows':len(items)!=len(ITEMS),'repetition':repetitive,'incomplete':finish in ['length','max_tokens'] or (parsed is None and text.lstrip().startswith(('{','[','```'))),'thinking_observed':bool(thinking),'parse_error':err,'mock_tool_execution':{'executed':False,'would_accept':native and strict and exact} if case=='tool' else None}

def run_request(key,case,rep,pid,image):
 out=ROOT/'results'/key/f'{case}-{rep}';out.mkdir(parents=True,exist_ok=True)
 d=payload(key,case,image);write_json(out/'request.json',d)
 m=Monitor(pid,out/'memory.jsonl').start();start=time.perf_counter();ttft=None;first_answer=None;content='';thinking='';calls={};events=[];meta={};finish=None;error=None
 try:
  url=f'http://127.0.0.1:{MODELS[key]["port"]}'+('/api/chat' if key=='ollama' else '/v1/chat/completions')
  with request(url,d) as r:
   for raw in r:
    line=raw.decode().strip()
    if not line or line.startswith('event:'):continue
    if line.startswith('data:'):line=line[5:].strip()
    if line=='[DONE]':break
    ev=json.loads(line);elapsed=time.perf_counter()-start;events.append({'elapsed_s':elapsed,'data':ev})
    if key=='ollama':
     msg=ev.get('message') or {};delta=msg.get('content') or '';thought=msg.get('thinking') or '';toolparts=msg.get('tool_calls') or []
     for i,t in enumerate(toolparts):calls[i]=t
     if ev.get('done'):meta=ev;finish=ev.get('done_reason')
    else:
     if ev.get('error'):raise RuntimeError('backend stream error: '+str(ev['error']))
     choices=ev.get('choices') or [];ch=choices[0] if choices else {};msg=ch.get('delta') or {};delta=msg.get('content') or '';thought=msg.get('reasoning_content') or msg.get('reasoning') or '';toolparts=msg.get('tool_calls') or []
     for t in toolparts:
      i=t.get('index',0);c=calls.setdefault(i,{'type':'function','function':{'name':'','arguments':''}})
      if t.get('id'):c['id']=t['id']
      f=t.get('function') or {};c['function']['name']+=f.get('name') or '';c['function']['arguments']+=f.get('arguments') or ''
     if ch.get('finish_reason'):finish=ch['finish_reason']
     if ev.get('usage'):meta['usage']=ev['usage']
     if ev.get('timings'):meta['timings']=ev['timings']
    if (delta or thought or toolparts) and ttft is None:ttft=elapsed
    if (delta or toolparts) and first_answer is None:first_answer=elapsed
    content+=delta;thinking+=thought
 except urllib.error.HTTPError as e:
  error=f'HTTP {e.code}: {e.read().decode(errors="replace")[:4000]}'
 except Exception as e:error=f'{type(e).__name__}: {e}'
 total=time.perf_counter()-start;m.stop();tools=list(calls.values())
 if key=='ollama':
  inp=meta.get('prompt_eval_count');gen=meta.get('eval_count');pt=meta.get('prompt_eval_duration',0)/1e9;gt=meta.get('eval_duration',0)/1e9
  speeds={'input_tok_s':inp/pt if inp and pt else None,'generation_tok_s':gen/gt if gen and gt else None,'input_tokens':inp,'output_tokens':gen,'input_seconds':pt,'generation_seconds':gt,'load_s':meta.get('load_duration',0)/1e9,'cached_tokens':None}
 else:
  t=meta.get('timings',{});u=meta.get('usage',{});speeds={'input_tok_s':t.get('prompt_per_second'),'generation_tok_s':t.get('predicted_per_second'),'input_tokens':u.get('prompt_tokens',u.get('input_tokens')),'output_tokens':u.get('completion_tokens',u.get('output_tokens')),'input_seconds':t.get('prompt_ms',0)/1000 if t else None,'generation_seconds':t.get('predicted_ms',0)/1000 if t else None,'cached_tokens':t.get('cache_n'),'mlx_peak_allocation_gb':t.get('peak_memory') if key=='mlx2' else None}
 result={'backend':key,'case':case,'rep':rep,'condition':'process-cold-first-request' if case=='order' and rep==1 else 'first-image-encode' if case=='image' and rep==1 else 'model-resident-warm','ttft_s':ttft,'first_answer_s':first_answer,'total_s':total,'finish_reason':finish,'error':error,**speeds,'memory':m.summary(),'score':score(content,tools,finish,thinking,case),'content':content,'thinking':thinking,'tool_calls':tools,'backend_meta':meta}
 write_json(out/'stream.json',events);write_json(out/'result.json',result)
 print(json.dumps({k:result[k] for k in ['backend','case','rep','condition','ttft_s','total_s','input_tok_s','generation_tok_s','error','score']},ensure_ascii=False),flush=True)
 return result

def run_backend(key):
 image=fixture();out=ROOT/'results'/key;out.mkdir(parents=True,exist_ok=True)
 port=MODELS[key]['port']
 with socket.socket() as s:
  try:s.bind(('127.0.0.1',port))
  except OSError:raise RuntimeError(f'port {port} occupied; no process stopped')
 cmd,env=commands(key);write_json(out/'launch.json',{'cmd':cmd,'env_overrides':{k:env[k] for k in ['HF_HOME','TOKENIZERS_PARALLELISM']+([x for x in env if x.startswith('OLLAMA_')] if key=='ollama' else [])},'started_wall':time.time(),'preflight_swap':psutil.swap_memory()._asdict()})
 log=(out/'server.log').open('w');p=subprocess.Popen(cmd,env=env,cwd=ROOT,stdout=log,stderr=subprocess.STDOUT,start_new_session=True)
 (out/'pid').write_text(str(p.pid));m=Monitor(p.pid,out/'whole-lifecycle-memory.jsonl').start();start=time.perf_counter();loaded=None;results=[]
 try:
  for _ in range(600):
   if p.poll() is not None:raise RuntimeError(f'{key} exited {p.returncode}; see server.log')
   try:
    path='/api/version' if key=='ollama' else '/health' if key=='pq2' else '/v1/models'
    with request(f'http://127.0.0.1:{port}'+path,timeout=2) as r:
     if r.status==200:loaded=time.perf_counter()-start;break
   except Exception:pass
   time.sleep(1)
  if loaded is None:raise RuntimeError('server readiness timeout')
  write_json(out/'readiness.json',{'startup_to_endpoint_ready_s':loaded,'weights_loaded_at_readiness':key!='ollama','cold_definition':'new server process, no OS filesystem cache purge'})
  # Three runs per fixture. All share identical fixture bytes/settings.
  # Warm refers to weight residency; native caches are enabled on all backends.
  for case in ['order','tool','image']:
   for rep in [1,2,3]:
    r=run_request(key,case,rep,p.pid,image);results.append(r)
    if r['error'] and 'timed out' in r['error']:raise RuntimeError('request timed out; stop only benchmark process')
 finally:
  m.stop();write_json(out/'lifecycle-memory-summary.json',m.summary())
  try:os.killpg(p.pid,signal.SIGTERM)
  except ProcessLookupError:pass
  try:p.wait(timeout=30)
  except subprocess.TimeoutExpired:os.killpg(p.pid,signal.SIGKILL);p.wait()
  log.close()
 return results

if __name__=='__main__':
 ap=argparse.ArgumentParser();ap.add_argument('backend',choices=[*MODELS,'fixtures']);a=ap.parse_args()
 if a.backend=='fixtures':fixture()
 else:run_backend(a.backend)
