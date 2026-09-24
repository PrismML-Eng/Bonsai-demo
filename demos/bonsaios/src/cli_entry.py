"""Native Hermes CLI, isolated profile, file-only workspace."""
import os,sys
sys.path.insert(0,os.environ['BONSAIOS_HERMES'])
from hermes_cli import main
original=main.cmd_chat
def chat(args):
 from file_guard import install
 install(os.environ['TERMINAL_CWD'],os.environ['HERMES_HOME'],os.environ.get('BONSAIOS_PIN_ENVIRONMENT')=='1')
 return original(args)
main.cmd_chat=chat
if __name__=='__main__':main.main()
