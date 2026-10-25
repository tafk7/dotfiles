#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_ROOT="$(mktemp -d)"
SERVER="dotfiles-config-$RANDOM-$$"
OUTER="$SERVER-outer"
trap 'tmux -L "$OUTER" kill-server 2>/dev/null || true; tmux -L "$SERVER" kill-server 2>/dev/null || true; tmux -L "$SERVER-guards" kill-server 2>/dev/null || true; rm -rf "$TEST_ROOT"' EXIT
mkdir -p "$TEST_ROOT/home/dev" "$TEST_ROOT/tmux" "$TEST_ROOT/state" "$TEST_ROOT/cache"
# Every tmux call below, including setup.sh's theme unwiring, must stay off the
# caller's real tmux server.
export TMUX_TMPDIR="$TEST_ROOT/tmux" TMUX=""
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

# Start the server from "inside" another tmux, as a nested tmux or an agent in a
# pane would. Its theme must be applied to itself, never to the outer server.
tmux -L "$OUTER" -f /dev/null new-session -d -s outer
tmux -L "$OUTER" set-option -gw @theme sentinel
outer_tmux="$(tmux -L "$OUTER" display-message -p '#{socket_path},#{pid},0')"

# Fresh state: the theme feature is on by default, so the server gets gruvbox.
mkdir -p "$TEST_ROOT/state-themed"
HOME="$TEST_ROOT/home" XDG_STATE_HOME="$TEST_ROOT/state-themed" XDG_CACHE_HOME="$TEST_ROOT/cache" \
    DOTFILES_DIR="$SPACED" TMUX="$outer_tmux" \
    tmux -L "$SERVER" -f "$SPACED/configs/tmux.conf" new-session -d -s test

# tmux.conf applies the theme in the background.
for _ in {1..50}; do
    [[ "$(tmux -L "$SERVER" show-options -gwqv @theme)" == gruvbox ]] && break
    sleep 0.1
done
[[ "$(tmux -L "$SERVER" show-options -gwqv @theme)" == gruvbox ]] \
    || { echo "FAIL: tmux.conf did not apply the theme to its own server" >&2; exit 1; }
[[ "$(tmux -L "$OUTER" show-options -gwqv @theme)" == sentinel ]] \
    || { echo "FAIL: a nested server's theme setup changed the outer server" >&2; exit 1; }

observed="$(tmux -L "$SERVER" show-environment -g DOTFILES_DIR)"
[[ "$observed" == "DOTFILES_DIR=$SPACED" ]] || { echo "FAIL: tmux did not capture custom DOTFILES_DIR" >&2; exit 1; }
if tmux -L "$SERVER" show-hooks -g | grep -Fq 'theme-switcher'; then
    echo "FAIL: themes must not need tmux hooks" >&2
    exit 1
fi

# A server started from a dotfiles shell inherits its exported load guards.
# tmux.conf drops them, so a new pane recomputes the environment from the
# checkout instead of keeping the values the server started with.
HOME="$TEST_ROOT/home" XDG_STATE_HOME="$TEST_ROOT/state-themed" XDG_CACHE_HOME="$TEST_ROOT/cache" \
    DOTFILES_DIR="$SPACED" _DOTFILES_BASE_ENV=1 _DOTFILES_ENV_LOADED=1 LESS=stale \
    tmux -L "$SERVER-guards" -f "$SPACED/configs/tmux.conf" new-session -d -s test
for guard in _DOTFILES_BASE_ENV _DOTFILES_ENV_LOADED; do
    if tmux -L "$SERVER-guards" show-environment -g "$guard" >/dev/null 2>&1; then
        echo "FAIL: tmux kept $guard in its global environment" >&2
        exit 1
    fi
done
tmux -L "$SERVER-guards" new-window -d "bash -lc 'printf %s \"\$LESS\" > \"$TEST_ROOT/pane-less\"'"
for _ in {1..50}; do [[ -s "$TEST_ROOT/pane-less" ]] && break; sleep 0.1; done
expected_less="$(sed -n "s/^ *export LESS='\\(.*\\)'$/\\1/p" "$ROOT/entry/profile.sh")"
[[ -n "$expected_less" && "$(cat "$TEST_ROOT/pane-less" 2>/dev/null)" == "$expected_less" ]] \
    || { echo "FAIL: a new pane did not recompute LESS: $(cat "$TEST_ROOT/pane-less" 2>/dev/null)" >&2; exit 1; }

printf 'tmux-config: ok\n'
