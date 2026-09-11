#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_REPO_ROOT="$ROOT"
source "$ROOT/tests/lib/harness.sh"
trap fixture_cleanup EXIT
fixture_init

source "$ROOT/setup.sh"

reset_args() {
    INSTALL_TIER=config INSTALL_AI=false AI_ALL=false INSTALL_RDP=false
    THEME_REQUEST="" AGENT_BADGE_REQUEST="" FORCE_OVERWRITE=false FORCE_REINSTALL=false
    SHOW_HELP=false DRY_RUN=false NO_HOOKS=false NO_GIT=false PARSE_ERROR=false
    AI_TOOLS=()
}

reset_args; parse_arguments --work --config --bash; assert_eq "$INSTALL_TIER" work "tier order downgraded"
reset_args; parse_arguments --config --full --bash; assert_eq "$INSTALL_TIER" work; assert_eq "$AI_ALL" true
reset_args; parse_arguments --bash --no-theme --no-agent-badge; assert_eq "$THEME_REQUEST" disabled; assert_eq "$AGENT_BADGE_REQUEST" disabled

reset_args
if parse_arguments --git-name --dev >/dev/null 2>&1; then fail "missing --git-name value accepted"; fi
[[ "$PARSE_ERROR" == true ]] || fail "missing value did not set parse error"

rc=0; "$ROOT/setup.sh" --definitely-unknown >/dev/null 2>&1 || rc=$?
assert_eq "$rc" 64 "unknown option exit"

printf 'ID=debian\nVERSION_ID="13"\n' > "$TEST_ROOT/os-release"
rc=0
DOTFILES_OS_RELEASE="$TEST_ROOT/os-release" "$ROOT/setup.sh" --dev --dry-run --no-hooks --no-git >/dev/null 2>&1 || rc=$?
[[ $rc -ne 0 ]] || fail "non-Ubuntu dev install was accepted"

DOTFILES_TEST_WSL_VERSION=1 WSL_DISTRO_NAME=Ubuntu INSTALL_TIER=bash INSTALL_RDP=false DRY_RUN=true \
    phase_verify_system >/dev/null 2>&1 && fail "WSL1 was accepted"

printf 'argument-parsing: ok\n'
