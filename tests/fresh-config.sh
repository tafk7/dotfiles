#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/tests/lib/harness.sh"
fixture_init
trap fixture_cleanup EXIT
export PATH="$TEST_ROOT/bin:$TEST_SYSTEM_PATH"
source "$ROOT/setup.sh"
THEME_REQUEST=disabled
DOTFILES_GIT_NAME=Fixture DOTFILES_GIT_EMAIL=fixture@example.com

# Deterministically model a base machine, independent of CI's installed tools.
command() {
    if [[ "$1" == -v && ( "$2" == nvim || "$2" == delta ) ]]; then return 1; fi
    builtin command "$@"
}
process_git_config "$ROOT/configs/gitconfig" "$HOME/.gitconfig" >/dev/null
if git config --global --get core.editor >/dev/null; then fail "config-only Git requires nvim"; fi
if git config --global --get core.pager >/dev/null; then fail "config-only Git requires delta"; fi
if git config --global --get interactive.diffFilter >/dev/null; then fail "config-only Git requires delta filter"; fi
unset EDITOR VISUAL _DOTFILES_ENV_LOADED
source "$ROOT/shell/env.sh"
command -v "$EDITOR" >/dev/null || fail "default editor unavailable"
unset -f command

# Config root is outside fixture HOME; --force must still preserve displaced data.
IFS=: read -r target _ _ <<< "${CONFIG_MAP[config/bat]}"
[[ "$target" == "$XDG_CONFIG_HOME/bat" ]] || fail "XDG config path ignored"
mkdir -p "$target"
printf 'user config\n' > "$target/config"
FORCE_OVERWRITE=true
process_symlink "$ROOT/configs/config/bat" "$target" >/dev/null
[[ -L "$target" && ! -e "$HOME/.config/bat" ]] || fail "XDG link misplaced"
backup="$(find "$DOTFILES_BACKUP_PREFIX" -type f -name config -print -quit)"
grep -qx 'user config' "$backup" || fail "external-XDG config not backed up"

# External installers exit before any release/network lookup, even with --force.
for name in nvim tmux eget; do
    cp /usr/bin/true "$TEST_ROOT/bin/$name"
done
for name in neovim tmux eget; do
    rc=0
    "$ROOT/installers/install-$name.sh" --force >/dev/null || rc=$?
    assert_eq "$rc" 2 "$name external install preserved"
done
printf 'fresh-config: ok\n'
