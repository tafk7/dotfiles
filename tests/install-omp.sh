#!/bin/bash
# installers/install-omp.sh against a local stand-in for the GitHub release:
# the binary lands only when its SHA-256 matches the release's sums, a working
# install is kept, an omp from elsewhere on PATH is never shadowed, and
# --update hands over to `omp update`.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_REPO_ROOT="$ROOT"
source "$ROOT/tests/lib/harness.sh"
trap fixture_cleanup EXIT
fixture_init
export PATH="$HOME/.local/bin:$TEST_ROOT/bin:$TEST_SYSTEM_PATH"
mkdir -p "$TEST_ROOT/bin"

release="$TEST_ROOT/release"
mkdir -p "$release"
# A stand-in omp: --version prints its version; `update` rewrites itself to
# the version in $TEST_ROOT/next, as omp update replaces its binary.
make_release() {
    local version="$1" asset
    printf 'v%s\n' "$version" > "$release/TAG"
    for asset in omp-linux-x64 omp-linux-arm64; do
        cat > "$release/$asset" <<EOF
#!/bin/sh
case "\${1:-}" in
    --version) echo "omp $version" ;;
    update) next="\$(cat "$TEST_ROOT/next")"; sed -i "s/omp $version/omp \$next/" "\$0" ;;
esac
EOF
    done
    (cd "$release" && sha256sum omp-linux-x64 omp-linux-arm64 > SHA256SUMS.txt)
}
install_omp() { DOTFILES_OMP_RELEASE_DIR="$release" "$ROOT/installers/install-omp.sh" "$@"; }
bin="$HOME/.local/bin/omp"

# A launcher earlier on PATH cannot be shadowed and need not run before setup.
launcher="$TEST_ROOT/launcher"
mkdir -p "$launcher"
printf '#!/bin/sh\necho called >> "%s/launcher-calls"\nexit 97\n' "$TEST_ROOT" > "$launcher/omp"
chmod +x "$launcher/omp"
export PATH="$launcher:$PATH"

# A fresh install verifies, installs and records the binary.
make_release 19.2.1
out="$(install_omp 2>&1)" || fail "fresh install failed: $out"
assert_eq "$("$bin" --version)" "omp 19.2.1" "installed version"
[[ "$out" == *"Installing Oh My Pi v19.2.1"* ]] || fail "install did not name the release: $out"
grep -q "^omp	yes	dotfiles	installed	" "$XDG_STATE_HOME/dotfiles/components.tsv" || fail "the install was not recorded"

observed="$("$ROOT/installers/install-omp.sh" --observe)"
[[ "$observed" == *"path=$bin"* && "$observed" == *"owner=dotfiles"* && "$observed" == *"ready=yes"* ]] || fail "observed the launcher: $observed"
bash -c 'source "$1/lib/install.sh"; tool_is_present omp; record_component_outcome omp skip' _ "$ROOT" \
    || fail "presence or outcome recording followed the launcher"

# A working install is kept: exit 2, nothing downloaded.
make_release 19.3.0
rc=0; install_omp >/dev/null 2>&1 || rc=$?
assert_eq "$rc/$("$bin" --version)" "2/omp 19.2.1" "a rerun replaced a working install"

# --update runs omp's own updater: 0 when it moved, 2 when already current.
printf '19.4.0\n' > "$TEST_ROOT/next"
rc=0; install_omp --update >/dev/null 2>&1 || rc=$?
assert_eq "$rc/$("$bin" --version)" "0/omp 19.4.0" "--update"
printf '19.4.0\n' > "$TEST_ROOT/next"
rc=0; install_omp --update >/dev/null 2>&1 || rc=$?
assert_eq "$rc" 2 "--update when current"
[[ ! -e "$TEST_ROOT/launcher-calls" ]] || fail "probed a launcher during install or update"
export PATH="$HOME/.local/bin:$TEST_ROOT/bin:$TEST_SYSTEM_PATH"

# A checksum mismatch installs nothing; the working binary stays.
make_release 19.5.0
for asset in omp-linux-x64 omp-linux-arm64; do printf '\n# tampered\n' >> "$release/$asset"; done
rc=0; out="$(install_omp --force 2>&1)" || rc=$?
assert_eq "$rc/$("$bin" --version)" "1/omp 19.4.0" "a tampered binary"
[[ "$out" == *"Checksum mismatch"* ]] || fail "no checksum error: $out"

# A release whose sums do not list the binary is refused.
make_release 19.5.0
printf '%s  LICENSE\n' "$(printf '0%.0s' {1..64})" > "$release/SHA256SUMS.txt"
rc=0; out="$(install_omp --force 2>&1)" || rc=$?
[[ $rc -eq 1 && "$out" == *"lists no omp-linux-"* ]] || fail "missing sums entry: $rc $out"

# An unexpected tag is refused before anything is downloaded.
make_release 19.5.0
printf 'v1;rm\n' > "$release/TAG"
rc=0; out="$(install_omp --force 2>&1)" || rc=$?
[[ $rc -eq 1 && "$out" == *"Unexpected Oh My Pi release tag"* ]] || fail "bad tag: $rc $out"

# --force replaces it with the release.
make_release 19.5.0
install_omp --force >/dev/null 2>&1 || fail "--force failed"
assert_eq "$("$bin" --version)" "omp 19.5.0" "--force"

# An omp from elsewhere on PATH is never shadowed.
rm -f "$bin"
printf '#!/bin/sh\necho "omp brew"\n' > "$TEST_ROOT/bin/omp"
chmod +x "$TEST_ROOT/bin/omp"
rc=0; out="$(install_omp 2>&1)" || rc=$?
[[ $rc -eq 2 && ! -e "$bin" && "$out" == *"externally-managed omp"* ]] || fail "shadowed an external omp: $rc $out"

printf 'install-omp: ok\n'
