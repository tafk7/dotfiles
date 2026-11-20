#!/bin/bash
# setup_viz_service writes viz.service and viz-collect.service for a systemd
# user instance, against a stub systemctl: the generated text only, nothing is
# started.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_REPO_ROOT="$ROOT"
source "$ROOT/tests/lib/harness.sh"
trap fixture_cleanup EXIT
fixture_init
source "$ROOT/setup.sh"

units="$HOME/.config/systemd/user"
calls="$TEST_ROOT/systemctl-calls"
mkdir -p "$XDG_RUNTIME_DIR/systemd"
python3 -c 'import socket, sys; socket.socket(socket.AF_UNIX).bind(sys.argv[1])' "$XDG_RUNTIME_DIR/systemd/private"

# The stub answers for this HOME's manager. RUNNING lists the units that are
# enabled and active; FAILING the units whose restart fails.
RUNNING="" FAILING=""
systemctl() {
    printf '%s\n' "$*" >> "$calls"
    case "$*" in
        "--user show-environment") printf 'HOME=%s\n' "$HOME" ;;
        "--user is-enabled "*|"--user is-active "*) [[ " $RUNNING " == *" ${*: -1} "* ]] ;;
        "--user restart "*) [[ " $FAILING " != *" ${*: -1} "* ]] ;;
        *) return 0 ;;
    esac
}

expected_viz="[Unit]
Description=viz: serve ~/viz to the ssh client's browser

[Service]
Type=simple
ExecStartPre=-\"$DOTFILES_DIR/bin/viz\" stop
ExecStart=\"$DOTFILES_DIR/bin/viz\" serve
Restart=on-failure
RestartSec=30

[Install]
WantedBy=default.target"
expected_collect="[Unit]
Description=viz: run the live pages' collectors (viz collect)

[Service]
Type=simple
ExecStart=\"$DOTFILES_DIR/bin/viz\" collect
Restart=on-failure
RestartSec=30

[Install]
WantedBy=default.target"

# A first install writes both units, enables and starts them.
: > "$calls"
setup_viz_service >/dev/null 2>&1 || fail "a first install failed"
[[ "$(<"$units/viz.service")" == "$expected_viz" ]] || fail "viz.service text changed"
[[ "$(<"$units/viz-collect.service")" == "$expected_collect" ]] || fail "viz-collect.service text is wrong"
for name in viz.service viz-collect.service; do
    grep -qxF -- "--user enable $name" "$calls" || fail "$name was not enabled"
    grep -qxF -- "--user restart $name" "$calls" || fail "$name was not started"
done
! compgen -G "$units/.viz*" >/dev/null || fail "a staged unit was left behind"

# Installed, enabled and running: nothing is reloaded or restarted.
: > "$calls"
RUNNING="viz.service viz-collect.service"
setup_viz_service >/dev/null 2>&1 || fail "an unchanged install failed"
! grep -qE -- '--user (daemon-reload|enable|restart)' "$calls" || fail "an unchanged install touched the units"

# A changed checkout path rewrites and restarts both.
: > "$calls"
DOTFILES_DIR="$TEST_ROOT/elsewhere" setup_viz_service >/dev/null 2>&1 || fail "a moved checkout failed"
grep -qF "ExecStart=\"$TEST_ROOT/elsewhere/bin/viz\" collect" "$units/viz-collect.service" \
    || fail "viz-collect.service does not name the new checkout"
grep -qxF -- "--user restart viz-collect.service" "$calls" || fail "a changed viz-collect.service was not restarted"

# One unit failing to start does not keep the other from being installed.
rm -f "$units"/*.service
RUNNING="" FAILING="viz.service"
if setup_viz_service >/dev/null 2>&1; then fail "a unit that did not start was not reported"; fi
[[ "$(<"$units/viz-collect.service")" == "$expected_collect" ]] || fail "viz-collect.service was skipped"

# A dry run writes nothing.
rm -f "$units"/*.service
FAILING=""
DRY_RUN=true setup_viz_service >/dev/null 2>&1 || fail "a dry run failed"
! compgen -G "$units/*.service" >/dev/null || fail "a dry run wrote a unit"

printf 'viz-service: ok\n'
