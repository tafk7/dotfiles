#!/bin/bash
# installers/install-antigravity.sh against a stand-in release manifest and
# tarball (file://): agy lands only when the tarball's SHA-512 matches, a
# working install is kept, --update fetches only another version, an agy from
# elsewhere on PATH is never shadowed, and the shell profile is never touched.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_REPO_ROOT="$ROOT"
source "$ROOT/tests/lib/harness.sh"
trap fixture_cleanup EXIT
fixture_init
export PATH="$HOME/.local/bin:$TEST_ROOT/bin:$TEST_SYSTEM_PATH"
mkdir -p "$TEST_ROOT/bin"

release="$TEST_ROOT/release"
manifest="$release/manifest.json"
mkdir -p "$release"
# make_release VERSION [SHA512]: a tarball holding one antigravity binary that
# prints VERSION, and a manifest naming it (with its SHA-512 unless given).
make_release() {
    local version="$1" sha
    mkdir -p "$release/build"
    printf '#!/bin/sh\n[ "${1:-}" = --version ] && echo "agy %s"\necho "$*" >> "%s/agy-calls"\n' \
        "$version" "$TEST_ROOT" > "$release/build/antigravity"
    chmod +x "$release/build/antigravity"
    tar -czf "$release/cli.tar.gz" -C "$release/build" antigravity
    sha="${2-$(sha512sum "$release/cli.tar.gz" | awk '{print $1}')}"
    printf '{"version": "%s", "url": "file://%s", "sha512": "%s"}\n' "$version" "$release/cli.tar.gz" "$sha" > "$manifest"
}
install_agy() { DOTFILES_ANTIGRAVITY_MANIFEST_URL="file://$manifest" "$ROOT/installers/install-antigravity.sh" "$@"; }
bin="$HOME/.local/bin/agy"
mkdir -p "$HOME"
for rc in .bashrc .profile .zshrc; do printf '# mine\n' > "$HOME/$rc"; done

# A fresh install verifies, installs and records the binary.
make_release 1.5.18
out="$(install_agy 2>&1)" || fail "fresh install failed: $out"
assert_eq "$("$bin" --version)" "agy 1.5.18" "installed version"
grep -q "^antigravity	yes	dotfiles	installed	" "$XDG_STATE_HOME/dotfiles/components.tsv" || fail "the install was not recorded"
observed="$("$ROOT/installers/install-antigravity.sh" --observe)"
[[ "$observed" == *"owner=dotfiles"* && "$observed" == *"ready=yes"* ]] || fail "observation: $observed"

# A working install is kept: exit 2.
make_release 1.6.0
rc=0; install_agy >/dev/null 2>&1 || rc=$?
assert_eq "$rc/$("$bin" --version)" "2/agy 1.5.18" "a rerun replaced a working install"

# --update installs the manifest's version, and is a no-op once current.
rc=0; install_agy --update >/dev/null 2>&1 || rc=$?
assert_eq "$rc/$("$bin" --version)" "0/agy 1.6.0" "--update"
rc=0; install_agy --update >/dev/null 2>&1 || rc=$?
assert_eq "$rc" 2 "--update when current"

# A checksum mismatch installs nothing; the working binary stays.
make_release 1.7.0 "$(printf 'a%.0s' {1..128})"
rc=0; out="$(install_agy --update 2>&1)" || rc=$?
assert_eq "$rc/$("$bin" --version)" "1/agy 1.6.0" "a bad SHA-512"
[[ "$out" == *"Checksum mismatch"* ]] || fail "no checksum error: $out"

# A manifest without a SHA-512, or with an odd version, is refused.
make_release 1.7.0 ""
rc=0; out="$(install_agy --update 2>&1)" || rc=$?
[[ $rc -eq 1 && "$out" == *"no SHA-512"* ]] || fail "missing sha512: $rc $out"
make_release '1.7;0'
rc=0; out="$(install_agy --update 2>&1)" || rc=$?
[[ $rc -eq 1 && "$out" == *"Unexpected version"* ]] || fail "odd version: $rc $out"

# A binary that is not the manifest's version is refused.
make_release 1.7.0
sed -i 's/{"version": "1.7.0"/{"version": "1.8.0"/' "$manifest"
rc=0; out="$(install_agy --update 2>&1)" || rc=$?
assert_eq "$rc/$("$bin" --version)" "1/agy 1.6.0" "a binary of another version"

# Only https and file:// are fetched, and a remote manifest may not point the
# tarball at a local file (a stand-in curl serves the manifest).
make_release 1.7.0
rc=0; out="$(DOTFILES_ANTIGRAVITY_MANIFEST_URL="http://example.invalid/m.json" "$ROOT/installers/install-antigravity.sh" --update 2>&1)" || rc=$?
[[ $rc -eq 1 && "$out" == *"Refusing to download from: http://"* ]] || fail "http manifest: $rc $out"
printf '#!/bin/sh\nwhile [ "$1" != --output ]; do shift; done\ncp "%s" "$2"\n' "$manifest" > "$TEST_ROOT/bin/curl"
chmod +x "$TEST_ROOT/bin/curl"
rc=0; out="$(DOTFILES_ANTIGRAVITY_MANIFEST_URL="https://example.invalid/m.json" "$ROOT/installers/install-antigravity.sh" --update 2>&1)" || rc=$?
[[ $rc -eq 1 && "$out" == *"Refusing a local file from a remote manifest"* ]] || fail "remote manifest, local tarball: $rc $out"
rm -f "$TEST_ROOT/bin/curl"

# It never ran agy install or agy update, and the shell profile is untouched.
grep -Eq '^(install|update)' "$TEST_ROOT/agy-calls" 2>/dev/null && fail "ran agy install or update"
for rc in .bashrc .profile .zshrc; do assert_eq "$(<"$HOME/$rc")" "# mine" "$rc changed"; done

# An agy from elsewhere on PATH is never shadowed.
rm -f "$bin"
printf '#!/bin/sh\necho "agy 9.9.9"\n' > "$TEST_ROOT/bin/agy"
chmod +x "$TEST_ROOT/bin/agy"
rc=0; out="$(install_agy 2>&1)" || rc=$?
[[ $rc -eq 2 && ! -e "$bin" && "$out" == *"externally-managed agy"* ]] || fail "shadowed an external agy: $rc $out"
rm -f "$TEST_ROOT/bin/agy"

# The shell wrapper refuses agy update and agy install and passes the rest.
make_release 1.7.0
install_agy >/dev/null 2>&1 || fail "reinstall failed"
out="$(bash -c 'source "$1/shell/tools/antigravity.sh"; agy update; echo "rc=$?"; agy models' _ "$ROOT" 2>&1)"
[[ "$out" == *"dotfiles upgrade antigravity"*"rc=64"* ]] || fail "wrapper did not refuse agy update: $out"
assert_eq "$(tail -n1 "$TEST_ROOT/agy-calls")" "models" "wrapper passes other commands"

printf 'install-antigravity: ok\n'
