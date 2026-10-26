#!/bin/bash
# dotfiles update end to end, against a local remote: an upstream commit bumps
# one tool's pin and changes the shell environment. One update pulls, re-execs,
# installs the bumped build, refreshes the tmux server's environment once,
# verifies, and reports the shell that loaded before the change.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_REPO_ROOT="$ROOT"
TMUX_BIN="$(command -v tmux)" || { echo 'tmux required for update-e2e tests' >&2; exit 1; }
source "$ROOT/tests/lib/harness.sh"
fixture_init
unset DOTFILES_OPERATION
export DOTFILES_TMUX_SERVER="e2e-$$"
pids=()
trap 'kill "${pids[@]}" 2>/dev/null || true; command tmux -L "$DOTFILES_TMUX_SERVER" kill-server 2>/dev/null || true; fixture_cleanup' EXIT
export NO_COLOR=1 DOTFILES_TEST_PLATFORM=ubuntu DOTFILES_TEST_ARCH=x86_64 DOTFILES_TEST_OS_VERSION=24.04
export DOTFILES_TEST_SYSTEMD_RUNNING=0 DOTFILES_OPERATION_WAIT=1
export GIT_AUTHOR_NAME=Fixture GIT_AUTHOR_EMAIL=fixture@example.com GIT_COMMITTER_NAME=Fixture GIT_COMMITTER_EMAIL=fixture@example.com
export GIT_CONFIG_NOSYSTEM=1
ln -s "$TMUX_BIN" "$TEST_ROOT/bin/tmux"
# Nothing reaches the network or the package manager.
printf '#!/bin/sh\necho "curl $*" >> "%s/forbidden"\nexit 1\n' "$TEST_ROOT" > "$TEST_ROOT/bin/curl"
printf '#!/bin/sh\nexit 1\n' > "$TEST_ROOT/bin/dpkg-query"
chmod +x "$TEST_ROOT/bin/curl" "$TEST_ROOT/bin/dpkg-query"
mkdir -p "$HOME/.local/bin"
export PATH="$HOME/.local/bin:$TEST_ROOT/bin:$TEST_SYSTEM_PATH"
source "$ROOT/lib/install.sh"
digest() { sha256sum "$1" | awk '{print $1}'; }

# The seed checkout's lock records this machine's fake builds of every bash-tier
# eget tool, so the bash tier starts current.
seed="$TEST_ROOT/seed" remote="$TEST_ROOT/remote.git" checkout="$TEST_ROOT/checkout"
mkdir -p "$seed"
tar -C "$ROOT" --exclude=.git -cf - . | tar -x -C "$seed"
for name in "${REGISTRY_ORDER[@]}"; do
    [[ "$name" != packages:* && "${TOOL_METHOD[$name]}" == eget && "${TOOL_TIER[$name]:-}" == bash ]] || continue
    tool_applicable "$name" || continue
    for binary in "${TOOL_BINARY[$name]}" ${TOOL_COMPANIONS[$name]:-}; do
        printf '#!/bin/sh\necho "%s fixture"\n' "$binary" > "$HOME/.local/bin/$binary"
        chmod +x "$HOME/.local/bin/$binary"
    done
    awk -F '\t' -v OFS='\t' -v n="$name" -v d="sha256:$(digest "$HOME/.local/bin/${TOOL_BINARY[$name]}")" \
        '$1 == n && $2 == "x86_64" { $8 = d } 1' "$seed/versions.lock" > "$seed/versions.lock.new"
    mv "$seed/versions.lock.new" "$seed/versions.lock"
    ledger_record "$name" yes dotfiles installed fixture "$HOME/.local/bin/${TOOL_BINARY[$name]}" staged-release
done
# eget is the pin, and downloads write the prepared artifact for their target.
export EGET_ARTIFACTS="$TEST_ROOT/artifacts"
mkdir -p "$EGET_ARTIFACTS"
cat > "$HOME/.local/bin/eget" <<EOF
#!/bin/sh
if [ "\${1:-}" = --version ]; then echo 'eget version $EGET_VERSION'; exit 0; fi
while [ \$# -gt 0 ]; do [ "\$1" = --to ] && { to="\$2"; shift; }; shift; done
cat "\$EGET_ARTIFACTS/\$(basename "\$to")" > "\$to"
EOF
chmod +x "$HOME/.local/bin/eget"
ledger_record eget yes dotfiles installed "$EGET_VERSION" "$HOME/.local/bin/eget" staged-release
git -C "$seed" init -q -b main && git -C "$seed" add -A && git -C "$seed" commit -qm seed
git clone -q --bare "$seed" "$remote"
git clone -q "$remote" "$checkout"
"$checkout/setup.sh" --bash --no-hooks --no-theme --git-name Fixture --git-email fixture@example.com >"$TEST_ROOT/setup.out" 2>&1 \
    || fail "fixture setup failed: $(tail -20 "$TEST_ROOT/setup.out")"

# Running: a tmux server, and a shell that loaded before the upstream change.
command tmux -L "$DOTFILES_TMUX_SERVER" -f /dev/null new-session -d -s main
bash -c 'source "$1/shell/staleness.sh"; exec sleep 60' _ "$checkout" &
old_shell=$!; pids+=("$old_shell")
for _ in $(seq 50); do ls "$XDG_RUNTIME_DIR/dotfiles/shells/$old_shell-"* >/dev/null 2>&1 && break; sleep 0.1; done
sleep 1.1

# Upstream: fd's pin moves to a new build, and a shell default changes.
printf '#!/bin/sh\necho "fd 99"\n' > "$EGET_ARTIFACTS/fd"
work="$TEST_ROOT/upstream-work"
git clone -q "$remote" "$work"
awk -F '\t' -v OFS='\t' -v d="sha256:$(digest "$EGET_ARTIFACTS/fd")" \
    '$1 == "fd" && $2 == "x86_64" { $3 = "v99.0.0"; $8 = d } 1' "$work/versions.lock" > "$work/versions.lock.new"
mv "$work/versions.lock.new" "$work/versions.lock"
sed -i 's|^export PROJECTS_DIRS=.*|export PROJECTS_DIRS="$HOME/upstream-projects"|' "$work/shell/env.sh"
git -C "$work" commit -qam "Bump fd; change the project roots"
git -C "$work" push -q
before="$(git -C "$checkout" rev-parse --short HEAD)"

rc=0
output="$("$checkout/bin/dotfiles" update 2>&1)" || rc=$?
assert_eq "$rc" 0 "update: $output"
after="$(git -C "$checkout" rev-parse --short HEAD)"
[[ "$after" == "$(git -C "$remote" rev-parse --short HEAD)" && "$output" == *"update: $before -> $after"* ]] \
    || fail "the update did not pull and report the revisions: $output"
assert_eq "$(cat "$HOME/.local/bin/fd")" "$(cat "$EGET_ARTIFACTS/fd")" "the bumped build"
[[ "$(ledger_line fd)" == *"pin=v99.0.0 sha256=$(digest "$EGET_ARTIFACTS/fd")"* ]] || fail "the bump was not recorded: $(ledger_line fd)"
assert_eq "$(command tmux -L "$DOTFILES_TMUX_SERVER" show-environment -g PROJECTS_DIRS)" \
    "PROJECTS_DIRS=$HOME/upstream-projects" "the tmux server's environment after the update"
assert_eq "$(grep -c 'Refreshing running processes' <<< "$output")" 1 "refreshes in one update"
# (The tmux pane's own shell loaded before the pull too.)
stale="$(grep -m1 "loaded before the last change to shell startup (pulled $before..$after); reload them: pids " <<< "$output" || true)"
[[ " ${stale##*pids } " == *" $old_shell "* ]] || fail "the stale shell was not reported: $output"
[[ ! -e "$TEST_ROOT/forbidden" ]] || fail "the update reached the network: $(<"$TEST_ROOT/forbidden")"

printf 'update-e2e: ok\n'
