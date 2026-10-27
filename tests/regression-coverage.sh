#!/bin/bash
# Behavior the setup redesign must keep, pinned before the engine moves:
# per-tool AI selection, external installs, unsupported platforms, custom XDG
# roots, moved and downgraded pins, and partial failure.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_REPO_ROOT="$ROOT"
source "$ROOT/tests/lib/harness.sh"
trap fixture_cleanup EXIT
fixture_init
export NO_COLOR=1

ledger_field() {
    local -a fields
    IFS=$'\t' read -r -a fields <<< "$(ledger_line "$1")"
    printf '%s' "${fields[$2]}"
}

run_setup() {
    HOME="$HOME" XDG_CONFIG_HOME="$XDG_CONFIG_HOME" XDG_DATA_HOME="$XDG_DATA_HOME" \
        XDG_STATE_HOME="$XDG_STATE_HOME" XDG_CACHE_HOME="$XDG_CACHE_HOME" TMPDIR="$TMPDIR" \
        DOTFILES_BACKUP_PREFIX="$DOTFILES_BACKUP_PREFIX" DOTFILES_TEST_PLATFORM="${PLATFORM:-ubuntu}" \
        DOTFILES_TEST_OS_VERSION="${OS_VERSION:-24.04}" DOTFILES_TEST_ARCH=x86_64 PATH="${RUN_PATH:-$PATH}" \
        "$ROOT/setup.sh" "$@" --no-hooks --no-theme
}

# --- Unsupported platforms: explicit requests fail before anything changes.
for request in "--azure:26.04" "--tail:20.04" "--gcloud:20.04"; do
    flag="${request%%:*}" OS_VERSION="${request#*:}"
    printf 'ID=ubuntu\nVERSION_ID="%s"\n' "$OS_VERSION" > "$TEST_ROOT/os-release"
    rc=0
    DOTFILES_OS_RELEASE="$TEST_ROOT/os-release" OS_VERSION="$OS_VERSION" run_setup "$flag" --dry-run >/dev/null 2>&1 || rc=$?
    [[ $rc -ne 0 ]] || fail "$flag on Ubuntu $OS_VERSION was accepted"
done
unset OS_VERSION
[[ ! -e "$XDG_STATE_HOME/dotfiles/components.tsv" ]] || fail "a refused request recorded components"

# --- Custom XDG roots outside HOME: links and state follow them.
custom="$TEST_ROOT/custom-xdg"
mkdir -p "$custom/config" "$custom/state" "$TEST_ROOT/tools"
printf '#!/bin/sh\necho "bat 0.25.0"\n' > "$TEST_ROOT/tools/bat"
chmod +x "$TEST_ROOT/tools/bat"
XDG_CONFIG_HOME="$custom/config" XDG_STATE_HOME="$custom/state" RUN_PATH="$TEST_ROOT/tools:$TEST_SYSTEM_PATH" \
    run_setup --config >/dev/null 2>&1 || fail "config tier with custom XDG roots failed"
[[ "$(readlink "$custom/config/bat")" == "$ROOT/configs/config/bat" ]] || fail "bat config not linked under custom XDG_CONFIG_HOME"
[[ -f "$custom/state/dotfiles/install-path" ]] || fail "state not written under custom XDG_STATE_HOME"
[[ ! -e "$HOME/.config/bat" && ! -e "$HOME/.local/state/dotfiles" ]] || fail "custom XDG roots leaked into HOME defaults"

source "$ROOT/setup.sh"

# --- Per-tool AI selection selects and installs exactly the named tools.
(
    parse_arguments --claude --opencode
    installed=""
    run_installer() { installed+=" $1"; }
    feature_enabled() { return 1; }
    install_selection >/dev/null
    assert_eq "$installed" " claude opencode" "per-tool AI selection"
    if component_selected codex || component_selected pi; then fail "a per-tool flag selected other AI CLIs"; fi
    SELECTED_CAPABILITIES=() SELECTED_AI_TOOLS=()
    parse_arguments --claude --ai
    installed=""
    install_selection >/dev/null
    assert_eq "$installed" " claude codex opencode pi" "--ai with a per-tool flag"
)

# --- External installs are recorded as such and never replaced.
mkdir -p "$HOME/.local/bin" "$TEST_ROOT/usr/bin"
printf '#!/bin/sh\necho "claude 9.9.9 (external)"\n' > "$TEST_ROOT/usr/bin/claude"
printf '#!/bin/sh\necho "fd 9.0.0"\n' > "$TEST_ROOT/usr/bin/fd"
printf '#!/bin/sh\necho "sd 0.1.0"\n' > "$HOME/.local/bin/sd"
chmod +x "$TEST_ROOT/usr/bin/claude" "$TEST_ROOT/usr/bin/fd" "$HOME/.local/bin/sd"
export PATH="$HOME/.local/bin:$TEST_ROOT/usr/bin:$TEST_SYSTEM_PATH"
track_install claude skip
assert_eq "$(ledger_field claude 2)/$(ledger_field claude 3)" "external/present" "external claude"
(
    # eget would fail the test if it were ever asked to download.
    printf '#!/bin/sh\n[ "$1" = --version ] && { echo "eget 1.3.4"; exit 0; }\ntouch "%s/downloaded"\nexit 1\n' \
        "$TEST_ROOT" > "$HOME/.local/bin/eget"
    chmod +x "$HOME/.local/bin/eget"
    run_installer() { :; }
    tier_includes() { return 0; }
    for name in "${!TOOL_METHOD[@]}"; do
        [[ "${TOOL_METHOD[$name]}" != eget || "$name" == fd || "$name" == sd ]] || unset "TOOL_METHOD[$name]"
    done
    install_eget_tools >/dev/null 2>&1 || true
    [[ ! -e "$TEST_ROOT/downloaded" ]] || fail "an external or unowned tool was downloaded over"
    assert_eq "$(ledger_field fd 2)/$(ledger_field fd 3)" "external/present" "system fd"
    assert_eq "$(ledger_field sd 2)/$(ledger_field sd 3)" "unknown/present" "unowned sd in ~/.local/bin"
)

# --- Moved and downgraded pins converge an owned eget tool; a failing tool
# does not stop the others.
repo="$TEST_ROOT/repo"
mkdir -p "$repo"
DOTFILES_DIR="$repo"
DOTFILES_VERSIONS_LOCK="$repo/versions.lock"
TOOL_METHOD=(['demo']=eget ['other']=eget)
TOOL_BINARY=(['demo']=demo ['other']=other)
TOOL_TIER=(['demo']=bash ['other']=bash)
TOOL_PLATFORM=(['demo']=ubuntu ['other']=ubuntu)
TOOL_ARCHES=(['demo']='x86_64,aarch64' ['other']='x86_64,aarch64')
TOOL_OWNERSHIP_ROOTS=(['demo']="$HOME/.local/bin" ['other']="$HOME/.local/bin")
TOOL_UPDATE_CONTRACT=(['demo']=staged-release ['other']=staged-release)
run_installer() { :; }
tier_includes() { return 0; }
# The fake eget writes a binary reporting the tag in the URL, and fails for
# any URL containing EGET_FAIL.
cat > "$HOME/.local/bin/eget" <<'FAKE_EGET'
#!/bin/bash
[[ "$1" == --version ]] && { echo "eget 1.3.4"; exit 0; }
while (( $# )); do
    case "$1" in --to) to="$2"; shift 2 ;; --file|--verify-sha256) shift 2 ;; *) url="$1"; shift ;; esac
done
[[ -z "${EGET_FAIL:-}" || "$url" != *"$EGET_FAIL"* ]] || exit 1
tag="${url%/*}"; tag="${tag##*/}"
printf '#!/bin/sh\necho "%s %s"\n' "${to##*/}" "${tag#v}" > "$to"
FAKE_EGET
chmod +x "$HOME/.local/bin/eget"
# pin DEMO_TAG OTHER_TAG: versions.lock rows whose identity is the binary the
# fake eget writes for that tag.
pin() {
    local name tag arch digest
    for name in demo:"$1" other:"$2"; do
        tag="${name#*:}" name="${name%%:*}"
        digest="$(printf '#!/bin/sh\necho "%s %s"\n' "$name" "${tag#v}" | sha256sum | awk '{print $1}')"
        for arch in x86_64 aarch64; do
            printf '%s\t%s\t%s\texample/%s\tasset.tar.gz\t%s\t-\tsha256:%s\n' \
                "$name" "$arch" "$tag" "$name" "$(printf '0%.0s' {1..64})" "$digest"
        done
    done > "$DOTFILES_VERSIONS_LOCK"
}
pin v2.0.0 v2.0.0
install_eget_tools >/dev/null 2>&1 || fail "initial eget install failed"
assert_eq "$("$HOME/.local/bin/demo")" "demo 2.0.0" "initial pin"
pin v3.0.0 v2.0.0
install_eget_tools >/dev/null 2>&1 || fail "moved pin install failed"
assert_eq "$("$HOME/.local/bin/demo")" "demo 3.0.0" "moved pin did not converge"
[[ "$(ledger_field demo 6)" == *"pin=v3.0.0 "* ]] || fail "moved pin not recorded"
pin v1.5.0 v2.0.0
install_eget_tools >/dev/null 2>&1 || fail "downgraded pin install failed"
assert_eq "$("$HOME/.local/bin/demo")" "demo 1.5.0" "downgraded pin did not converge"
pin v1.6.0 v2.1.0
INSTALL_OK=() INSTALL_FAIL=()
if EGET_FAIL=other install_eget_tools >/dev/null 2>&1; then fail "partial eget failure reported success"; fi
assert_eq "$("$HOME/.local/bin/demo")" "demo 1.6.0" "a failing tool stopped another's update"
assert_eq "$("$HOME/.local/bin/other")" "other 2.0.0" "a failed update replaced the working binary"
[[ " ${INSTALL_FAIL[*]} " == *" other "* && " ${INSTALL_OK[*]} " == *" demo "* ]] \
    || fail "partial failure not tracked per tool"
assert_eq "$(ledger_field other 3)" update-failed "failed update of a working tool"

printf 'regression-coverage: ok\n'
