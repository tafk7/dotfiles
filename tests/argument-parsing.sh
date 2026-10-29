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
    REINSTALL_COMPONENTS="" ONLY_COMPONENTS=""
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

# --force is both halves; each half alone; --reinstall and --only take names.
reset_args; parse_arguments --bash --reinstall; assert_eq "$FORCE_REINSTALL/$FORCE_OVERWRITE" true/false "--reinstall"
reset_args; parse_arguments --bash --overwrite-configs; assert_eq "$FORCE_REINSTALL/$FORCE_OVERWRITE" false/true "--overwrite-configs"
reset_args; parse_arguments --bash --force; assert_eq "$FORCE_REINSTALL/$FORCE_OVERWRITE" true/true "--force"
reset_args; parse_arguments --bash --reinstall=fd,bat; assert_eq "$REINSTALL_COMPONENTS/$FORCE_REINSTALL" "fd,bat/false" "--reinstall=LIST"
reset_args; parse_arguments --bash --only fd,sd; assert_eq "$ONLY_COMPONENTS" "fd,sd" "--only"
reset_args; if parse_arguments --bash --only bogus >/dev/null 2>&1; then fail "--only accepted an unknown component"; fi
reset_args; if parse_arguments --bash --reinstall=bogus >/dev/null 2>&1; then fail "--reinstall accepted an unknown component"; fi
reset_args; if parse_arguments --bash --only claude >/dev/null 2>&1; then fail "--only accepted an unselected component"; fi
reset_args; parse_arguments --claude --only claude || fail "--only refused a selected AI CLI"

reset_args
if parse_arguments --only --dev >/dev/null 2>&1; then fail "missing --only value accepted"; fi
[[ "$PARSE_ERROR" == true ]] || fail "missing value did not set parse error"

# Setup sets no Git identity: the retired flags, with or without a value, fail
# with a pointer to git profile, and their values are not taken for options.
reset_args
err="$(parse_arguments --git-name "CI Bot" --bash --git-email=ci@example.com --git-name 2>&1 >/dev/null)" \
    && fail "retired identity flags were accepted"
[[ "$err" == *"--git-name was removed; set a Git identity with: git profile add NAME --default"* \
   && "$err" == *"--git-email was removed"* && "$err" != *"Unknown option"* ]] \
    || fail "retired identity flags: $err"
rc=0; "$ROOT/setup.sh" --bash --git-email ci@example.com >/dev/null 2>&1 || rc=$?
assert_eq "$rc" 64 "retired --git-email option exit"

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
[[ $rc -eq 0 ]] || fail "Ubuntu 22.04 work tier was refused instead of skipping sbx"

# The front door's usage errors exit 64 before anything runs; the older names
# take what they always took (and ai-update now pi).
for args in "upgrade" "upgrade --bogus" "upgrade claude,bat" "verify --tier" "verify --tier=" "verify --tier=ai" "verify --nope"; do
    rc=0
    # shellcheck disable=SC2086
    "$ROOT/bin/dotfiles" $args >/dev/null 2>&1 || rc=$?
    assert_eq "$rc" 64 "dotfiles $args"
done
for args in "ai-update" "ai-update bat" "verify --tier" "verify --tier bogus" "verify --unknown"; do
    rc=0
    # shellcheck disable=SC2086
    "$ROOT/bin/"$args >/dev/null 2>&1 || rc=$?
    assert_eq "$rc" 64 "bin/$args"
done
for command in "dotfiles upgrade --help" "ai-update --help" "verify --help"; do
    # shellcheck disable=SC2086
    "$ROOT/bin/"$command >/dev/null || fail "bin/$command"
done
"$ROOT/bin/ai-update" --help | grep -Fq 'claude|codex|opencode|pi' || fail "ai-update does not name pi"

reset_args
DOTFILES_TEST_WSL_VERSION=1 WSL_DISTRO_NAME=Ubuntu INSTALL_TIER=bash DRY_RUN=true \
    phase_verify_system >/dev/null 2>&1 && fail "WSL1 was accepted"

printf 'argument-parsing: ok\n'
