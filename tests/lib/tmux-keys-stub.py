#!/usr/bin/env python3
"""Pane program for the tmux key tests: puts its tty in raw mode and logs every
input byte, so a test can see exactly what tmux forwarded to the application.

Run it under the name tmux should report as pane_current_command
(`exec -a claude python3 tmux-keys-stub.py ...`); tk_stub builds that command.

--claude imitates Claude's fullscreen transcript dump: on Ctrl+O [ it leaves
the alternate screen at once and, after a pause, writes a transcript over the
normal screen (`dump`, `short` for one that fits the screen), or does nothing
(`never`); Esc returns to the alternate screen.

--opencode imitates OpenCode's export dialog driven to Export (Ctrl+X x, five
Tabs, Enter): it writes session-stub.md to the temporary directory and shows
"Session exported".
"""

import argparse
import os
import sys
import tempfile
import time
import tty

parser = argparse.ArgumentParser()
parser.add_argument("--log", required=True, help="append raw input bytes here")
parser.add_argument("--alt", action="store_true", help="draw on the alternate screen")
parser.add_argument("--mouse", action="store_true", help="enable SGR mouse reporting")
parser.add_argument("--paste", action="store_true", help="enable bracketed paste, as the agents do")
parser.add_argument("--extkeys", action="store_true", help="request extended keys (modifyOtherKeys 2), as Claude does")
parser.add_argument("--claude", choices=["dump", "short", "never"], help="answer Ctrl+O [ like Claude")
parser.add_argument("--opencode", action="store_true", help="answer the export keys like OpenCode")
args = parser.parse_args()

fd = sys.stdin.fileno()
tty.setraw(fd)


def write(text):
    os.write(sys.stdout.fileno(), text.encode())


ALT_SCREEN = "\x1b[?1049h\x1b[H\x1b[2Jstub on the alternate screen\r\n"
TRANSCRIPT = []
for turn in ("first", "second", "third"):
    TRANSCRIPT += [f"\u276f {turn} question", f"\u25cf {turn} answer"]
    TRANSCRIPT += [f"  {turn} detail {n}" for n in range(1, 31)]

if args.claude == "short":
    TRANSCRIPT = TRANSCRIPT[:4]

if args.alt or args.claude or args.opencode:
    write(ALT_SCREEN)
if args.mouse:
    write("\x1b[?1000h\x1b[?1006h")
if args.extkeys:
    write("\x1b[>4;2m")
if args.paste:
    write("\x1b[?2004h")

with open(args.log, "ab", buffering=0) as log:
    open(args.log + ".ready", "w").close()
    previous = received = b""
    while True:
        data = os.read(fd, 1024)
        if not data:
            break
        log.write(data)
        if args.claude in ("dump", "short") and b"\x0f[" in previous + data:
            # Claude leaves the alternate screen, prepares the dump (0.5 s for
            # a large session), then overwrites the screen from the top: a
            # second dump grows history by one transcript, not one plus a
            # screenful.
            write("\x1b[?1049l")
            time.sleep(0.8)
            write("\x1b[H" + "".join(line + "\x1b[K\r\n" for line in TRANSCRIPT))
        if args.claude and data == b"\x1b":
            write(ALT_SCREEN)
        received += data
        if args.opencode and received.endswith(b"\x18x\t\t\t\t\t\r"):
            with open(os.path.join(tempfile.gettempdir(), "session-stub.md"), "w") as export:
                export.write("\n".join(TRANSCRIPT) + "\n")
            write("\x1b[H\x1b[2JSession exported\r\n")
        previous = data[-1:]
