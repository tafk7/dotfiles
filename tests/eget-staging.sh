#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_REPO_ROOT="$ROOT"
source "$ROOT/tests/lib/harness.sh"
trap fixture_cleanup EXIT
fixture_init
export PATH="$HOME/.local/bin:$TEST_SYSTEM_PATH"
mkdir -p "$HOME/.local/bin" "$TEST_ROOT/artifacts"
export EGET_ARTIFACTS="$TEST_ROOT/artifacts" EGET_ARGS="$TEST_ROOT/eget-args"

# The fake eget records its arguments and writes the prepared artifact named
# after its --to target, without the execute bit (as eget leaves a bare binary).
cat > "$HOME/.local/bin/eget" <<'EOF'
#!/bin/sh
if [ "${1:-}" = --version ]; then echo 'eget 1.3.4'; exit 0; fi
printf '%s\n' "$@" > "$EGET_ARGS"
[ "${EGET_TEST_FAIL:-0}" = 0 ] || exit 42
while [ $# -gt 0 ]; do
    [ "$1" = --to ] && { to="$2"; shift; }
    shift
done
[ -d "$(dirname "$to")" ] || exit 43
cat "$EGET_ARTIFACTS/$(basename "$to")" > "$to"
EOF
chmod +x "$HOME/.local/bin/eget"

# artifact BINARY OUTPUT: the binary the next download extracts.
artifact() {
    printf '#!/bin/sh\n[ "${1:-}" = --version ] && echo "%s"\n' "$2" > "$TEST_ROOT/artifacts/$1"
}
digest() { sha256sum "$1" | awk '{print $1}'; }
# lock NAME TAG [IDENTITY]: versions.lock rows for both architectures. The
# identity defaults to the prepared artifact's digest.
lock() {
    local name="$1" tag="$2" identity="${3:-}" arch
    [[ -n "$identity" ]] || identity="sha256:$(digest "$TEST_ROOT/artifacts/${TOOL_BINARY[$name]}")"
    for arch in x86_64 aarch64; do
        printf '%s\t%s\t%s\texample/%s\t%s-%s.tar.gz\t%s\t%s-dir/%s\t%s\n' \
            "$name" "$arch" "$tag" "$name" "$name" "$arch" "$asset_sha" "$name" "${TOOL_BINARY[$name]}" "$identity"
    done > "$DOTFILES_VERSIONS_LOCK"
}
asset_sha="$(printf 'a%.0s' {1..64})"
# tool NAME [BINARY]: register one eget tool as the only one.
tool() {
    TOOL_METHOD=(["$1"]=eget)
    TOOL_BINARY=(["$1"]="${2:-$1}")
    TOOL_TIER=(["$1"]=bash)
    TOOL_PLATFORM=(["$1"]=ubuntu)
    TOOL_ARCHES=(["$1"]='x86_64,aarch64')
    TOOL_OWNERSHIP_ROOTS=(["$1"]="$HOME/.local/bin")
    TOOL_UPDATE_CONTRACT=(["$1"]=staged-release)
    INSTALL_OK=() INSTALL_SKIP=() INSTALL_FAIL=()
}

source "$ROOT/lib/install.sh"
run_installer() { return 0; }
tier_includes() { return 0; }
DOTFILES_DIR="$TEST_ROOT/repo"
DOTFILES_VERSIONS_LOCK="$DOTFILES_DIR/versions.lock"
mkdir -p "$DOTFILES_DIR"

tool demo
printf '#!/bin/sh\n[ "${1:-}" = --version ] && echo "demo old"\n' > "$HOME/.local/bin/demo"
chmod +x "$HOME/.local/bin/demo"
old_hash="$(digest "$HOME/.local/bin/demo")"
artifact demo "demo new"
lock demo v1
FORCE_REINSTALL=true
ledger_record demo yes dotfiles installed old "$HOME/.local/bin/demo" test

export EGET_TEST_FAIL=1
if install_eget_tools >/dev/null 2>&1; then fail "failed staged download reported success"; fi
assert_eq "$(digest "$HOME/.local/bin/demo")" "$old_hash" "failed update replaced working binary"
assert_eq "$("$HOME/.local/bin/demo" --version)" "demo old"
failed_line="$(ledger_line demo)"
[[ "$failed_line" == $'demo\tyes\tdotfiles\tupdate-failed\t'* ]] \
    || fail "failed update did not retain observed working component"

export EGET_TEST_FAIL=0
tool demo
FORCE_REINSTALL=false
install_eget_tools >/dev/null
assert_eq "$("$HOME/.local/bin/demo" --version)" "demo new"
[[ "$(ledger_line demo)" == *"pin=v1 sha256=$(digest "$TEST_ROOT/artifacts/demo")"* ]] || fail "staged artifact pin/hash not recorded"

# A bundled/private rg elsewhere on PATH is not a durable system installation.
# It must not suppress installation of the pinned dotfiles-owned ripgrep.
private_bin="$TEST_ROOT/.codex/private/bin"
mkdir -p "$private_bin"
printf '#!/bin/sh\n[ "${1:-}" = --version ] && echo "ripgrep private"\n' > "$private_bin/rg"
chmod +x "$private_bin/rg"
PATH="$private_bin:$HOME/.local/bin:$TEST_SYSTEM_PATH"
tool ripgrep rg
artifact rg "ripgrep 15.2.0"
lock ripgrep 15.2.0
install_eget_tools >/dev/null
[[ -x "$HOME/.local/bin/rg" ]] || fail "private Codex rg suppressed managed ripgrep"
assert_eq "$("$HOME/.local/bin/rg" --version)" "ripgrep 15.2.0"
tool_is_present ripgrep || fail "managed ripgrep was hidden by private PATH entry"
tool ripgrep rg
rm -f "$EGET_ARGS"
install_eget_tools >/dev/null
[[ ! -e "$EGET_ARGS" ]] || fail "the locked build was downloaded again"
[[ "$(ledger_line ripgrep)" == $'ripgrep\tyes\tdotfiles\tinstalled\t'* ]] \
    || fail "managed ripgrep ownership was not retained"
PATH="$HOME/.local/bin:$TEST_SYSTEM_PATH"

# Current means the locked digest, not a version string: a binary that prints
# the pinned version but is another build is replaced, and the locked build is
# kept however it reports its version.
tool eza
printf '#!/bin/sh\necho "eza - A modern replacement for ls"\necho "v0.23.4 [+git]"\n' > "$HOME/.local/bin/eza"
chmod +x "$HOME/.local/bin/eza"
ledger_record eza yes dotfiles installed v0.23.4 "$HOME/.local/bin/eza" test
artifact eza "eza locked"
lock eza v0.23.4
install_eget_tools >/dev/null
assert_eq "$("$HOME/.local/bin/eza" --version)" "eza locked" "a version-string match kept another build"
tool eza
rm -f "$EGET_ARGS"
install_eget_tools >/dev/null
[[ ! -e "$EGET_ARGS" ]] || fail "the locked build triggered a download"

# An archive that passes its checksum but holds another binary is refused.
tool eza
artifact eza "eza tampered"
before="$(digest "$HOME/.local/bin/eza")"
FORCE_REINSTALL=true
if install_eget_tools >/dev/null 2>&1; then fail "an extracted binary off the lock was accepted"; fi
assert_eq "$(digest "$HOME/.local/bin/eza")" "$before" "a binary off the lock replaced the installed one"
FORCE_REINSTALL=false

mkdir -p "$HOME/.local/demo/bin" "$TEST_ROOT/bad-tree"
printf '#!/bin/sh\necho old-tree\n' > "$HOME/.local/demo/bin/demo"
chmod +x "$HOME/.local/demo/bin/demo"
before_tree="$(digest "$HOME/.local/demo/bin/demo")"
if atomic_replace_tree demo "$TEST_ROOT/bad-tree" "$HOME/.local/demo" bin/demo >/dev/null 2>&1; then
    fail "invalid staged tree was accepted"
fi
assert_eq "$(digest "$HOME/.local/demo/bin/demo")" "$before_tree" "invalid tree replaced working install"

# The download is the locked asset by URL, verified against its checksum, with
# the locked member extracted: no repository slug, so no GitHub API call.
tool fd
artifact fd "fd 10.4.2"
lock fd v10.4.2
DOTFILES_TEST_ARCH=aarch64 install_eget_tools >/dev/null
eget_args="$(paste -sd ' ' "$EGET_ARGS")"
[[ "$eget_args" == "--file fd-dir/fd --to "*"/.local/bin/fd --verify-sha256 $asset_sha https://github.com/example/fd/releases/download/v10.4.2/fd-aarch64.tar.gz" ]] \
    || fail "eget was not given the locked asset: $eget_args"
[[ -x "$HOME/.local/bin/fd" ]] || fail "a downloaded binary without its execute bit was not made executable"

# A tool the lock has no row for fails before any download.
rm -f "$EGET_ARGS" "$HOME/.local/bin/fd"
tool fd
grep -v $'^fd\taarch64' "$DOTFILES_VERSIONS_LOCK" > "$TEST_ROOT/lock" && mv "$TEST_ROOT/lock" "$DOTFILES_VERSIONS_LOCK"
if DOTFILES_TEST_ARCH=aarch64 install_eget_tools >/dev/null 2>&1; then fail "a tool without a lock row was installed"; fi
[[ ! -e "$EGET_ARGS" ]] || fail "eget ran without a lock row"

printf 'eget-staging: ok\n'
