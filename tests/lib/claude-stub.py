#!/usr/bin/env python3
"""Stand-in for `claude -p` in the ai-command tests.

Each call is appended to $AI_STUB_DIR/calls.jsonl (argv, stdin, cwd), and
answered as Claude Code 2.1 answers --output-format json --json-schema.
--session-id creates a session and --resume needs an existing one, as in
Claude. The answer comes from files in $AI_STUB_DIR, read at every call so a
test can change them while a shell is running:

  mode    ok (default), fail, auth, malformed, plain, wrong-session, slow
  reply   the command to return, `{n}` replaced by the call number
          (default: echo stub {n})
  sleep   seconds slow mode waits before answering (default 30)
"""

import json
import os
import sys
import time
from pathlib import Path

stub = Path(os.environ["AI_STUB_DIR"])
stdin = sys.stdin.read()
calls = stub / "calls.jsonl"
with calls.open("a") as log:
    log.write(json.dumps({"argv": sys.argv[1:], "stdin": stdin, "cwd": os.getcwd()}) + "\n")
number = sum(1 for _ in calls.open())


def setting(name, default):
    path = stub / name
    return path.read_text().rstrip("\n") if path.exists() else default


def option(name):
    args = sys.argv[1:]
    return args[args.index(name) + 1] if name in args else None


mode = setting("mode", "ok")
sessions = stub / "sessions"
sessions.mkdir(exist_ok=True)
session = option("--session-id")
if session:
    if (sessions / session).exists():
        sys.exit(f"Error: Session ID {session} is already in use.")
    (sessions / session).touch()
elif option("--resume"):
    session = option("--resume")
    if not (sessions / session).exists():
        sys.exit(f"No conversation found with session ID: {session}")
else:
    session = "00000000-0000-4000-8000-000000000000"

if mode == "slow":
    time.sleep(float(setting("sleep", "30")))
if mode == "fail":
    sys.exit("API Error: 529 overloaded (stub)")
if mode == "malformed":
    print("this is not JSON")
    sys.exit(0)

command = setting("reply", "echo stub {n}").replace("{n}", str(number))
result = {"type": "result", "subtype": "success", "is_error": False, "num_turns": 2,
          "result": json.dumps({"command": command}), "session_id": session,
          "structured_output": {"command": command}}
if mode == "auth":
    result.update(is_error=True, result="Not logged in · Please run /login")
    result.pop("structured_output")
elif mode == "plain":
    result["result"] = command
    result.pop("structured_output")
elif mode == "wrong-session":
    result["session_id"] = "11111111-1111-4111-8111-111111111111"
print(json.dumps(result))
sys.exit(1 if result["is_error"] else 0)
