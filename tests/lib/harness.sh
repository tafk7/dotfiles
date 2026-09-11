#!/bin/bash
set -euo pipefail

TEST_REPO_ROOT="${TEST_REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
TEST_ROOT="${TEST_ROOT:-$(mktemp -d)}"
TEST_SYSTEM_PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

fixture_init() {
    mkdir -p "$TEST_ROOT/home" "$TEST_ROOT/config" "$TEST_ROOT/data" \
        "$TEST_ROOT/state" "$TEST_ROOT/cache" "$TEST_ROOT/tmp" "$TEST_ROOT/bin" \
        "$TEST_ROOT/tmux"
    export HOME="$TEST_ROOT/home"
    export XDG_CONFIG_HOME="$TEST_ROOT/config"
    export XDG_DATA_HOME="$TEST_ROOT/data"
    export XDG_STATE_HOME="$TEST_ROOT/state"
    export XDG_CACHE_HOME="$TEST_ROOT/cache"
    export TMPDIR="$TEST_ROOT/tmp"
    export TMUX_TMPDIR="$TEST_ROOT/tmux"
    export DOTFILES_DIR="$TEST_REPO_ROOT"
    export DOTFILES_BACKUP_PREFIX="$TEST_ROOT/backups"
}

fixture_cleanup() {
    [[ -n "${TEST_ROOT:-}" && "$TEST_ROOT" == /tmp/* ]] && /bin/rm -rf -- "$TEST_ROOT"
}

fixture_snapshot() {
    local root="$1"
    find "$root" -path "$root/.git" -prune -o -printf '%P\t%y\t%m\t%s\t%T@' \
        -exec sh -c 'for f do if [ -f "$f" ]; then sha256sum "$f" | cut -d" " -f1; else printf "%s\n" -; fi; done' sh {} + \
        | LC_ALL=C sort | sha256sum | awk '{print $1}'
}

fixture_managed_snapshot() {
    {
        fixture_snapshot "$HOME"
        fixture_snapshot "$XDG_CONFIG_HOME"
        fixture_snapshot "$XDG_DATA_HOME"
        fixture_snapshot "$XDG_STATE_HOME"
        fixture_snapshot "$XDG_CACHE_HOME"
        [[ ! -e "$DOTFILES_BACKUP_PREFIX" ]] || fixture_snapshot "$DOTFILES_BACKUP_PREFIX"
    } | sha256sum | awk '{print $1}'
}

install_mutation_spies() {
    local command
    export DOTFILES_MUTATION_LOG="$TEST_ROOT/mutations.log"
    : > "$DOTFILES_MUTATION_LOG"
    for command in mkdir mv rm ln cp chmod install apt apt-get dpkg tee systemctl sudo; do
        printf '#!/bin/sh\nprintf "%%s\\t%%s\\n" "%s" "$*" >> "$DOTFILES_MUTATION_LOG"\nexit 97\n' "$command" \
            > "$TEST_ROOT/bin/$command"
        /bin/chmod +x "$TEST_ROOT/bin/$command"
    done
    export PATH="$TEST_ROOT/bin:$TEST_SYSTEM_PATH"
}

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
assert_eq() { [[ "$1" == "$2" ]] || fail "expected '$2', got '$1'${3:+ ($3)}"; }
