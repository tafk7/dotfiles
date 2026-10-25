#!/bin/bash
# Owned variables resolve as repo default, then ~/.shell.env, then direnv, in
# every startup-reading shell; inherited values never win.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIRENV_BINARY="$(command -v direnv)" || { echo 'direnv is required for environment-layers tests' >&2; exit 1; }
TEST_REPO_ROOT="$ROOT"
source "$ROOT/tests/lib/harness.sh"
fixture_init
trap fixture_cleanup EXIT
unset _DOTFILES_ENV_LOADED _DOTFILES_BASE_ENV _PROFILE_LOADED
unset DIRENV_DIFF DIRENV_DIR DIRENV_FILE DIRENV_WATCHES
export DIRENV_CONFIG="$TEST_ROOT/direnv-config"
ln -s "$DIRENV_BINARY" "$TEST_ROOT/bin/direnv"
printf '#!/bin/sh\n' > "$TEST_ROOT/bin/nvim"
chmod +x "$TEST_ROOT/bin/nvim"
export PATH="$TEST_ROOT/bin:$TEST_SYSTEM_PATH"
for mapping in profile.sh:.profile bash.sh:.bashrc bash_profile:.bash_profile zshenv:.zshenv zsh.sh:.zshrc zprofile:.zprofile; do
    ln -s "$ROOT/entry/${mapping%%:*}" "$HOME/${mapping#*:}"
done
mkdir -p "$TEST_ROOT/plain" "$TEST_ROOT/project"
printf 'export PROJECTS_DIRS=project\n' > "$TEST_ROOT/project/.envrc"
direnv allow "$TEST_ROOT/project"
default_less="$(sed -n "s/^ *export LESS='\\(.*\\)'$/\\1/p" "$ROOT/entry/profile.sh")"
default_projects="$HOME/projects:$HOME/work:$HOME/dev:$HOME/code:$HOME/src"

# Prints EDITOR|PROJECTS_DIRS|LESS|RIPGREP_CONFIG_PATH|LOCAL_ONLY for each kind
# of shell, started with stale inherited values.
probe() {
    local kind="$1" dir="$2" report='printf "%s|%s|%s|%s|%s\n" "$EDITOR" "$PROJECTS_DIRS" "$LESS" "$RIPGREP_CONFIG_PATH" "${LOCAL_ONLY:-}"'
    local -a cmd
    case "$kind" in
        bash-login) cmd=(bash -lc "$report") ;;
        bash-interactive) cmd=(bash -ic "$report") ;;
        zsh) cmd=(zsh -c "$report") ;;
        zsh-interactive) cmd=(zsh -ic "$report") ;;
    esac
    (cd "$dir" && env -u SSH_CONNECTION HOME="$HOME" ZDOTDIR="$HOME" PATH="$PATH" \
        EDITOR=inherited PROJECTS_DIRS=inherited LESS=inherited RIPGREP_CONFIG_PATH=inherited \
        "${cmd[@]}" 2>/dev/null | tail -n1)
}

kinds=(bash-login bash-interactive zsh zsh-interactive)
for kind in "${kinds[@]}"; do
    assert_eq "$(probe "$kind" "$TEST_ROOT/plain")" "nvim|$default_projects|$default_less|$HOME/.ripgreprc|" "$kind repo defaults"
done

printf 'export EDITOR=machine-editor\nexport PROJECTS_DIRS=machine\n' > "$HOME/.shell.env"
printf 'export LOCAL_ONLY=interactive\n' > "$HOME/.shell.local"
for kind in "${kinds[@]}"; do
    local_only=""; [[ "$kind" == *interactive ]] && local_only=interactive
    assert_eq "$(probe "$kind" "$TEST_ROOT/plain")" "machine-editor|machine|$default_less|$HOME/.ripgreprc|$local_only" "$kind machine layer"
    assert_eq "$(probe "$kind" "$TEST_ROOT/project")" "machine-editor|project|$default_less|$HOME/.ripgreprc|$local_only" "$kind project layer"
done

printf 'environment-layers: ok\n'
