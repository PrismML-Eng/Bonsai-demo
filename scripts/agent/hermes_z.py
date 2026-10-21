#!/usr/bin/env python3
"""hermes_z.py <task.md> [hermes args...] -- run hermes one-shot on the task text WITHOUT that text in the
process argv. `ps` and pattern-based process killers see only this wrapper and the file path.

Why: the model's terminal tool runs on this machine. On 2026-09-21 23:57:13 a skateboard run cleaned up its
headless browser with a pattern-kill matching 'headless' followed by 'chrom'; the subway task text (which
tells the model to render headless in Chrome) sat in every subway agent's argv, so the pattern matched and
killed four unrelated Hermes runs. Same self-match trap as pattern kills over ssh.
"""
import sys
task = open(sys.argv[1], encoding="utf-8").read()
sys.argv = ["hermes", "-z", task] + sys.argv[2:]
from hermes_cli.main import main
sys.exit(main())
