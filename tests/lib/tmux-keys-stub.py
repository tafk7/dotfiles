#!/usr/bin/env python3
"""Pane program for the tmux key tests: puts its tty in raw mode and logs every
input byte, so a test can see exactly what tmux forwarded to the application.

Run it under the name tmux should report as pane_current_command
(`exec -a claude python3 tmux-keys-stub.py ...`); tk_stub builds that command.
"""

import argparse
import os
import sys
import tty

parser = argparse.ArgumentParser()
parser.add_argument("--log", required=True, help="append raw input bytes here")
parser.add_argument("--alt", action="store_true", help="draw on the alternate screen")
parser.add_argument("--mouse", action="store_true", help="enable SGR mouse reporting")
args = parser.parse_args()

fd = sys.stdin.fileno()
tty.setraw(fd)


def write(text):
    sys.stdout.write(text)
    sys.stdout.flush()


if args.alt:
    write("\x1b[?1049h\x1b[H\x1b[2Jstub on the alternate screen\r\n")
if args.mouse:
    write("\x1b[?1000h\x1b[?1006h")

with open(args.log, "ab", buffering=0) as log:
    open(args.log + ".ready", "w").close()
    while True:
        data = os.read(fd, 1024)
        if not data:
            break
        log.write(data)
