#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_REPO_ROOT="$ROOT"
source "$ROOT/tests/lib/harness.sh"
trap fixture_cleanup EXIT
fixture_init

rc=0
HOME="$HOME" XDG_STATE_HOME="$XDG_STATE_HOME" DOTFILES_DIR="$ROOT" \
    WSL_DISTRO_NAME=Ubuntu DOTFILES_TEST_SYSTEMD_RUNNING=0 \
    "$ROOT/installers/install-xrdp.sh" >/dev/null 2>&1 || rc=$?
[[ $rc -ne 0 ]] || fail "xrdp accepted WSL without systemd"
[[ ! -e "$HOME/.xsession" ]] || fail "xrdp mutated HOME before systemd preflight"

printf 'xrdp: ok\n'
