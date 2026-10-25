#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_REPO_ROOT="$ROOT"
source "$ROOT/tests/lib/harness.sh"
trap fixture_cleanup EXIT
fixture_init

mkdir -p "$TEST_ROOT/bin" "$TEST_ROOT/projects one/repo/.git" "$TEST_ROOT/projects-two/repo/.git"
cat > "$TEST_ROOT/bin/argument-recorder" <<'EOF'
#!/bin/sh
printf '%s' "$(basename "$0")"
for arg do printf '|%s' "$arg"; done
printf '\n'
EOF
chmod +x "$TEST_ROOT/bin/argument-recorder"
for command in claude codex opencode pi btop lazygit; do ln -s argument-recorder "$TEST_ROOT/bin/$command"; done
cat > "$TEST_ROOT/bin/docker" <<'EOF'
#!/bin/sh
if [ "$1" = ps ]; then printf '%s\n' alpha beta; else exec argument-recorder "$@"; fi
EOF
chmod +x "$TEST_ROOT/bin/docker"
export PATH="$TEST_ROOT/bin:$TEST_SYSTEM_PATH"
export PROJECTS_DIRS="$TEST_ROOT/projects one:$TEST_ROOT/projects-two"

run_shell_matrix() {
    local shell="$1" output
    output="$(HOME="$HOME" PATH="$PATH" PROJECTS_DIRS="$PROJECTS_DIRS" DOTFILES_DIR="$ROOT" \
        "$shell" -c '
            source "$DOTFILES_DIR/shell/tools/nav.sh"
            source "$DOTFILES_DIR/shell/tools/docker.sh"
            source "$DOTFILES_DIR/shell/tools/general.sh"
            source "$DOTFILES_DIR/shell/tools/claude.sh"
            source "$DOTFILES_DIR/shell/tools/codex.sh"
            source "$DOTFILES_DIR/shell/tools/opencode.sh"
            source "$DOTFILES_DIR/shell/tools/pi.sh"
            roots="$(_dotfiles_iter_project_dirs)"
            [[ "$roots" == *"projects one"* && "$roots" == *"projects-two"* ]] || exit 31
            CLAUDE_FLAGS="--model sonnet"; CODEX_FLAGS="--profile work"
            OPENCODE_FLAGS="--model local"; PI_FLAGS="--provider test"
            claude prompt; claude stop job; codex exec prompt; opencode run prompt; opencode service status; pi prompt
            btop plain; lazygit plain
            dstopall
            mkdir -p "$HOME/a/b/c" && cd "$HOME/a/b/c"
            .. && [[ "$PWD" == "$HOME/a/b" ]] || exit 32
            .. 2 && [[ "$PWD" == "$HOME" ]] || exit 33
            ! .. x 2>/dev/null || exit 34
        ')"
    [[ "$output" == *'claude|--model|sonnet|prompt'* ]] || fail "$shell claude flag splitting"
    [[ "$output" == *'claude|stop|job'* ]] || fail "$shell claude subcommand without flags"
    [[ "$output" == *'codex|--profile|work|exec|prompt'* ]] || fail "$shell codex flag splitting"
    [[ "$output" == *'opencode|run|--model|local|prompt'* ]] || fail "$shell opencode flag splitting"
    [[ "$output" == *'opencode|service|status'* ]] || fail "$shell opencode administrative flags"
    [[ "$output" == *'pi|--provider|test|prompt'* ]] || fail "$shell pi flag splitting"
    [[ "$output" == *"btop|--config|$XDG_CACHE_HOME/dotfiles/btop.conf|plain"* ]] || fail "$shell btop palette config"
    grep -Fxq 'color_theme = "TTY"' "$XDG_CACHE_HOME/dotfiles/btop.conf" || fail "$shell btop config does not select the TTY theme"
    [[ "$output" == *'lazygit|plain'* ]] || fail "$shell lazygit passthrough"
    [[ "$output" == *'argument-recorder|stop|alpha|beta'* ]] || fail "$shell docker array handling"
}

run_shell_matrix bash
run_shell_matrix zsh

# reload --soft re-sources the startup files in place, with every guard cleared.
printf 'DOTFILES_RELOAD_MARKER=$(( ${DOTFILES_RELOAD_MARKER:-0} + 1 ))\n' > "$HOME/.bashrc"
HOME="$HOME" DOTFILES_DIR="$ROOT" _DOTFILES_BASE_ENV=1 _DOTFILES_ENV_LOADED=1 bash --noprofile --norc -c \
    'source "$DOTFILES_DIR/shell/tools/general.sh"; reload --soft
     [[ "$DOTFILES_RELOAD_MARKER" == 1 && -z "${_DOTFILES_BASE_ENV:-}${_DOTFILES_ENV_LOADED:-}" ]]' \
    || fail "bash soft reload"
printf 'DOTFILES_RELOAD_ENV=$(( ${DOTFILES_RELOAD_ENV:-0} + 1 ))\n' > "$HOME/.zshenv"
printf 'DOTFILES_RELOAD_MARKER=$(( ${DOTFILES_RELOAD_MARKER:-0} + 1 ))\n' > "$HOME/.zshrc"
HOME="$HOME" DOTFILES_DIR="$ROOT" _DOTFILES_BASE_ENV=1 _DOTFILES_ENV_LOADED=1 zsh -dfc \
    'source "$DOTFILES_DIR/shell/tools/general.sh"; reload --soft
     [[ "$DOTFILES_RELOAD_ENV" == 1 && "$DOTFILES_RELOAD_MARKER" == 1 && -z "${_DOTFILES_BASE_ENV:-}${_DOTFILES_ENV_LOADED:-}" ]]' \
    || fail "zsh soft reload"
rm "$HOME/.bashrc" "$HOME/.zshenv" "$HOME/.zshrc"

# reload replaces the shell with a fresh login shell: the directory stays,
# Layer 0 recomputes over stale inherited values, and unexported state is gone.
# The replacement shell reads its commands from the same stdin.
reload_home="$TEST_ROOT/reload-home"
mkdir -p "$reload_home" "$TEST_ROOT/reload dir"
for mapping in profile.sh:.profile bash.sh:.bashrc bash_profile:.bash_profile zshenv:.zshenv zprofile:.zprofile; do
    ln -s "$ROOT/entry/${mapping%%:*}" "$reload_home/${mapping#*:}"
done
for shell in bash zsh; do
    if [[ "$shell" == bash ]]; then args=(--noprofile --norc -c); else args=(-dfc); fi
    reloaded="$(cd "$TEST_ROOT/reload dir" && printf '%s\n' 'printf "%s|%s|%s\n" "$PWD" "${UNEXPORTED:-}" "$PROJECTS_DIRS"' \
        | env HOME="$reload_home" ZDOTDIR="$reload_home" PATH="$PATH" DOTFILES_DIR="$ROOT" PROJECTS_DIRS=stale \
            _DOTFILES_BASE_ENV=1 _DOTFILES_ENV_LOADED=1 "$shell" "${args[@]}" \
            'source "$DOTFILES_DIR/shell/tools/general.sh"; UNEXPORTED=1; reload; echo not-replaced')"
    assert_eq "$reloaded" "$TEST_ROOT/reload dir||$reload_home/projects:$reload_home/work:$reload_home/dev:$reload_home/code:$reload_home/src" "$shell reload"
    status=0
    HOME="$reload_home" DOTFILES_DIR="$ROOT" "$shell" "${args[@]}" \
        'source "$DOTFILES_DIR/shell/tools/general.sh"; sleep 5 & reload 2>/dev/null; s=$?; kill $! 2>/dev/null; exit $s' \
        || status=$?
    assert_eq "$status" 1 "$shell reload with a background job"
done

export TEST_ROOT
# Optional Python tools are discovered at invocation, including after a PATH
# change. No startup probes are needed.
for shell in bash zsh; do
    if [[ "$shell" == bash ]]; then args=(--noprofile --norc -c); else args=(-dfc); fi
    "$shell" "${args[@]}" '
        source "$DOTFILES_DIR/shell/tools/python.sh"
        # Install the tools only after sourcing: lazy resolution sees them.
        mkdir -p "$HOME/new-tools"
        ln -sf "$TEST_ROOT/bin/argument-recorder" "$HOME/new-tools/black"
        ln -sf "$TEST_ROOT/bin/argument-recorder" "$HOME/new-tools/ruff"
        export PATH="$HOME/new-tools:$PATH"
        [[ "$(fmt --check)" == "black|.|--check" ]] || exit 51
        [[ "$(lint --select E)" == "ruff|check|.|--select|E" ]] || exit 52
        [[ "$(lintf --unsafe-fixes)" == "ruff|check|.|--fix|--unsafe-fixes" ]] || exit 53
    ' || fail "$shell deferred Python tools"
done

# Interactive prompts carry an OSC 133;A mark for tmux prompt jumps, after any
# PROMPT_COMMAND step that rebuilds PS1; agent (non-interactive) shells get none.
mkdir -p "$TEST_ROOT/zdot"
printf 'source "%s/entry/zsh.sh"\n' "$ROOT" > "$TEST_ROOT/zdot/.zshrc"
bash_prompt="$(env -u SSH_CONNECTION HOME="$HOME" PATH="$PATH" bash --rcfile "$ROOT/entry/bash.sh" -i -c \
    'PS1=plain; eval "$PROMPT_COMMAND"; eval "$PROMPT_COMMAND"; printf %s "$PS1"' 2>/dev/null)"
[[ "$bash_prompt" == '\[\e]133;A\e\\\]plain' ]] || fail "bash prompt mark: $bash_prompt"
zsh_prompt="$(env -u SSH_CONNECTION HOME="$HOME" PATH="$PATH" ZDOTDIR="$TEST_ROOT/zdot" zsh -i -c 'print -rn -- "$PROMPT"' 2>/dev/null)"
[[ "$zsh_prompt" == $'%{\e]133;A\e\\%}'* ]] || fail "zsh prompt mark: $zsh_prompt"
HOME="$HOME" PATH="$PATH" bash -c 'source "$1"; ! declare -F _dotfiles_prompt_mark && [[ "${PROMPT_COMMAND:-}" != *133* ]]' _ \
    "$ROOT/entry/bash.sh" >/dev/null || fail "non-interactive bash got the prompt mark"

printf 'shell-behavior: ok\n'
