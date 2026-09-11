#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_ROOT="$(mktemp -d)"
SERVER="dotfiles-config-$RANDOM-$$"
trap 'TMUX_TMPDIR="$TEST_ROOT/tmux" tmux -L "$SERVER" kill-server 2>/dev/null || true; rm -rf "$TEST_ROOT"' EXIT
mkdir -p "$TEST_ROOT/home/dev" "$TEST_ROOT/tmux" "$TEST_ROOT/state" "$TEST_ROOT/cache"
SPACED="$TEST_ROOT/home/dev/dotfiles with spaces"
cp -a "$ROOT" "$SPACED"

HOME="$TEST_ROOT/home" XDG_STATE_HOME="$TEST_ROOT/state" XDG_CACHE_HOME="$TEST_ROOT/cache" \
    XDG_CONFIG_HOME="$TEST_ROOT/config" DOTFILES_DIR="$SPACED" \
    "$SPACED/setup.sh" --config --no-theme --no-hooks \
    --git-name Fixture --git-email fixture@example.com >/dev/null
[[ "$(readlink -f "$TEST_ROOT/home/.bashrc")" == "$SPACED/entry/bash.sh" ]] \
    || { echo "FAIL: setup did not honor spaced checkout path" >&2; exit 1; }

HOME="$TEST_ROOT/home" XDG_STATE_HOME="$TEST_ROOT/state" XDG_CACHE_HOME="$TEST_ROOT/cache" \
    TMUX_TMPDIR="$TEST_ROOT/tmux" DOTFILES_DIR="$SPACED" \
    tmux -L "$SERVER" -f "$SPACED/configs/tmux.conf" new-session -d -s test

observed="$(TMUX_TMPDIR="$TEST_ROOT/tmux" tmux -L "$SERVER" show-environment -g DOTFILES_DIR)"
[[ "$observed" == "DOTFILES_DIR=$SPACED" ]] || { echo "FAIL: tmux did not capture custom DOTFILES_DIR" >&2; exit 1; }

printf 'tmux-config: ok\n'
