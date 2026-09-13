#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_ROOT="$(mktemp -d)"
SERVER="dotfiles-config-$RANDOM-$$"
trap 'TMUX_TMPDIR="$TEST_ROOT/tmux" tmux -L "$SERVER" kill-server 2>/dev/null || true; rm -rf "$TEST_ROOT"' EXIT
mkdir -p "$TEST_ROOT/home/dev" "$TEST_ROOT/tmux" "$TEST_ROOT/state" "$TEST_ROOT/cache"
SPACED="$TEST_ROOT/home/dev/dotfiles with spaces"
mkdir -p "$SPACED"
tar -C "$ROOT" --exclude=.git --exclude=generated --exclude=.backups -cf - . | tar -x -C "$SPACED"

HOME="$TEST_ROOT/home" XDG_STATE_HOME="$TEST_ROOT/state" XDG_CACHE_HOME="$TEST_ROOT/cache" \
    XDG_CONFIG_HOME="$TEST_ROOT/config" DOTFILES_DIR="$SPACED" \
    "$SPACED/setup.sh" --config --no-theme --no-hooks \
    --git-name Fixture --git-email fixture@example.com >/dev/null
[[ "$(readlink -f "$TEST_ROOT/home/.bashrc")" == "$SPACED/entry/bash.sh" ]] \
    || { echo "FAIL: setup did not honor spaced checkout path" >&2; exit 1; }
git_include="$(git config --file "$TEST_ROOT/home/.gitconfig" --get-all include.path | head -n1)"
[[ "$git_include" == "$TEST_ROOT/config/dotfiles/gitconfig" ]] \
    || { echo "FAIL: Git include broke under a spaced checkout path" >&2; exit 1; }

cp "$SPACED/entry/bash.sh" "$TEST_ROOT/home/bashrc-flat"
resolved="$(HOME="$TEST_ROOT/home" XDG_STATE_HOME="$TEST_ROOT/state" DOTFILES_DIR='' \
    bash --noprofile --norc -c 'source "$1"; printf %s "$DOTFILES_DIR"' _ "$TEST_ROOT/home/bashrc-flat")"
[[ "$resolved" == "$SPACED" ]] || { echo "FAIL: flattened Bash entrypoint did not use durable install path" >&2; exit 1; }

cp "$SPACED/entry/zshenv" "$TEST_ROOT/home/zshenv-flat"
resolved="$(HOME="$TEST_ROOT/home" XDG_STATE_HOME="$TEST_ROOT/state" DOTFILES_DIR='' \
    zsh -dfc 'source "$1"; print -rn -- "$DOTFILES_DIR"' _ "$TEST_ROOT/home/zshenv-flat")"
[[ "$resolved" == "$SPACED" ]] || { echo "FAIL: flattened Zsh entrypoint did not use durable install path" >&2; exit 1; }

HOME="$TEST_ROOT/home" XDG_STATE_HOME="$TEST_ROOT/state" XDG_CACHE_HOME="$TEST_ROOT/cache" \
    TMUX_TMPDIR="$TEST_ROOT/tmux" DOTFILES_DIR="$SPACED" \
    tmux -L "$SERVER" -f "$SPACED/configs/tmux.conf" new-session -d -s test

observed="$(TMUX_TMPDIR="$TEST_ROOT/tmux" tmux -L "$SERVER" show-environment -g DOTFILES_DIR)"
[[ "$observed" == "DOTFILES_DIR=$SPACED" ]] || { echo "FAIL: tmux did not capture custom DOTFILES_DIR" >&2; exit 1; }
if TMUX_TMPDIR="$TEST_ROOT/tmux" tmux -L "$SERVER" show-hooks -g after-select-window \
    | grep -Fq 'theme-switcher'; then
    echo "FAIL: disabled theme installed tmux hooks" >&2
    exit 1
fi

printf 'tmux-config: ok\n'
