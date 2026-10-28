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

--codex-modes imitates Codex's permission modes: its prompt (the placeholder
dimmed when empty), /permissions and the picker it opens (numbered rows, the
current one marked, Full Access asking once more), and F7, which opens the
picker on its first press and after that steps Read Only, Ask for approval,
Approve for me, each step noted in the transcript.

--opencode-modes imitates OpenCode's one permission switch: Ctrl+P's command
list, its Permissions entry, the setting Left and Right flip, and the footer
that reads "Build auto" while it accepts everything.
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
parser.add_argument("--codex-modes", action="store_true", help="switch permission modes like Codex")
parser.add_argument("--opencode-modes", action="store_true", help="switch permissions like OpenCode")
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


# One key per item: an escape sequence, a lone Esc, or a byte.
KEYS = re.compile(rb"\x1b\[[0-9;]*[~A-Za-z]|\x1bO.|\x1b|.", re.DOTALL)
CODEX_MODES = ["Ask for approval", "Approve for me", "Full Access", "Read Only"]
CODEX_CYCLE = {"Read Only": "Ask for approval", "Ask for approval": "Approve for me",
               "Approve for me": "Read Only", "Full Access": "Read Only"}
agent = {"mode": "Ask for approval", "first_f7": True, "dialog": None, "box": "", "notes": [],
         "auto": False, "search": ""}


def draw(lines):
    write("\x1b[H\x1b[2J" + "".join(f"\x1b[{row};1H{line}" for row, line in lines))


def codex_draw():
    """The transcript, then the prompt, or a dialog in its place, as Codex has it."""
    lines = [(row + 1, note) for row, note in enumerate(agent["notes"][-20:])]
    if agent["dialog"] == "picker":
        lines.append((32, "  Update Model Permissions"))
        for n, name in enumerate(CODEX_MODES, 1):
            current = " (current)" if name == agent["mode"] else ""
            lines.append((32 + n, f"{'›' if current else ' '} {n}. {name}{current}  what it allows"))
        lines.append((38, "  enter select · esc back"))
    elif agent["dialog"] == "confirm":
        lines += [(35, "› 1. Yes, continue anyway  Apply full access for this session"),
                  (36, "  2. Cancel                Go back without enabling full access"),
                  (38, "  enter select · esc back")]
    else:
        box = agent["box"] or "\x1b[2mAsk Codex to do anything\x1b[0m"
        # The prompt line has a themed background, as the real one does.
        lines += [(36, f"\x1b[1m›\x1b[0m\x1b[48;2;65;65;65m {box}\x1b[49m"), (38, "  Context 0% used · 0 out · stub")]
    draw(lines)


def codex_set(mode):
    agent["mode"] = mode
    agent["notes"].append(f"• Permission selection requested: {mode}")
    agent["dialog"] = None


def codex_key(key):
    dialog = agent["dialog"]
    if key == b"\x1b":
        agent["dialog"] = None
    elif dialog == "picker" and key in (b"1", b"2", b"3", b"4"):
        mode = CODEX_MODES[int(key) - 1]
        if mode == "Full Access":
            agent["dialog"] = "confirm"
        else:
            codex_set(mode)
    elif dialog == "confirm" and key == b"1":
        codex_set("Full Access")
    elif dialog == "confirm" and key == b"2":
        agent["dialog"] = None
    elif key == b"\x1b[18~":
        if agent["first_f7"]:
            agent["dialog"] = "picker"
        else:
            codex_set(CODEX_CYCLE[agent["mode"]])
        agent["first_f7"] = False
    elif key == b"\r":
        if agent["box"] == "/permissions":
            agent["dialog"] = "picker"
        elif agent["box"]:
            agent["notes"].append(f"› {agent['box']}")
        agent["box"] = ""
    elif not key.startswith(b"\x1b") and key >= b" ":
        agent["box"] += key.decode(errors="replace")
    codex_draw()


def opencode_draw():
    lines = []
    if agent["dialog"] == "commands":
        lines += [(5, "  Commands                esc"), (6, f"  {agent['search']}")]
        if "permis" in agent["search"].lower():
            lines.append((7, "  Permissions             Settings · Session"))
    elif agent["dialog"] == "settings":
        value = "auto accept" if agent["auto"] else "prompt"
        lines += [(5, f"  ● Permissions           {value}"), (6, "  change ←/→")]
    # A new session draws the prompt mid-screen.
    lines += [(20, f"┃  {agent['box'] or 'Ask anything'}"),
              (21, f"┃  Build{' auto' if agent['auto'] else ''} · Big Pickle OpenCode")]
    draw(lines)


def opencode_key(key):
    dialog = agent["dialog"]
    if key == b"\x1b":
        agent["dialog"] = None
    elif key == b"\x10":
        agent.update(dialog="commands", search="")
    elif dialog == "commands" and key == b"\r":
        if "permis" in agent["search"].lower():
            agent["dialog"] = "settings"
    elif dialog == "settings" and key in (b"\x1b[C", b"\x1b[D"):
        agent["auto"] = not agent["auto"]
    elif not key.startswith(b"\x1b") and key >= b" ":
        agent["search" if dialog == "commands" else "box"] += key.decode(errors="replace")
    opencode_draw()


if args.alt or args.claude or args.opencode or modes or args.codex_modes or args.opencode_modes:
    write(ALT_SCREEN)
if modes:
    show_mode()
if args.codex_modes:
    codex_draw()
if args.opencode_modes:
    opencode_draw()
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
        if args.codex_modes or args.opencode_modes:
            for key in KEYS.findall(data):
                (codex_key if args.codex_modes else opencode_key)(key)
        received += data
        if args.editor:
            type_into_box(data)
        if args.opencode and received.endswith(b"\x18x\x1b[Z\r"):
            with open(os.path.join(tempfile.gettempdir(), "session-stub.md"), "w") as export:
                export.write("\n".join(TRANSCRIPT) + "\n")
            write("\x1b[H\x1b[2JSession exported\r\n")
        elif args.opencode and data == b"\x1b":
            write(ALT_SCREEN)
