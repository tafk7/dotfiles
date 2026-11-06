#!/bin/bash
# bin/forwards: a tunnel's hold sets tmux's @forwards while it lives, status
# and close find it by its lock, toggle closes an open tunnel, and a client
# that goes away ends the hold at the next heartbeat.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_ROOT="$(mktemp -d)"
trap 'kill $(jobs -p) 2>/dev/null || true; rm -rf "$TEST_ROOT"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }

mkdir -p "$TEST_ROOT/bin" "$TEST_ROOT/run"
chmod 700 "$TEST_ROOT/run"
cat > "$TEST_ROOT/bin/tmux" <<EOF
#!/bin/sh
case "\$1" in list-clients) echo /dev/pts/9 ;; esac
echo "\$*" >> "$TEST_ROOT/tmux.log"
EOF
chmod +x "$TEST_ROOT/bin/tmux"
export PATH="$TEST_ROOT/bin:$PATH" XDG_RUNTIME_DIR="$TEST_ROOT/run" FORWARDS_HEARTBEAT=0.1
forwards="$ROOT/bin/forwards"

wait_for() {   # wait_for EXPECTED: forwards status prints it within 3 s
    local _
    for _ in $(seq 30); do
        [[ "$("$forwards" status 2>/dev/null || true)" == "$1" ]] && return 0
        sleep 0.1
    done
    fail "line ${BASH_LINENO[0]}: status is $("$forwards" status || true), not $1"
}
last_set() { grep '^set-option' "$TEST_ROOT/tmux.log" | tail -1; }

"$forwards" status >/dev/null && fail "status: open with no tunnel"
[[ "$("$forwards" status || true)" == closed ]] || fail "status: not closed"
"$forwards" hold 2>/dev/null && fail "hold without names"

# A hold whose client keeps reading its heartbeat: open, and tmux lit.
( "$forwards" hold viz other | cat >/dev/null ) &
wait_for 'open: viz other'
[[ "$(last_set)" == 'set-option -g @forwards other,viz' ]] || fail "tmux: $(last_set)"
grep -q '^refresh-client -S -t /dev/pts/9$' "$TEST_ROOT/tmux.log" || fail "tmux: status not redrawn"

# Toggle closes it, and tmux goes dim.
[[ "$("$forwards" toggle)" == closed ]] || fail "toggle did not close"
wait_for closed
[[ "$(last_set)" == 'set-option -gu @forwards' ]] || fail "tmux after toggle: $(last_set)"
ls "$TEST_ROOT/run/forwards"/hold.* >/dev/null 2>&1 && fail "toggle left a hold file"

# close ends a hold; with none open it says so and changes nothing.
( "$forwards" hold viz | cat >/dev/null ) &
wait_for 'open: viz'
"$forwards" close
wait_for closed
[[ "$("$forwards" close 2>&1)" == 'forwards: none open' ]] || fail "close with none open"

# The client goes away: the next heartbeat ends the hold.
( "$forwards" hold viz | while [[ ! -e "$TEST_ROOT/drop" ]]; do read -r -t 0.05 || true; done ) &
wait_for 'open: viz'
touch "$TEST_ROOT/drop"
wait_for closed
[[ "$(last_set)" == 'set-option -gu @forwards' ]] || fail "tmux after a dropped client: $(last_set)"

# A hold killed outright leaves a file with a free lock: stale, not open.
( "$forwards" hold viz | cat >/dev/null ) &
wait_for 'open: viz'
pkill -KILL -f "$forwards hold viz" || true
wait_for closed
[[ -z "$(ls -A "$TEST_ROOT/run/forwards")" ]] || fail "files left behind: $(ls -A "$TEST_ROOT/run/forwards")"

echo 'forwards: ok'
