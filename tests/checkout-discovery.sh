#!/bin/bash
# Checkout discovery order (docs/architecture.md): entry symlink, inherited
# valid DOTFILES_DIR, recorded install-path, then ~/dev/dotfiles. Every case
# runs with a scrubbed environment against the same fixture checkouts.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_ROOT="$(mktemp -d)"
trap 'rm -rf "$TEST_ROOT"' EXIT
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

# Fixture checkouts: "linked" carries the real entry files; every checkout has
# stub Layer 0 files that record which checkout was loaded.
for name in linked inherited recorded; do
    mkdir -p "$TEST_ROOT/$name/shell"
    printf 'DOTFILES_LOADED_FROM=%s\n' "$name" > "$TEST_ROOT/$name/shell/env.sh"
    : > "$TEST_ROOT/$name/shell/env-runtime.sh"
done
mkdir -p "$TEST_ROOT/linked/entry"
cp "$ROOT/entry/bash.sh" "$ROOT/entry/profile.sh" "$ROOT/entry/zshenv" "$TEST_ROOT/linked/entry/"
mkdir -p "$TEST_ROOT/not-a-checkout"

HOME="$TEST_ROOT/home"
STATE="$TEST_ROOT/state"

# install_entries symlink|copy
install_entries() {
    rm -rf "$HOME"; mkdir -p "$HOME"
    local mapping
    for mapping in bash.sh:.bashrc profile.sh:.profile zshenv:.zshenv; do
        if [[ "$1" == symlink ]]; then
            ln -s "$TEST_ROOT/linked/entry/${mapping%%:*}" "$HOME/${mapping#*:}"
        else
            cp "$TEST_ROOT/linked/entry/${mapping%%:*}" "$HOME/${mapping#*:}"
        fi
    done
}

# record_install_path PATH|none
record_install_path() {
    rm -rf "$STATE"; mkdir -p "$STATE/dotfiles"
    [[ "$1" == none ]] || printf '%s\n' "$1" > "$STATE/dotfiles/install-path"
}

# discover SHELL [INHERITED] → "DOTFILES_DIR|DOTFILES_LOADED_FROM"
discover() {
    local shell="$1" inherited="${2:-}" report
    report='printf "%s|%s" "${DOTFILES_DIR-unset}" "${DOTFILES_LOADED_FROM-none}"'
    local -a env_args=(env -i HOME="$HOME" PATH="$PATH" XDG_STATE_HOME="$STATE")
    [[ -z "$inherited" ]] || env_args+=(DOTFILES_DIR="$inherited")
    case "$shell" in
        bash) "${env_args[@]}" bash --noprofile --norc -c "source ~/.bashrc; $report" ;;
        zsh) "${env_args[@]}" zsh -dc "$report" ;;
        dash) "${env_args[@]}" dash -c ". ~/.profile; $report" ;;
    esac
}

expect() {
    local label="$1" expected="$2" shell="$3"; shift 3
    local actual
    actual="$(discover "$shell" "$@")" || fail "$shell $label: startup failed"
    [[ "$actual" == "$expected" ]] || fail "$shell $label: expected '$expected', got '$actual'"
}

for shell in bash zsh; do
    # 1. The symlink wins, even over a different valid inherited checkout.
    install_entries symlink; record_install_path "$TEST_ROOT/recorded"
    expect "symlink" "$TEST_ROOT/linked|linked" "$shell"
    expect "symlink beats inherited" "$TEST_ROOT/linked|linked" "$shell" "$TEST_ROOT/inherited"

    # 2. A flattened copy keeps a valid inherited checkout.
    install_entries copy
    expect "inherited" "$TEST_ROOT/inherited|inherited" "$shell" "$TEST_ROOT/inherited"

    # 3. Otherwise the recorded install path, also replacing an invalid inherited value.
    expect "install-path" "$TEST_ROOT/recorded|recorded" "$shell"
    expect "invalid inherited" "$TEST_ROOT/recorded|recorded" "$shell" "$TEST_ROOT/not-a-checkout"

    # 4. Otherwise the default, which need not exist.
    record_install_path none
    expect "default" "$HOME/dev/dotfiles|none" "$shell"
done

# dash reads ~/.profile but never runs checkout discovery or Layer 0.
if command -v dash >/dev/null 2>&1; then
    install_entries symlink; record_install_path "$TEST_ROOT/recorded"
    expect "POSIX profile" "unset|none" dash
fi

printf 'checkout-discovery: ok\n'
