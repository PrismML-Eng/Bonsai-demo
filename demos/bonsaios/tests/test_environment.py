"""Metadata portability and workspace isolation; no recorded answers are fixtures."""
import copy,json,sys,tempfile,types,unittest
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'src'))
from environment import EnvironmentPins,PINS,VIRTUAL_WORK,VIRTUAL_HOME
class PinsTest(unittest.TestCase):
 def test_dates_paths_and_host_are_stable_but_user_request_is_preserved(self):
  pin=EnvironmentPins('/tmp/install/work','/tmp/install/home')
  request={'messages':[{'role':'system','content':'Conversation started: tomorrow\nHost: other machine\nCurrent working directory: /tmp/install/work\nScratch directory: /tmp/install/home/scratch'},{'role':'user','content':'Create my custom game.'}],'seed':7,'temperature':0.7}
  saved=copy.deepcopy(request);result,index=pin.normalize(request,0)
  self.assertEqual(request,saved);self.assertEqual(result['messages'][1],request['messages'][1]);self.assertEqual(result['seed'],7)
  self.assertIn('Current working directory: '+VIRTUAL_WORK,result['messages'][0]['content'])
  self.assertIn(PINS['requests']['0'][0]['system_metadata']['Conversation started:'],result['messages'][0]['content'])
 def test_ids_in_structured_fields_and_compression_notes(self):
  pin=EnvironmentPins('/a','/b');pin.remember_calls([{'id':'call_new'}],0,0)
  expected=PINS['requests']['0'][0]['tool_ids'][0]
  body={'messages':[{'role':'tool','tool_call_id':'call_new','content':'output'},{'role':'user','content':'You are a summarization agent creating a context checkpoint.\n[TOOL RESULT call_new]\nTEMPORAL ANCHORING: Today is 2030-01-01'}]}
  normalized,_=pin.normalize(body,0)
  self.assertEqual(normalized['messages'][0]['tool_call_id'],expected)
  self.assertIn('[TOOL RESULT '+expected+']',normalized['messages'][1]['content'])
  self.assertIn('2026-09-23',normalized['messages'][1]['content'])
 def test_extra_rounds_do_not_reject_custom_generations(self):
  pin=EnvironmentPins('/a','/b')
  body={'messages':[{'role':'user','content':'An unrelated task'}],'seed':99}
  for _ in range(100):self.assertEqual(pin.normalize(body,20)[0],body)
 def test_file_guard_dispatches_live_and_blocks_escape(self):
  from file_guard import install
  previous=sys.modules.get('tools.registry');fake=types.ModuleType('tools.registry');calls=[]
  class Registry:
   def dispatch(self,name,args,**kw):calls.append((name,args));return json.dumps({'path':args.get('path','.'),'live':True})
  fake.ToolRegistry=Registry;sys.modules['tools.registry']=fake
  try:
   with tempfile.TemporaryDirectory() as directory:
    work=Path(directory)/'work';work.mkdir();home=Path(directory)/'home';home.mkdir();install(work,home,True);registry=Registry()
    result=json.loads(registry.dispatch('read_file',{'path':VIRTUAL_WORK+'/os.html'}))
    self.assertTrue(result['live']);self.assertEqual(calls[-1][1]['path'],str(work/'os.html'));self.assertEqual(result['path'],VIRTUAL_WORK+'/os.html')
    registry.dispatch('read_file',{'path':'os.html'});self.assertEqual(calls[-1][1]['path'],'os.html')
    registry.dispatch('search_files',{'pattern':'hello'});self.assertNotIn('path',calls[-1][1])
    count=len(calls);denied=json.loads(registry.dispatch('read_file',{'path':'../private.txt'}));self.assertIn('error',denied);self.assertEqual(len(calls),count)
    (work/'escape').symlink_to(home,target_is_directory=True);self.assertIn('error',json.loads(registry.dispatch('write_file',{'path':'escape/private.txt','content':'x'})))
  finally:
   if previous is None:sys.modules.pop('tools.registry',None)
   else:sys.modules['tools.registry']=previous
if __name__=='__main__':unittest.main()
