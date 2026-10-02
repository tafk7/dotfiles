#!/bin/bash
# Characterization of setup.sh selection: for a matrix of flags, record the
# banner, selected components, install dispatch, system-requirement checks, and
# the success line with next steps, then compare with the committed snapshot.
# Refresh deliberately with: bash tests/setup-selection.sh --update
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_REPO_ROOT="$ROOT"
source "$ROOT/tests/lib/harness.sh"
trap fixture_cleanup EXIT
fixture_init
SNAPSHOT="$ROOT/tests/fixtures/setup-selection.snapshot"
export NO_COLOR=1

printf 'ID=ubuntu\nVERSION_ID="24.04"\n' > "$TEST_ROOT/ubuntu-24.04"
printf 'ID=ubuntu\nVERSION_ID="20.04"\n' > "$TEST_ROOT/ubuntu-20.04"
printf 'ID=debian\nVERSION_ID="13"\n' > "$TEST_ROOT/debian"

MATRIX=(
    "--config" "--bash" "--dev" "--work" "--full"
    "--ai" "--claude" "--claude --codex" "--claude --ai" "--ai --claude" "--claude --claude"
    "--pi --opencode"
    "--rdp" "--tail" "--azure" "--gcloud" "--aws" "--azure --aws"
    "--full --tail --gcloud" "--dev --rdp" "--work --claude --codex --tail"
    "--bash --pi --rdp --tail --azure --gcloud --aws"
)

# Host stubs shared by every section; each section runs in its own subshell
# after a fresh `source setup.sh`, so selection state never leaks between cases.
stub_host() {
    is_wsl() { return 1; }
    get_arch() { printf 'x86_64\n'; }
    tool_arch() { printf 'x86_64\n'; }
    detect_environment() { :; }
    hostname() { printf 'host\n'; }
    host_group_state() { printf 'ok\n'; }
    feature_enabled() { return 0; }
    MISSING=""; PROBES=""
    command() {
        if [[ "${1:-}" == -v ]]; then
            PROBES+=" $2"
            [[ " $MISSING " != *" $2 "* ]]
            return
        fi
        builtin command "$@"
    }
}

snapshot_case() {
    local -a flags
    read -r -a flags <<< "$1"
    printf '== %s\n' "$1"

    printf -- '-- banner\n'
    ( source "$ROOT/setup.sh"; stub_host; run_installation() { :; }; main "${flags[@]}" ) 2>&1

    printf -- '-- components\n'
    (
        source "$ROOT/setup.sh"; stub_host; parse_arguments "${flags[@]}"
        for name in $(printf '%s\n' "${!TOOL_BINARY[@]}" | LC_ALL=C sort); do
            component_selected "$name" && printf '%s ' "$name"
        done
        printf '\n'
    )

    printf -- '-- install\n'
    (
        source "$ROOT/setup.sh"; stub_host; parse_arguments "${flags[@]}"
        CALLS=""
        install_bash_packages() { CALLS+=" bash"; }
        install_dev_packages() { CALLS+=" dev"; }
        install_work_packages() { CALLS+=" work"; }
        install_rdp_packages() { CALLS+=" rdp"; }
        install_tail_packages() { CALLS+=" tail"; }
        install_cloud_capability() { CALLS+=" cloud:$1"; }
        install_eget_tools() { CALLS+=" eget:$*"; }
        run_installer() { CALLS+=" cli:$1"; }
        INSTALLATION_FAILED=false
        phase_install_packages >/dev/null 2>&1 || CALLS+=" (failed)"
        printf '%s\n' "${CALLS# }"
    )

    printf -- '-- verify\n'
    local os absent
    for os in ubuntu-24.04 ubuntu-20.04 debian; do
        for absent in "" curl git apt-get sudo systemctl; do
            (
                source "$ROOT/setup.sh"; stub_host; parse_arguments "${flags[@]}"
                MISSING="$absent"; APPLICABLE=""
                tool_applicable() { APPLICABLE+=" $1"; return 0; }
                rc=0
                # Not a command substitution: PROBES must survive the call.
                DOTFILES_OS_RELEASE="$TEST_ROOT/$os" phase_verify_system \
                    >/dev/null 2>"$TEST_ROOT/verify.err" || rc=$?
                message="$(grep -F '[ERROR]' "$TEST_ROOT/verify.err" | head -n1 || true)"
                printf '%s missing=%s rc=%s probes=[%s] applicable=[%s] %s\n' \
                    "$os" "${absent:-none}" "$rc" "${PROBES# }" "${APPLICABLE# }" "$message"
            )
        done
    done

    printf -- '-- success\n'
    (
        source "$ROOT/setup.sh"; stub_host; parse_arguments "${flags[@]}"
        journal_pending() { return 1; }
        phase_verify_system() { :; }
        apply_feature_requests() { :; }
        phase_install_packages() { :; }
        phase_setup_configs() { :; }
        print_install_summary() { :; }
        run_installation 2>&1
    )
}

generate() {
    printf '== --help\n'
    "$ROOT/setup.sh" --help
    local entry
    for entry in "${MATRIX[@]}"; do
        snapshot_case "$entry"
    done
}

actual="$TEST_ROOT/setup-selection.actual"
generate > "$actual"
if [[ "${1:-}" == --update ]]; then
    cp "$actual" "$SNAPSHOT"
    printf 'setup-selection: snapshot updated\n'
    exit 0
fi
diff -u "$SNAPSHOT" "$actual" >&2 || fail "setup selection behavior changed (see diff above)"
printf 'setup-selection: ok\n'
