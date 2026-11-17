#!/bin/bash
# bin/agent-trust on a temporary HOME and CODEX_HOME: trusting, revoking and
# pruning in Claude Code's ~/.claude.json and Codex's config.toml, worktrees,
# refusals (agent shells, no terminal, broad folders), Claude's lock, and
# Codex edits that keep the rest of the file. Answers go through a pty.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_REPO_ROOT="$ROOT"
source "$ROOT/tests/lib/harness.sh"
trap fixture_cleanup EXIT
fixture_init

# The caller may be an agent's shell: this test is the user's terminal.
unset CLAUDECODE AI_AGENT CODEX_THREAD_ID CODEX_SANDBOX CODEX_SANDBOX_NETWORK_DISABLED \
    OPENCODE OPENCODE_SESSION_ID CLAUDE_CONFIG_DIR
export CODEX_HOME="$HOME/.codex"
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
TOOL="$ROOT/bin/agent-trust"
CLAUDE_JSON="$HOME/.claude.json"
CODEX_TOML="$CODEX_HOME/config.toml"
W="$TEST_ROOT/w"
mkdir -p "$CODEX_HOME" "$W/plain/sub" "$W/other"

has() { [[ "$1" == *"$2"* ]] || fail "$3: missing '$2' in: $1"; }

# reset: a Claude file with another project and other settings, and a Codex
# file with comments and a table after the projects.
reset() {
    mkdir -p "$W/plain/sub" "$W/other"
    python3 - "$CLAUDE_JSON" "$W" <<'PY'
import json, sys
path, w = sys.argv[1:]
data = {"numStartups": 3, "theme": "dark", "projects": {
    f"{w}/other": {"allowedTools": ["Bash(ls)"], "hasTrustDialogAccepted": False, "lastCost": 1.5},
    f"{w}/gone": {"allowedTools": [], "hasTrustDialogAccepted": True},
    f"{w}/plain/sub": {"allowedTools": [], "hasTrustDialogAccepted": True}},
    "oauthAccount": {"emailAddress": "user@example.com"}}
open(path, "w").write(json.dumps(data, indent=2, ensure_ascii=False))
PY
    chmod 600 "$CLAUDE_JSON"
    cat > "$CODEX_TOML" <<EOF
# My Codex settings
model = "gpt-test"   # keep this comment

[projects."$W/gone"]
trust_level = "trusted"

[projects."$W/other"]
trust_level = "untrusted"

# Profiles follow.
[profiles.fast]
model_reasoning_effort = "low"
EOF
    chmod 600 "$CODEX_TOML"
}

# run ANSWER ARGS...: the tool in a pty that answers ANSWER; sets out and rc.
run() {
    local answer="$1"
    shift
    rc=0
    out=$(printf '%s\n' "$answer" | script -qec "$(printf '%q ' "$TOOL" "$@")" /dev/null 2>&1) || rc=$?
    out=${out//$'\r'/}
}

# plain ARGS...: the tool with no terminal at all (stdout and stderr).
plain() {
    rc=0
    out=$(setsid -w "$TOOL" "$@" 2>&1 </dev/null) || rc=$?
}

claude_q() { python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(eval(sys.argv[2]))' "$CLAUDE_JSON" "$1"; }
codex_q() { python3 -c 'import tomllib,sys; d=tomllib.load(open(sys.argv[1],"rb")); print(eval(sys.argv[2]))' "$CODEX_TOML" "$1"; }
state() { sha256sum "$CLAUDE_JSON" "$CODEX_TOML"; ls -a "$HOME" "$CODEX_HOME"; }

# --- Refusals: agent shells, broad folders, no terminal. Nothing changes.
reset
before=$(state)
for marker in CLAUDECODE=1 AI_AGENT=claude-code CODEX_THREAD_ID=0199 CODEX_SANDBOX=seatbelt OPENCODE=1; do
    rc=0
    out=$(env "$marker" "$TOOL" "$W/plain" 2>&1) || rc=$?
    assert_eq "$rc" 1 "$marker: exit status"
    has "$out" "refusing to run in an agent's shell (${marker%%=*} is set)" "$marker"
    rc=0
    env "$marker" "$TOOL" --list >/dev/null 2>&1 || rc=$?
    assert_eq "$rc" 1 "$marker: --list is refused too"
done
for folder in "$HOME" "$HOME/" "$(dirname "$HOME")" / /tmp; do
    run y "$folder"
    assert_eq "$rc" 1 "$folder: exit status"
    has "$out" "refusing to trust" "$folder"
done
ln -s "$HOME" "$W/home-link"
run y "$W/home-link"
has "$out" "refusing to trust ~: your home folder" "home through a symlink"
plain "$W/plain"
assert_eq "$rc" 1 "no terminal: exit status"
has "$out" "needs a terminal to ask on" "no terminal"
plain --revoke "$W/plain/sub"
has "$out" "needs a terminal to ask on" "no terminal for --revoke"
run y "$W/missing"
has "$out" "no such folder" "missing folder"
plain
assert_eq "$rc" 2 "no PATH: usage error"
assert_eq "$(state)" "$before" "refusals changed nothing"

# --- Dry run needs no terminal and writes nothing.
plain --dry-run "$W/plain"
assert_eq "$rc" 0 "dry run: exit status"
has "$out" "trust   $W/plain" "dry run shows the change"
has "$out" "Dry run: nothing written." "dry run"
assert_eq "$(state)" "$before" "dry run changed nothing"

# --- Declining changes nothing.
run n "$W/plain"
assert_eq "$rc" 1 "declined: exit status"
has "$out" "Trust these in Claude Code and Codex? [y/N]" "the question"
has "$out" "Nothing changed." "declined"
assert_eq "$(state)" "$before" "declining changed nothing"

# --- Trust a new folder, and one with entries in both files.
codex_before=$(<"$CODEX_TOML")
run y "$W/plain" "$W/other"
assert_eq "$rc" 0 "trust: exit status"
has "$out" "Claude Code: done, read back from ~/.claude.json" "Claude confirmed"
has "$out" "Codex: done, read back from ~/.codex/config.toml" "Codex confirmed"
assert_eq "$(claude_q "d['projects']['$W/plain']")" \
    "{'allowedTools': [], 'mcpContextUris': [], 'mcpServers': {}, 'enabledMcpjsonServers': [], 'disabledMcpjsonServers': [], 'hasTrustDialogAccepted': True, 'hasClaudeMdExternalIncludesApproved': False, 'hasClaudeMdExternalIncludesWarningShown': False}" \
    "a new Claude entry has Claude's defaults"
assert_eq "$(claude_q "d['projects']['$W/other']")" \
    "{'allowedTools': ['Bash(ls)'], 'hasTrustDialogAccepted': True, 'lastCost': 1.5}" "an existing Claude entry keeps its fields"
assert_eq "$(claude_q "(d['numStartups'], d['theme'], d['oauthAccount'], len(d['projects']))")" \
    "(3, 'dark', {'emailAddress': 'user@example.com'}, 4)" "the rest of ~/.claude.json"
[[ "$(tail -c 1 "$CLAUDE_JSON")" == "}" ]] || fail "the Claude file gained a trailing newline"
assert_eq "$(stat -c %a "$CLAUDE_JSON") $(stat -c %a "$CODEX_TOML")" "600 600" "modes kept"
[[ ! -e "$CLAUDE_JSON.lock" ]] || fail "the Claude lock was left behind"
assert_eq "$(codex_q "(d['projects']['$W/plain'], d['projects']['$W/other'], d['model'], d['profiles'])")" \
    "({'trust_level': 'trusted'}, {'trust_level': 'trusted'}, 'gpt-test', {'fast': {'model_reasoning_effort': 'low'}})" \
    "Codex trust"
expected=${codex_before/'trust_level = "untrusted"'/'trust_level = "trusted"'}
expected+=$'\n\n'"[projects.\"$W/plain\"]"$'\ntrust_level = "trusted"'
assert_eq "$(<"$CODEX_TOML")" "$expected" "Codex: changed in place and appended, comments kept"
leftovers=$(find "$HOME" "$CODEX_HOME" -maxdepth 1 -name '*.tmp')
assert_eq "$leftovers" "" "no temporary file left behind"

# --- Again: nothing to change, and no question.
plain "$W/plain"
assert_eq "$rc" 0 "already trusted: exit status"
has "$out" "already trusted: $W/plain" "already trusted"
has "$out" "Nothing to change." "already trusted"

# --- Symlinks resolve; a linked worktree stands for its main repository.
ln -s "$W/plain" "$W/plain-link"
plain --dry-run --claude "$W/plain-link"
has "$out" "already trusted: $W/plain" "a symlink resolves"
git init -q "$W/repo"
git -C "$W/repo" -c user.name=t -c user.email=t@example.com commit -q --allow-empty -m init
git -C "$W/repo" worktree add -q "$W/repo-wt" 2>/dev/null
mkdir -p "$W/repo-wt/src"
run y "$W/repo-wt/src"
assert_eq "$rc" 0 "worktree: exit status"
has "$out" "trust   $W/repo  (main repository of $W/repo-wt/src)" "worktree mapped"
assert_eq "$(claude_q "d['projects']['$W/repo']['hasTrustDialogAccepted']")" True "worktree: Claude"
assert_eq "$(codex_q "d['projects']['$W/repo']")" "{'trust_level': 'trusted'}" "worktree: Codex"
assert_eq "$(claude_q "'$W/repo-wt' in d['projects'] or '$W/repo-wt/src' in d['projects']")" False "no worktree entry"

# --- --list.
plain --list
assert_eq "$rc" 0 "list: exit status"
has "$out" "Claude Code (~/.claude.json): 5 trusted" "Claude list"
has "$out" "  $W/gone  (gone)" "a missing folder is marked"
has "$out" "Codex (~/.codex/config.toml): 4 trusted" "Codex list"

# --- Revoke: Claude keeps the entry; Codex drops the key, and the table if
# nothing else is in it.
python3 - "$CODEX_TOML" "$W" <<'PY'
import sys
path, w = sys.argv[1:]
text = open(path).read().replace(f'[projects."{w}/repo"]\n', f'[projects."{w}/repo"]\nnote = "kept"\n')
open(path, "w").write(text)
PY
run y --revoke "$W/plain" "$W/repo-wt" "$W/never"
assert_eq "$rc" 0 "revoke: exit status"
has "$out" "revoke  $W/plain" "revoke shown"
has "$out" "not trusted: $W/never" "an unknown folder"
assert_eq "$(claude_q "d['projects']['$W/plain']['hasTrustDialogAccepted'], d['projects']['$W/repo']['hasTrustDialogAccepted']")" \
    "(False, False)" "Claude revoked"
assert_eq "$(codex_q "'$W/plain' in d['projects'], d['projects']['$W/repo']")" "(False, {'note': 'kept'})" "Codex revoked"
grep -q "$W/plain\"" "$CODEX_TOML" && fail "the emptied Codex table stayed"

# --- Prune: entries of folders that are gone, trusted or not.
rm -rf "$W/other"
run y --prune
assert_eq "$rc" 0 "prune: exit status"
has "$out" "remove  $W/gone" "prune shown"
has "$out" "Remove 4 entries from Claude Code and Codex?" "prune question"
assert_eq "$(claude_q "sorted(d['projects'])")" "['$W/plain', '$W/plain/sub', '$W/repo']" "Claude pruned"
assert_eq "$(codex_q "sorted(d['projects'])")" "['$W/repo']" "Codex pruned"
has "$(<"$CODEX_TOML")" $'# Profiles follow.\n[profiles.fast]' "the comment above the next table is kept"
assert_eq "$(codex_q "d['profiles']")" "{'fast': {'model_reasoning_effort': 'low'}}" "profiles kept"
plain --prune
has "$out" "no entries of missing folders" "nothing left to prune"

# --- One agent at a time; an agent that isn't set up.
reset
run y --codex "$W/plain"
assert_eq "$(claude_q "'$W/plain' in d['projects']")" False "--codex leaves Claude alone"
assert_eq "$(codex_q "d['projects']['$W/plain']")" "{'trust_level': 'trusted'}" "--codex"
rm -rf "$CODEX_HOME"
run y "$W/plain"
assert_eq "$rc" 0 "no Codex: exit status"
has "$out" "Codex: not set up (~/.codex/config.toml), skipped" "no Codex"
assert_eq "$(claude_q "d['projects']['$W/plain']['hasTrustDialogAccepted']")" True "Claude without Codex"
run y --codex "$W/other"
assert_eq "$rc" 1 "--codex without Codex: exit status"
has "$out" "Codex is not set up here" "--codex without Codex"
mkdir -p "$CODEX_HOME"
run y --codex "$W/plain"
assert_eq "$(<"$CODEX_TOML")" "[projects.\"$W/plain\"]"$'\ntrust_level = "trusted"' "a new Codex file"
assert_eq "$(stat -c %a "$CODEX_TOML")" 600 "a new Codex file is private"

# --- Claude's lock: wait for a live one, take over a stale one.
reset
mkdir "$CLAUDE_JSON.lock"
(sleep 1; rmdir "$CLAUDE_JSON.lock") &
run y --claude "$W/plain"
wait
assert_eq "$rc" 0 "lock: exit status"
assert_eq "$(claude_q "d['projects']['$W/plain']['hasTrustDialogAccepted']")" True "written after the lock was released"
mkdir "$CLAUDE_JSON.lock"
touch -d '1 minute ago' "$CLAUDE_JSON.lock"
run y --claude --revoke "$W/plain"
assert_eq "$rc" 0 "stale lock: exit status"
[[ ! -e "$CLAUDE_JSON.lock" ]] || fail "the stale lock was left behind"

# --- Files it won't edit.
reset
mv "$CLAUDE_JSON" "$W/real.json"
ln -s "$W/real.json" "$CLAUDE_JSON"
run y --claude "$W/plain"
assert_eq "$rc" 1 "symlinked ~/.claude.json: exit status"
has "$out" "is a symlink; edit its target by hand" "symlinked ~/.claude.json"
rm "$CLAUDE_JSON"
mv "$W/real.json" "$CLAUDE_JSON"
printf 'projects = { "%s/plain" = { trust_level = "untrusted" } }\n' "$W" > "$CODEX_TOML"
before=$(state)
run y --codex "$W/plain"
assert_eq "$rc" 1 "inline Codex projects: exit status"
has "$out" "outside a [projects.\"...\"] table; edit it by hand" "inline Codex projects"
assert_eq "$(state)" "$before" "inline Codex projects unchanged"
printf 'model = \n' > "$CODEX_TOML"
before=$(state)
run y --codex "$W/plain"
has "$out" "is not valid TOML" "invalid Codex file"
assert_eq "$(state)" "$before" "an invalid Codex file is unchanged"

# --- CLAUDE_CONFIG_DIR moves Claude's file.
reset
mkdir -p "$TEST_ROOT/claude-alt"
cp "$CLAUDE_JSON" "$TEST_ROOT/claude-alt/.claude.json"
CLAUDE_CONFIG_DIR="$TEST_ROOT/claude-alt" run y --claude "$W/plain"
assert_eq "$(claude_q "'$W/plain' in d['projects']")" False "CLAUDE_CONFIG_DIR: ~/.claude.json untouched"
CLAUDE_JSON="$TEST_ROOT/claude-alt/.claude.json"
assert_eq "$(claude_q "d['projects']['$W/plain']['hasTrustDialogAccepted']")" True "CLAUDE_CONFIG_DIR"

# --- Claude Code denies the tool to itself by default.
python3 - "$ROOT/configs/claude-settings.defaults.json" <<'PY' || fail "no default deny rule for agent-trust"
import json, sys
assert "Bash(agent-trust*)" in json.load(open(sys.argv[1]))["permissions"]["deny"]
PY

printf 'agent-trust: ok\n'
