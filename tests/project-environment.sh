#!/bin/bash
# Exercise actual direnv activation across fresh agent subprocesses.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIRENV_BINARY="$(command -v direnv)" || { echo 'direnv is required for project-environment tests' >&2; exit 1; }
TEST_REPO_ROOT="$ROOT"
source "$ROOT/tests/lib/harness.sh"
fixture_init
trap fixture_cleanup EXIT
unset _DOTFILES_ENV_LOADED _DOTFILES_BASE_ENV _PROFILE_LOADED
unset DIRENV_DIFF DIRENV_DIR DIRENV_FILE DIRENV_WATCHES DOTFILES_PROJECT_TEST
export DIRENV_CONFIG="$TEST_ROOT/direnv-config"
export PATH="$TEST_ROOT/bin:$TEST_SYSTEM_PATH"
ln -s "$DIRENV_BINARY" "$TEST_ROOT/bin/direnv"
for mapping in profile.sh:.profile bash.sh:.bashrc bash_profile:.bash_profile zshenv:.zshenv zprofile:.zprofile; do
    ln -s "$ROOT/entry/${mapping%%:*}" "$HOME/${mapping#*:}"
done
mkdir -p "$TEST_ROOT/project-a" "$TEST_ROOT/project-b" "$TEST_ROOT/blocked"
printf 'export DOTFILES_PROJECT_TEST=A\n' > "$TEST_ROOT/project-a/.envrc"
printf 'export DOTFILES_PROJECT_TEST=B\n' > "$TEST_ROOT/project-b/.envrc"
printf 'touch "%s"\n' "$TEST_ROOT/blocked-executed" > "$TEST_ROOT/blocked/.envrc"
direnv allow "$TEST_ROOT/project-a"
direnv allow "$TEST_ROOT/project-b"
export TEST_ROOT

for shell in bash zsh; do
    if [[ "$shell" == bash ]]; then args=(-lc); else args=(-dc); fi
    (
        cd "$TEST_ROOT/project-a"
        "$shell" "${args[@]}" '
            [[ "$DOTFILES_PROJECT_TEST" == A ]] || exit 61
            [[ "$_DOTFILES_ENV_LOADED" == 1 ]] || exit 62
            cd "$TEST_ROOT/project-b" || exit 63
            # An exported guard must not skip CWD-sensitive activation.
            bash -lc '\''[[ "$DOTFILES_PROJECT_TEST" == B ]]'\'' || exit 64
            zsh -dc '\''[[ "$DOTFILES_PROJECT_TEST" == B ]]'\'' || exit 65
            # Bare Bash deliberately inherits the parent environment.
            bash --noprofile --norc -c '\''[[ "$DOTFILES_PROJECT_TEST" == A ]]'\'' || exit 66
            cd "$TEST_ROOT/blocked" || exit 67
            bash -lc : || exit 68
            zsh -dc : || exit 69
        '
    ) || fail "$shell project environment transition"
done
[[ ! -e "$TEST_ROOT/blocked-executed" ]] || fail "unapproved .envrc executed"
printf 'project-environment: ok\n'
