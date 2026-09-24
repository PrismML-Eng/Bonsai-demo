"""Stable model-visible metadata, with no response replay or output gates."""
import copy,json,re
from pathlib import Path
PINS=json.loads((Path(__file__).resolve().parents[1]/'repro/environment.json').read_text())
VIRTUAL_WORK=PINS['virtual_work'];VIRTUAL_HOME=PINS['virtual_home']
def transform(value,fn):
 if isinstance(value,str):return fn(value)
 if isinstance(value,list):return [transform(v,fn) for v in value]
 if isinstance(value,dict):return {k:transform(v,fn) for k,v in value.items()}
 return value
def map_paths(value,work,home):
 return transform(value,lambda s:s.replace(str(work),VIRTUAL_WORK).replace(str(home),VIRTUAL_HOME))
class EnvironmentPins:
 def __init__(self,work,home):
  self.work=work;self.home=home;self.counts={};self.ids={}
 def metadata(self,phase,index):
  # Extra/custom turns remain supported, using the final metadata state.
  rows=PINS['requests'].get(str(phase),PINS['requests']['5'])
  return rows[min(index,len(rows)-1)]['system_metadata']
 def normalize(self,request,phase):
  index=self.counts.get(phase,0);self.counts[phase]=index+1
  result=map_paths(copy.deepcopy(request),self.work,self.home)
  def ids(s):
   for actual,canonical in self.ids.items():s=s.replace(actual,canonical)
   return s
  result=transform(result,ids)
  for m in result.get('messages',[]):
   content=m.get('content')
   if not isinstance(content,str):continue
   if content.startswith('You are a summarization agent creating a context checkpoint.'):
    content=re.sub(r'^TEMPORAL ANCHORING:.*$',lambda match:re.sub(r'\d{4}-\d{2}-\d{2}',PINS['date'],match.group(0)),content,flags=re.M)
   if '## Context Recovery' in content:
    content=re.sub(r"(?m)^The \d+ compacted message\(s\).*session_search.*$",lambda line:re.sub(r"session_id='[0-9]{8}_[0-9]{6}_[a-zA-Z0-9]+'","session_id='"+PINS['reference_session']+"'",line.group(0)),content)
   if m.get('role')=='system':
    for prefix,line in self.metadata(phase,index).items():
     if line is not None:content=re.sub('^'+re.escape(prefix)+'.*$',lambda match:line,content,flags=re.M)
   m['content']=content
  return result,index
 def remember_calls(self,calls,phase,index):
  rows=PINS['requests'].get(str(phase),[])
  targets=rows[index]['tool_ids'] if index<len(rows) else []
  for i,call in enumerate(calls):
   actual=call.get('id')
   if actual and actual not in self.ids:
    self.ids[actual]=targets[i] if i<len(targets) else f'call_extra_{phase}_{index}_{i}'
