#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_REPO_ROOT="$ROOT"
source "$ROOT/tests/lib/harness.sh"
trap fixture_cleanup EXIT
fixture_init

source "$ROOT/setup.sh"

reset_args() {
    INSTALL_TIER=config SELECTED_CAPABILITIES=() SELECTED_AI_TOOLS=()
    THEME_REQUEST="" AGENT_BADGE_REQUEST="" FORCE_OVERWRITE=false FORCE_REINSTALL=false
    SHOW_HELP=false DRY_RUN=false NO_HOOKS=false NO_GIT=false PARSE_ERROR=false
}
# Selected capabilities as "name=value" in table order.
selection() {
    local name out=""
    for name in "${CAPABILITY_NAMES[@]}"; do
        if capability_selected "$name"; then out+=" $name=${SELECTED_CAPABILITIES[$name]}"; fi
    done
    printf '%s\n' "${out# }"
}

reset_args; parse_arguments --work --config --bash; assert_eq "$INSTALL_TIER" work "tier order downgraded"
reset_args; parse_arguments --config --full --bash; assert_eq "$INSTALL_TIER" work; assert_eq "$(selection)" "ai=all"
reset_args; parse_arguments --bash --no-theme --no-agent-badge; assert_eq "$THEME_REQUEST" disabled; assert_eq "$AGENT_BADGE_REQUEST" disabled
reset_args; parse_arguments --full --tail --gcloud; assert_eq "$INSTALL_TIER" work; assert_eq "$(selection)" "ai=all tail=yes gcloud=yes"
reset_args; parse_arguments --tail; assert_eq "$INSTALL_TIER" config; assert_eq "$(selection)" "tail=yes"
reset_args; parse_arguments --azure --aws; assert_eq "$INSTALL_TIER" config; assert_eq "$(selection)" "azure=yes aws=yes"
reset_args; parse_arguments --claude --pi; assert_eq "$(selection)" "ai=some"; assert_eq "${SELECTED_AI_TOOLS[*]}" "claude pi"
reset_args; parse_arguments --codex --ai --claude; assert_eq "$(selection)" "ai=all" "--ai lost to a later per-tool flag"

reset_args
if parse_arguments --git-name --dev >/dev/null 2>&1; then fail "missing --git-name value accepted"; fi
[[ "$PARSE_ERROR" == true ]] || fail "missing value did not set parse error"

rc=0; "$ROOT/setup.sh" --definitely-unknown >/dev/null 2>&1 || rc=$?
assert_eq "$rc" 64 "unknown option exit"
rc=0; "$ROOT/setup.sh" --worker >/dev/null 2>&1 || rc=$?
assert_eq "$rc" 64 "retired --worker option was accepted"

printf 'ID=debian\nVERSION_ID="13"\n' > "$TEST_ROOT/os-release"
rc=0
DOTFILES_OS_RELEASE="$TEST_ROOT/os-release" "$ROOT/setup.sh" --dev --dry-run --no-hooks --no-git >/dev/null 2>&1 || rc=$?
[[ $rc -ne 0 ]] || fail "non-Ubuntu dev install was accepted"

printf 'ID=ubuntu\nVERSION_ID="22.04"\nVERSION_CODENAME=jammy\n' > "$TEST_ROOT/os-release"
rc=0
DOTFILES_OS_RELEASE="$TEST_ROOT/os-release" DOTFILES_TEST_PLATFORM=ubuntu DOTFILES_TEST_ARCH=x86_64 \
    "$ROOT/setup.sh" --work --dry-run --no-hooks --no-git >/dev/null 2>&1 || rc=$?
[[ $rc -ne 0 ]] || fail "Ubuntu 22.04 work tier was accepted despite sbx requiring 24.04+"

reset_args
DOTFILES_TEST_WSL_VERSION=1 WSL_DISTRO_NAME=Ubuntu INSTALL_TIER=bash DRY_RUN=true \
    phase_verify_system >/dev/null 2>&1 && fail "WSL1 was accepted"

printf 'argument-parsing: ok\n'
