"""Verify the cap affects emitted reasoning, not just request field acceptance."""
import json,sys,time,urllib.request,pathlib
url,out=sys.argv[1],pathlib.Path(sys.argv[2])
def post(path,payload):
 req=urllib.request.Request(url+path,data=json.dumps(payload).encode(),headers={'Content-Type':'application/json'})
 with urllib.request.urlopen(req,timeout=90) as r:return json.load(r)
payload={'model':'bonsai-2-27b','messages':[{'role':'user','content':'Design and implement a complete self-contained Flappy Bird HTML game. Carefully reason through physics, collisions, rendering, event handling, responsive layout and persistence before writing the code.'}],'temperature':1.0,'top_p':.95,'top_k':20,'min_p':0,'presence_penalty':0,'repeat_penalty':1,'seed':101,'max_tokens':512,'reasoning_effort':'xhigh','reasoning_budget_tokens':128,'chat_template_kwargs':{'enable_thinking':True}}
t=time.time();response=post('/v1/chat/completions',payload)
msg=response['choices'][0]['message'];reason=msg.get('reasoning_content') or '';content=msg.get('content') or ''
n=len(post('/tokenize',{'content':reason,'add_special':False})['tokens'])
result={'request':payload,'response':response,'reasoning_retokenized_tokens':n,'wall_seconds':time.time()-t,'cap_enforced':bool(reason) and bool(content) and 0<n<=192,'note':'128-token reasoning probe, up to 64 tokens of allowance for closing/forced text and retokenization. Output is intentionally capped only for this infrastructure probe; probe is excluded from quality trials.'}
out.write_text(json.dumps(result,indent=2)+'\n');print(json.dumps({k:v for k,v in result.items() if k not in ['request','response']}))
if not result['cap_enforced']:raise SystemExit('Thinking budget failed its behavioral preflight')
