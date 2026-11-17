"""dotfiles/agent-trust: a folder trusted with `agent-trust` opens in Claude Code and Codex without the trust question.

Setup: the agents image as `ada`, no network, the real Claude Code and Codex CLIs against the
stand-in servers, the commit cloned to ~/dev/dotfiles; two git repositories, ~/work/trusted and
~/work/control. `agent-trust ~/work/trusted` runs in a tmux pane (it asks on the terminal) and
is answered `y`.
Checks: agent-trust exits 0 and both files record the trust; each CLI started in the control
folder stops at its trust question (so the check can fail), and started in the trusted folder
gets past it to its prompt.
Covers: the folder-trust trap (sessions in a new folder stop at the trust question), and its fix.
"""

import json
import shlex
import time

from lib.results import Failure

NAME = "dotfiles/agent-trust"
SLOW = False
NETWORK = False
NEEDS = ("claude", "codex")
INTERFACE = 1

TRUSTED, CONTROL = "/home/ada/work/trusted", "/home/ada/work/control"
# What each CLI shows: its trust question, and a line it draws only once past it. Codex draws its whole
# input box ("Ask Codex to do anything") before deciding to ask, then replaces it with the question 5 to 10
# seconds later (checked 2026-11-17, 0.169.0); only a session that started shows the footer naming the
# model, which the stand-in config calls "stand-in". Claude asks before drawing anything else.
SCREENS = {
    "claude": {"command": "claude", "question": "Is this a project you created or one you trust",
               "ready": "Claude Code v"},
    "codex": {"command": "codex", "question": "Trust this folder?", "ready": "stand-in default"},
}


def pane(container, session: str) -> str:
    return container.exec(f"tmux capture-pane -p -t {session} 2>/dev/null || true", check=False).stdout


def screen_of(container, session: str, agent: str, timeout=90, settle=5) -> str:
    """Wait until the pane shows the agent's trust question or its past-the-question line, then SETTLE
    seconds more and read it again: the question wins if it showed at either read."""
    question, ready = SCREENS[agent]["question"], SCREENS[agent]["ready"]
    try:
        text = container.wait_for(
            f"t=$(tmux capture-pane -p -t {session}); "
            f"printf '%s' \"$t\" | grep -qF {shlex.quote(question)} && echo question && exit 0; "
            f"printf '%s' \"$t\" | grep -qF {shlex.quote(ready)} && echo ready && exit 0; exit 1",
            timeout=timeout)
    except TimeoutError:
        raise Failure(f"{agent} in {session}: neither its trust question nor its prompt within {timeout}s; "
                      f"pane: {' | '.join(line for line in pane(container, session).splitlines() if line.strip())[:300]}")
    if text.strip() == "question":
        return "question"
    time.sleep(settle)
    return "question" if question in pane(container, session) else "ready"


def run(ctx):
    container = ctx.start_agents("agent-trust")
    ctx.clone(container, "ada", "/home/ada/dev/dotfiles")
    container.exec(f"for d in {TRUSTED} {CONTROL}; do mkdir -p $d && git -C $d init -q; done")

    container.exec("tmux new-session -d -s trust -x 200 -y 50 "
                   f"'~/dev/dotfiles/bin/agent-trust {TRUSTED}; echo $? > /tmp/trust.exit; sleep 600'")
    try:
        container.wait_for("tmux capture-pane -p -t trust | grep -qF '[y/N]'", timeout=30)
    except TimeoutError:
        raise Failure("agent-trust did not ask: " + pane(container, "trust").strip()[:300])
    container.exec("tmux send-keys -t trust y Enter")
    status = container.wait_for("cat /tmp/trust.exit", timeout=30).strip()
    if status != "0":
        raise Failure(f"agent-trust exited {status}: " + pane(container, "trust").strip()[:300])

    claude_json = json.loads(container.exec("cat ~/.claude.json").stdout)
    if not claude_json.get("projects", {}).get(TRUSTED, {}).get("hasTrustDialogAccepted"):
        raise Failure(f"~/.claude.json does not trust {TRUSTED}")
    codex_config = container.exec("cat ~/.codex/config.toml").stdout
    if f'[projects."{TRUSTED}"]' not in codex_config or 'trust_level = "trusted"' not in codex_config:
        raise Failure(f"~/.codex/config.toml does not trust {TRUSTED}")

    seen = {}
    for agent in ("claude", "codex"):
        for label, folder in (("control", CONTROL), ("trusted", TRUSTED)):
            session = f"{agent}-{label}"
            container.exec(f"tmux new-session -d -s {session} -x 200 -y 50 -c {folder} "
                           f"'{SCREENS[agent]['command']}; sleep 600'")
            seen[session] = screen_of(container, session, agent)
            ctx.log(f"[{session}] {seen[session]}\n{pane(container, session)}")
    expected = {f"{agent}-control": "question" for agent in SCREENS} | {f"{agent}-trusted": "ready" for agent in SCREENS}
    wrong = [f"{session}: {seen[session]} (expected {want})" for session, want in expected.items()
             if seen[session] != want]
    if wrong:
        raise Failure("; ".join(wrong))
    return "trusted by agent-trust: Claude Code and Codex open without the question; the control folder still asks"
