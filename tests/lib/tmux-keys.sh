#!/bin/bash
# Raw-key harness for tmux binding tests.
#
# An inner tmux server loads configs/tmux.conf from a copy of the checkout at a
# path with spaces. Its client runs inside a pane of an outer `-f /dev/null`
# server under `script`, so a test types raw escape sequences the way WezTerm
# sends them (tk_raw) and reads every byte the client writes to its terminal
# (the script log; tk_osc52 decodes clipboard sequences from it).
#
#   tk_start                      start both servers and attach the client
#   ti ARGS...                    run a tmux command against the inner server
#   tk_raw BYTES                  type printf-escaped BYTES into the client
#   tk_esc                        type a lone Esc and let tmux take it as Escape
#   tk_stub NAME LOG [ARGS...]    pane command running the logging stub as NAME
#   tk_ready LOG                  wait until that stub is reading raw input
#   tk_input LOG                  what a stub received, through `cat -vT`
#   tk_wait FORMAT VALUE [PANE]   poll a format until it expands to VALUE
#   tk_until COMMAND...           retry COMMAND for up to five seconds
#   tk_expect WANT LABEL CMD...   retry until CMD prints WANT
#   tk_contains / tk_lacks TEXT CMD...   whether CMD's output contains TEXT
#   tk_screen_has TEXT [PANE]     whether TEXT is on the pane's screen
#   tk_client_screen              what the client shows, status line included
#   tk_mark / tk_osc52            OSC 52 payloads written since the mark
#   TK_TMUX                       $TMUX value for commands run "inside" tmux

# shellcheck source=tests/lib/harness.sh
source "$(dirname "${BASH_SOURCE[0]}")/harness.sh"

TK_INNER="tk-inner-$$-$RANDOM"
TK_OUTER="$TK_INNER-outer"
TK_STUB="$TEST_REPO_ROOT/tests/lib/tmux-keys-stub.py"
TK_MARK=0

tk_cleanup() {
    tmux -L "$TK_OUTER" kill-server 2>/dev/null || true
    tmux -L "$TK_INNER" kill-server 2>/dev/null || true
    fixture_cleanup
}

ti() { timeout 5 tmux -L "$TK_INNER" "$@"; }

tk_start() {
    fixture_init
    trap tk_cleanup EXIT
    TK_CHECKOUT="$TEST_ROOT/dotfiles with spaces"
    TK_CONFIG="$TK_CHECKOUT/configs/tmux.conf"
    TK_LOG="$TEST_ROOT/client.log"
    mkdir -p "$TK_CHECKOUT"
    tar -C "$TEST_REPO_ROOT" --exclude=.git --exclude=generated --exclude=.backups -cf - . \
        | tar -x -C "$TK_CHECKOUT"
    export DOTFILES_DIR="$TK_CHECKOUT" SHELL=/bin/bash PATH="$TEST_ROOT/bin:$PATH"

    ti -f "$TK_CONFIG" new-session -d -s test -x 120 -y 40 'exec sleep 3600'
    tmux -L "$TK_OUTER" -f /dev/null new-session -d -s outer -x 120 -y 41 \
        "env -u TMUX TERM=xterm-256color script -qfc 'tmux -L $TK_INNER attach -t test' '$TK_LOG'"
    tk_until tk_contains x ti list-clients -F x || fail "the test client never attached"
    TK_TMUX=$(ti display-message -p '#{socket_path},#{pid},0')
}

tk_raw() {
    local hex
    # shellcheck disable=SC2059  # BYTES is a printf escape string by design.
    hex=$(printf "$1" | od -An -tx1 -v)
    # shellcheck disable=SC2086  # one argument per byte
    tmux -L "$TK_OUTER" send-keys -t outer -H $hex
}

# tmux waits up to 500 ms for more bytes after a lone Esc while it still has a
# query out to the terminal, and the outer test server never answers all of
# them; a key typed sooner would turn the Esc into Meta.
tk_esc() {
    tk_raw '\e'
    sleep 0.6
}

tk_stub() {
    local name="$1" log="$2"
    shift 2
    rm -f -- "$log.ready"
    : >> "$log"
    printf 'exec -a %q python3 %q --log %q' "$name" "$TK_STUB" "$log"
    (($# == 0)) || printf ' %q' "$@"
}

tk_ready() { tk_until test -e "$1.ready" || fail "stub for $1 never started"; }

tk_input() { cat -vT -- "$1"; }

tk_wait() {
    local format="$1" want="$2" pane="${3:-}" got _
    for _ in {1..50}; do
        got=$(ti display-message -p ${pane:+-t "$pane"} "$format" 2>/dev/null || true)
        [[ "$got" == "$want" ]] && return 0
        sleep 0.1
    done
    fail "$format: expected '$want', got '$got'"
}

# Poll a command until it succeeds (five seconds).
tk_until() {
    local _
    for _ in {1..50}; do
        "$@" && return 0
        sleep 0.1
    done
    return 1
}

tk_expect() {
    local want="$1" label="$2" got _
    shift 2
    for _ in {1..50}; do
        got=$("$@" 2>/dev/null || true)
        [[ "$got" == "$want" ]] && return 0
        sleep 0.1
    done
    fail "$label: expected '$want', got '$got'"
}

tk_contains() {
    local text="$1"
    shift
    [[ "$("$@" 2>/dev/null)" == *"$text"* ]]
}

tk_lacks() { ! tk_contains "$@"; }

tk_client_screen() { tmux -L "$TK_OUTER" capture-pane -p -t outer; }

tk_screen_has() { [[ "$(ti capture-pane -p ${2:+-t "$2"})" == *"$1"* ]]; }

tk_mark() { TK_MARK=$(stat -c %s "$TK_LOG"); }

# Print each OSC 52 payload written to the client since the mark, one per line.
tk_osc52() {
    python3 - "$TK_LOG" "$TK_MARK" <<'PY'
import base64, re, sys
data = open(sys.argv[1], "rb").read()[int(sys.argv[2]):]
for match in re.finditer(rb"\x1b\]52;[^;]*;([A-Za-z0-9+/=]*)(?:\x07|\x1b\\)", data):
    sys.stdout.buffer.write(base64.b64decode(match.group(1)) + b"\n")
PY
}

# Most recent status message shown to a client (the log is newest first).
tk_last_message() { ti show-messages | grep -m1 ' message: ' || true; }
