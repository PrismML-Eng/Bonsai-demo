"""Submit feedback to an interactive run without accessing the model directly."""
import argparse,json
from pathlib import Path
p=argparse.ArgumentParser(description=__doc__);p.add_argument('run',type=Path);g=p.add_mutually_exclusive_group(required=True);g.add_argument('--text');g.add_argument('--file',type=Path);g.add_argument('--stop',action='store_true');a=p.parse_args()
s=json.loads((a.run/'state.json').read_text())
if s['status']!='awaiting_feedback':p.error('Run is not currently awaiting feedback')
if a.stop:(a.run/'inbox/STOP').touch()
else:
 text=a.text if a.text is not None else a.file.read_text()
 if not text.strip():p.error('Feedback must not be empty')
 target=Path(s['next_feedback_file'])
 if target.exists():p.error('Feedback already submitted')
 temporary=target.with_suffix('.tmp');temporary.write_text(text.strip()+'\n');temporary.replace(target)
