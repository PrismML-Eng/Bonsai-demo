"""Measured token/time accounting; reasoning is included in completion tokens."""
import argparse,json,time
from pathlib import Path
ap=argparse.ArgumentParser();ap.add_argument('run',type=Path);a=ap.parse_args();rows=[]
for f in sorted(a.run.glob('request-*.json')):
 q=json.loads(f.read_text());resp=q.get('response') or {};usage=resp.get('usage') or {};timings=resp.get('timings') or {}
 if not q.get('trace',{}).get('stream_complete',False):continue
 rows.append({'file':f.name,'phase':q.get('phase'),'purpose':q.get('purpose'),'started':q['started'],'wall_seconds':q.get('wall_seconds',0),'completion_tokens':usage.get('completion_tokens',0),'prompt_tokens':usage.get('prompt_tokens',0),'decode_tokens':timings.get('predicted_n'),'decode_ms':timings.get('predicted_ms'),'finish_reason':(resp.get('choices') or [{}])[0].get('finish_reason')})
state=json.loads((a.run/'state.json').read_text());main=[r for r in rows if r['purpose']=='agent'];aux=[r for r in rows if r['purpose']!='agent']
def aggregate(rs):
 total=sum(r['completion_tokens'] for r in rs);wall=sum(r['wall_seconds'] for r in rs);timed=[r for r in rs if r['decode_tokens'] is not None and r['decode_ms'] is not None];dt=sum(r['decode_tokens'] for r in timed);ms=sum(r['decode_ms'] for r in timed)
 return {'completed_requests':len(rs),'generated_tokens_including_reasoning':total,'generation_request_wall_seconds':wall,'output_tokens_per_request_wall_second':total/wall if wall else None,'server_decode_tokens_per_second':dt/(ms/1000) if ms else None,'requests_with_server_decode_timing':len(timed),'decode_seconds':ms/1000,'truncated_requests':sum(r['finish_reason']=='length' for r in rs)}
report={'status':state['status'],'seed':state['seed'],'variant':state['variant'],'reasoning_budget':state['budget'],'backend':'PrismML llama.cpp branch','total_elapsed_seconds':(state.get('finished') or time.time())-state['started'],'elapsed_definition':'GPU session start to finish, including model load and any feedback waits','main_generation':aggregate(main),'auxiliary_generation':aggregate(aux),'all_generation':aggregate(rows),'requests':rows,'note':'Backend startup probes are excluded. Generated/completion tokens include reasoning and tool arguments, not repeated input context. Decode throughput is token-weighted across timed requests; request-wall throughput also includes prefill/transport.'}
(a.run/'metrics.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps({k:v for k,v in report.items() if k!='requests'},indent=2))
