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
            unset DOTFILES_THEME_BTOP_RESOLVED BTOP_THEME_CONFIG BTOP_THEME_DIR LAZYGIT_THEME_CONFIG
            btop plain; lazygit plain
            dstopall
        ')"
    [[ "$output" == *'claude|--model|sonnet|prompt'* ]] || fail "$shell claude flag splitting"
    [[ "$output" == *'claude|stop|job'* ]] || fail "$shell claude subcommand without flags"
    [[ "$output" == *'codex|--profile|work|exec|prompt'* ]] || fail "$shell codex flag splitting"
    [[ "$output" == *'opencode|run|--model|local|prompt'* ]] || fail "$shell opencode flag splitting"
    [[ "$output" == *'opencode|service|status'* ]] || fail "$shell opencode administrative flags"
    [[ "$output" == *'pi|--provider|test|prompt'* ]] || fail "$shell pi flag splitting"
    [[ "$output" == *'btop|plain'* && "$output" != *'btop|--config'* ]] || fail "$shell btop neutral fallback"
    [[ "$output" == *'lazygit|plain'* && "$output" != *'lazygit|--use-config-file'* ]] || fail "$shell lazygit neutral fallback"
    [[ "$output" == *'argument-recorder|stop|alpha|beta'* ]] || fail "$shell docker array handling"
}

run_shell_matrix bash
run_shell_matrix zsh

printf 'DOTFILES_RELOAD_MARKER=$(( ${DOTFILES_RELOAD_MARKER:-0} + 1 ))\n' > "$HOME/.bashrc"
HOME="$HOME" DOTFILES_DIR="$ROOT" bash --noprofile --norc -c \
    'source "$DOTFILES_DIR/shell/tools/general.sh"; reload; [[ "$DOTFILES_RELOAD_MARKER" == 1 ]]' \
    || fail "bash reload"
printf 'DOTFILES_RELOAD_MARKER=$(( ${DOTFILES_RELOAD_MARKER:-0} + 1 ))\n' > "$HOME/.zshrc"
HOME="$HOME" DOTFILES_DIR="$ROOT" zsh -dfc \
    'source "$DOTFILES_DIR/shell/tools/general.sh"; reload; [[ "$DOTFILES_RELOAD_MARKER" == 1 ]]' \
    || fail "zsh reload"

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

printf 'shell-behavior: ok\n'
