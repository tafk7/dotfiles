#!/usr/bin/env python3
"""Pane program for the tmux key tests: puts its tty in raw mode and logs every
input byte, so a test can see exactly what tmux forwarded to the application.

Run it under the name tmux should report as pane_current_command
(`exec -a claude python3 tmux-keys-stub.py ...`); tk_stub builds that command.

--claude imitates Claude's transcript view: Ctrl+O toggles it (its footer
reads "Showing detailed transcript"), and v in it writes the transcript to
$TMPDIR/cc-transcript-<hex>.txt and runs $VISUAL on that file as a direct
child, reading no input until the editor exits (`transcript`), or does nothing
(`never`).

--title sets the terminal title, as Codex does with its thread id.

--opencode imitates OpenCode's export dialog driven to Export (Ctrl+X x,
Shift+Tab, Enter): it writes session-stub.md to the temporary directory and
shows "Session exported" until Esc.

--editor imitates an agent's prompt box and its external editor (claude, the
default, and codex: Ctrl+G; opencode: Ctrl+X e): typed and pasted text goes
into the box; the key writes the box to a file named as that agent names it and
runs $VISUAL on it as a direct child; on exit 0 the file's text replaces the
box, as that agent takes it (Codex trims trailing whitespace; OpenCode keeps the
box for an empty file and drops a lone trailing newline). The box is written to
LOG.box after each edit.

--modes imitates Claude's permission-mode footer: a comma-separated cycle of
mode names ("accept edits", "plan mode"; an empty name shows no mode, as in
manual mode), the first shown at start; each Shift+Tab shows the next.
"""

import argparse
import os
import re
import subprocess
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
parser.add_argument("--claude", choices=["transcript", "never"], help="answer Ctrl+O v like Claude")
parser.add_argument("--title", help="set the terminal title")
parser.add_argument("--opencode", action="store_true", help="answer the export keys like OpenCode")
parser.add_argument("--editor", nargs="?", const="claude", choices=["claude", "codex", "opencode"],
                    help="keep a prompt box and run $VISUAL on it like that agent")
parser.add_argument("--modes", help="cycle these footer modes on Shift+Tab, like Claude")
args = parser.parse_args()

fd = sys.stdin.fileno()
tty.setraw(fd)


def write(text):
    os.write(sys.stdout.fileno(), text.encode())


ALT_SCREEN = "\x1b[?1049h\x1b[H\x1b[2Jstub on the alternate screen\r\n"
TRANSCRIPT_VIEW = "\x1b[H\x1b[2Jtranscript\x1b[40;1H Showing detailed transcript \u00b7 ctrl+o to toggle"
TRANSCRIPT = []
for turn in ("first", "second", "third"):
    TRANSCRIPT += [f"\u276f {turn} question", f"\u25cf {turn} answer"]
    TRANSCRIPT += [f"  {turn} detail {n}" for n in range(1, 31)]

box = ""
transcript_view = False


def claude_key(byte):
    """Ctrl+O and v, as Claude's transcript view takes them."""
    global transcript_view
    if byte == 0x0F:
        transcript_view = not transcript_view
        write(TRANSCRIPT_VIEW if transcript_view else ALT_SCREEN)
    elif byte == ord("v") and transcript_view and args.claude == "transcript":
        with tempfile.NamedTemporaryFile("w", prefix="cc-transcript-", suffix=".txt", delete=False) as out:
            out.write("\n".join(TRANSCRIPT) + "\n")
        subprocess.run([os.environ.get("VISUAL", "vi"), out.name])


# Each agent's external-editor key and its name for the prompt file.
EDITOR_KEYS = {"claude": b"\x07", "codex": b"\x07", "opencode": b"\x18e"}


def prompt_file():
    if args.editor == "codex":
        directory = os.path.join(os.environ["HOME"], ".codex", "editor")
        os.makedirs(directory, exist_ok=True)
        return tempfile.NamedTemporaryFile("w", prefix=".tmp", suffix=".md", dir=directory, delete=False)
    if args.editor == "opencode":
        return open(os.path.join(tempfile.gettempdir(), f"{time.time_ns() // 1000000}.md"), "w")
    return tempfile.NamedTemporaryFile("w", prefix="claude-prompt-", suffix=".md", delete=False)


def edit_box():
    global box
    with prompt_file() as prompt:
        prompt.write(box)
    if subprocess.run([os.environ.get("VISUAL", "vi"), prompt.name]).returncode == 0:
        with open(prompt.name) as prompt_text:
            text = prompt_text.read()
        if args.editor == "codex":
            box = text.rstrip()
        elif args.editor == "opencode":
            body = text[:-1] if text.endswith("\n") else text
            box = (body if "\n" not in body else text) if text else box
        else:
            box = text
    os.unlink(prompt.name)
    with open(args.log + ".box", "w") as box_file:
        box_file.write(box)


def type_into_box(data):
    global box
    # Claude's Ctrl+G may come as an extended key; other escape sequences are
    # dropped.
    text = re.sub(rb"\x1b\[27;5;103~", b"\x07", data)
    text = re.sub(rb"\x1b\[[0-9;]*[~A-Za-z]|\x1b.", b"", text)
    parts = text.split(EDITOR_KEYS[args.editor])
    for index, part in enumerate(parts):
        box += bytes(c for c in part if c >= 0x20 and c != 0x7F).decode(errors="replace")
        if index < len(parts) - 1:
            edit_box()


modes = args.modes.split(",") if args.modes is not None else []


def show_mode():
    label = f"\u23f5\u23f5 {modes[0]} on (shift+tab to cycle)" if modes[0] else "? for shortcuts"
    write(f"\x1b[999;1H\x1b[2K{label}")


if args.alt or args.claude or args.opencode or modes:
    write(ALT_SCREEN)
if modes:
    show_mode()
if args.title:
    write(f"\x1b]2;{args.title}\x07")
if args.mouse:
    write("\x1b[?1000h\x1b[?1006h")
if args.extkeys:
    write("\x1b[>4;2m")
if args.paste:
    write("\x1b[?2004h")

with open(args.log, "ab", buffering=0) as log:
    open(args.log + ".ready", "w").close()
    received = b""
    while True:
        data = os.read(fd, 1024)
        if not data:
            break
        log.write(data)
        if modes:
            for _ in range(data.count(b"\x1b[Z")):
                modes.append(modes.pop(0))
                show_mode()
        if args.claude:
            for byte in data:
                claude_key(byte)
        received += data
        if args.editor:
            type_into_box(data)
        if args.opencode and received.endswith(b"\x18x\x1b[Z\r"):
            with open(os.path.join(tempfile.gettempdir(), "session-stub.md"), "w") as export:
                export.write("\n".join(TRANSCRIPT) + "\n")
            write("\x1b[H\x1b[2JSession exported\r\n")
        elif args.opencode and data == b"\x1b":
            write(ALT_SCREEN)
