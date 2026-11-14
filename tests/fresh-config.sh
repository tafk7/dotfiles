#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/tests/lib/harness.sh"
fixture_init
trap fixture_cleanup EXIT
export PATH="$TEST_ROOT/bin:$TEST_SYSTEM_PATH"
source "$ROOT/setup.sh"
THEME_REQUEST=disabled

# Deterministically model a base machine, independent of CI's installed tools.
command() {
    if [[ "$1" == -v && ( "$2" == nvim || "$2" == delta ) ]]; then return 1; fi
    builtin command "$@"
}
process_git_config "$ROOT/configs/gitconfig" "$HOME/.gitconfig" >/dev/null
if git config --global --get core.editor >/dev/null; then fail "config-only Git requires nvim"; fi
if git config --global --get core.pager >/dev/null; then fail "config-only Git requires delta"; fi
if git config --global --get interactive.diffFilter >/dev/null; then fail "config-only Git requires delta filter"; fi
# A standard base image ships vim-tiny; a minimal one ships no editor at all.
printf '#!/bin/sh\n' > "$TEST_ROOT/bin/vim"; chmod +x "$TEST_ROOT/bin/vim"
unset EDITOR VISUAL _DOTFILES_ENV_LOADED
source "$ROOT/shell/env.sh"
[[ "$EDITOR" == vim ]] || fail "default editor is $EDITOR, not the base image's vim"
source "$ROOT/lib/outcomes.sh"
source "$ROOT/lib/verify.sh"
[[ "$(verify_environment)" != *$'\teditor\t'* ]] || fail "verify flagged an installed editor"
rm "$TEST_ROOT/bin/vim"
command() {
    if [[ "$1" == -v && "$2" =~ ^(nvim|delta|vim|nano|vi)$ ]]; then return 1; fi
    builtin command "$@"
}
[[ "$(verify_environment)" == *$'advisory\tEnvironment\teditor\t'* ]] \
    || fail "verify missed a machine with no editor"
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
    fake_command "$TEST_ROOT/bin/$name" true
done
for name in neovim tmux eget; do
    rc=0
    "$ROOT/installers/install-$name.sh" --force >/dev/null || rc=$?
    assert_eq "$rc" 2 "$name external install preserved"
done
printf 'fresh-config: ok\n'
