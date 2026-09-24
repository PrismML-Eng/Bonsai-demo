"""Map virtual file locations to real fresh tools; never supply recorded results."""
import json
from pathlib import Path
from environment import VIRTUAL_WORK,map_paths
def install(root,home,pinned=True):
 from tools.registry import ToolRegistry
 root=Path(root).resolve();original=ToolRegistry.dispatch
 def dispatch(self,name,args,**kw):
  if name not in {'read_file','write_file','patch','search_files'}:
   return json.dumps({'error':'This trial permits only file tools within its workspace.'})
  args=dict(args);raw=args.get('path','.')
  if pinned and (raw==VIRTUAL_WORK or raw.startswith(VIRTUAL_WORK+'/')):raw=str(root)+raw[len(VIRTUAL_WORK):]
  path=Path(raw).expanduser();path=path if path.is_absolute() else root/path
  if args.get('mode','replace')!='replace' or not path.resolve().is_relative_to(root):
   location=VIRTUAL_WORK if pinned else str(root)
   return json.dumps({'error':f'Work only in {location}. Other trial files and evaluators are outside this task.'})
  if 'path' in args:args['path']=raw
  result=original(self,name,args,**kw)
  return map_paths(result,root,home) if pinned else result
 ToolRegistry.dispatch=dispatch
