#!/bin/bash
# Hermetic contract tests for the Layer 0 shell path.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_REPO_ROOT="$ROOT"
source "$ROOT/tests/lib/harness.sh"
trap fixture_cleanup EXIT
fixture_init
unset _DOTFILES_ENV_LOADED _DOTFILES_BASE_ENV _PROFILE_LOADED

mkdir -p "$HOME"
ln -s "$ROOT/entry/profile.sh" "$HOME/.profile"
ln -s "$ROOT/entry/bash.sh" "$HOME/.bashrc"
ln -s "$ROOT/entry/bash_profile" "$HOME/.bash_profile"
ln -s "$ROOT/entry/zshenv" "$HOME/.zshenv"
ln -s "$ROOT/entry/zsh.sh" "$HOME/.zshrc"
ln -s "$ROOT/entry/zprofile" "$HOME/.zprofile"

state_before="$(fixture_snapshot "$TEST_ROOT")"

bash_result="$(HOME="$HOME" PATH="$TEST_SYSTEM_PATH" DOTFILES_DIR="$ROOT" bash --noprofile --norc -c '
    external_fixture_function() { :; }
    source "$DOTFILES_DIR/entry/bash.sh"
    declare -F external_fixture_function >/dev/null || exit 21
    compgen -A function | grep -E "^(_dotfiles_|reload$|proj$|theme$)" || true
')"
[[ -z "$bash_result" ]] || fail "bash Layer 0 leaked interactive/private functions: $bash_result"
rg_config="$(HOME="$HOME" PATH="$TEST_SYSTEM_PATH" DOTFILES_DIR="$ROOT" bash --noprofile --norc -c \
    'source "$DOTFILES_DIR/entry/bash.sh"; printf %s "$RIPGREP_CONFIG_PATH"')"
assert_eq "$rg_config" "$HOME/.ripgreprc" "tracked ripgrep config was not activated"

zsh_result="$(HOME="$HOME" PATH="$TEST_SYSTEM_PATH" DOTFILES_DIR="$ROOT" zsh -dfc '
    external_fixture_function() { : }
    source "$DOTFILES_DIR/entry/zshenv"
    (( $+functions[external_fixture_function] )) || exit 21
    print -rl -- ${(k)functions} | grep -E "^(_dotfiles_|reload$|proj$|theme$)" || true
')"
[[ -z "$zsh_result" ]] || fail "zsh Layer 0 leaked interactive/private functions: $zsh_result"

[[ -z "$(HOME="$HOME" PATH="$TEST_SYSTEM_PATH" bash --noprofile --norc -c 'source "$1/entry/bash.sh"; alias' _ "$ROOT")" ]] \
    || fail "bash Layer 0 defined aliases"
[[ -z "$(HOME="$HOME" PATH="$TEST_SYSTEM_PATH" DOTFILES_DIR="$ROOT" zsh -dfc \
    'source "$DOTFILES_DIR/entry/zshenv"; alias -L | grep -E "^(ll|theme|proj|cx|cl)=" || true')" ]] \
    || fail "zsh Layer 0 defined interactive aliases"

assert_eq "$(fixture_snapshot "$TEST_ROOT")" "$state_before" "Layer 0 mutated HOME/XDG state"
printf 'agent-shell: ok\n'
