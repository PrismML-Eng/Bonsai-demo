#!/usr/bin/env python3
"""Detach a command into its own session. macOS has no setsid(1), and `nohup ... &` alone still
leaves the child in the launching shell's process group -- so when a harness reaps that group,
the agent dies mid-run (this killed pacman at turn 4).

Usage: daemonize.py <pidfile> <stdout> <stderr> <cmd> [args...]
"""
import os, sys
pidfile, out, err, *cmd = sys.argv[1:]
if os.fork():                       # parent returns immediately
    sys.exit(0)
os.setsid()                         # new session: no controlling terminal, own process group
if os.fork():                       # second fork: cannot reacquire a terminal
    os._exit(0)
with open(pidfile, "w") as f:
    f.write(str(os.getpid()))
fd = os.open(os.devnull, os.O_RDONLY); os.dup2(fd, 0)
for path, target in ((out, 1), (err, 2)):
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_APPEND, 0o644); os.dup2(fd, target)
os.execvp(cmd[0], cmd)
