#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_REPO_ROOT="$ROOT"; source "$ROOT/tests/lib/harness.sh"; trap fixture_cleanup EXIT; fixture_init
source "$ROOT/setup.sh"

reset_selection() {
    INSTALL_TIER=config; SELECTED_CAPABILITIES=(); SELECTED_AI_TOOLS=()
    INSTALLATION_FAILED=false; INSTALL_OK=(); INSTALL_SKIP=(); INSTALL_FAIL=(); INSTALL_NA=()
}
# Record each install step by its component, package set, or configure step.
calls=""
install_eget_tools() { calls+=" eget"; }
install_package_set() { calls+=" packages:$1"; }
install_docker_engine() { calls+=" docker"; }
install_rdp_packages() { calls+=" rdp"; }
configure_docker_host_access() { calls+=" docker-access"; }
configure_work_host() { calls+=" kvm"; }
ensure_sbx_kits_builder() { calls+=" builder"; }
use_default_node() { :; }
run_installer() { calls+=" $1"; }
feature_enabled() { return 1; }

reset_selection; INSTALL_TIER=work; SELECTED_CAPABILITIES=([ai]=all [tail]=yes [gcloud]=yes)
# setup.sh is sourced above; ShellCheck 0.9 otherwise binds these calls to the
# failure-injection override near the end of this test instead of the sourced
# production function.
# shellcheck disable=SC2218
DOTFILES_TEST_PLATFORM=ubuntu DOTFILES_TEST_OS_VERSION=24.04 phase_install_packages >/dev/null
assert_eq "$calls" " eget packages:dev tmux neovim packages:work docker docker-access sbx kvm builder nvm node rust claude codex opencode pi tailscale gcloud" \
    "composed work/tail/cloud install order"

calls=""; reset_selection; INSTALL_TIER=work
# shellcheck disable=SC2218
DOTFILES_TEST_PLATFORM=ubuntu DOTFILES_TEST_OS_VERSION=24.04 phase_install_packages >/dev/null
[[ "$calls" != *tailscale* && "$calls" != *gcloud* && "$calls" != *claude* ]] || fail "work unexpectedly selected Tailscale/cloud/AI: $calls"

calls=""; reset_selection; SELECTED_CAPABILITIES=([tail]=yes)
# shellcheck disable=SC2218
phase_install_packages >/dev/null
assert_eq "$calls" " tailscale" "--tail did not retain config baseline independence"

# A component whose need failed in this run is not attempted.
calls=""; reset_selection; INSTALL_TIER=work
run_installer() { calls+=" $1"; [[ "$1" != nvm ]]; }
# shellcheck disable=SC2218
if DOTFILES_TEST_PLATFORM=ubuntu DOTFILES_TEST_OS_VERSION=24.04 phase_install_packages >/dev/null 2>&1; then
    fail "a failed nvm install reported success"
fi
[[ "$calls" == *" nvm rust"* && " ${INSTALL_FAIL[*]} " == *" node "* ]] || fail "node was attempted after nvm failed: $calls"
run_installer() { calls+=" $1"; }

output="$(DOTFILES_TEST_PLATFORM=ubuntu DOTFILES_TEST_ARCH=x86_64 DOTFILES_TEST_OS_VERSION=24.04 \
    HOME="$HOME" XDG_CONFIG_HOME="$XDG_CONFIG_HOME" XDG_STATE_HOME="$XDG_STATE_HOME" \
    XDG_CACHE_HOME="$XDG_CACHE_HOME" "$ROOT/setup.sh" --work --dry-run --no-hooks --no-git --no-theme 2>&1)"
# The plan comes from this host's observations, so it names only what differs;
# Tailscale and the cloud CLIs are never part of it.
[[ "$output" != *"Skipping sbx"* && "$output" != *tailscale* \
   && "$output" != *"Azure CLI: yes"* && "$output" != *"Google Cloud CLI: yes"* \
   && "$output" != *"AWS CLI v2: yes"* ]] || fail "work did not include sbx cleanly"

# Where sbx does not apply (WSL, 22.04), --work installs the other work tools
# and skips sbx, KVM access, and the kit builder.
for platform in wsl:24.04 ubuntu:22.04; do
    rc=0
    output="$(DOTFILES_TEST_PLATFORM="${platform%%:*}" DOTFILES_TEST_ARCH=x86_64 DOTFILES_TEST_OS_VERSION="${platform#*:}" \
        HOME="$HOME" XDG_CONFIG_HOME="$XDG_CONFIG_HOME" XDG_STATE_HOME="$XDG_STATE_HOME" \
        XDG_CACHE_HOME="$XDG_CACHE_HOME" "$ROOT/setup.sh" --work --dry-run --no-hooks --no-git --no-theme 2>&1)" || rc=$?
    [[ $rc -eq 0 ]] || fail "--work on $platform was refused: $output"
    [[ "$output" == *"Would install nvm"* && "$output" != *"Would install sbx"* \
       && "$output" != *"Would ensure the sbx kit builder"* \
       && "$output" == *"Skipping sbx: it is not applicable"* ]] || fail "--work on $platform did not skip only sbx: $output"
done
(
    calls=""; reset_selection; INSTALL_TIER=work
    tool_applicable() { [[ "$1" != sbx ]]; }
    # shellcheck disable=SC2218
    DRY_RUN=false phase_install_packages >/dev/null
    assert_eq "$calls" " eget packages:dev tmux neovim packages:work docker docker-access nvm node rust" "work tools where sbx does not apply"
    [[ " ${INSTALL_NA[*]} " == *" sbx "* ]] || fail "sbx not recorded as not applicable"
)

# Verify checks Docker wherever it is selected, and sbx/KVM only where sbx applies.
mkdir -p "$TEST_ROOT/verify-bin"
printf '#!/bin/sh
exit 1
' > "$TEST_ROOT/verify-bin/docker"
chmod +x "$TEST_ROOT/verify-bin/docker"
for platform in wsl ubuntu; do
    output="$(DOTFILES_TEST_PLATFORM="$platform" DOTFILES_TEST_ARCH=x86_64 DOTFILES_TEST_OS_VERSION=24.04 \
        PATH="$TEST_ROOT/verify-bin:$TEST_SYSTEM_PATH" "$ROOT/bin/dotfiles" verify -v --tier work 2>&1 || true)"
    [[ "$output" == *$'\nDocker\n'* ]] || fail "verify skipped Docker on $platform: $output"
    if [[ "$platform" == wsl ]]; then
        [[ "$output" != *"Local sandboxes"* && "$output" != *"sbx package missing"* ]] \
            || fail "verify checked sbx where it does not apply: $output"
    else
        [[ "$output" == *$'\nLocal sandboxes\n'* ]] || fail "verify skipped sbx where it applies: $output"
    fi
done

# --diagnose adds sbx's bounded local diagnostics to the sandbox checks.
printf '#!/bin/sh\necho "sbx $*" >> "%s/sbx.log"\n' "$TEST_ROOT" > "$TEST_ROOT/verify-bin/sbx"
chmod +x "$TEST_ROOT/verify-bin/sbx"
for diagnose in "" --diagnose; do
    : > "$TEST_ROOT/sbx.log"
    output="$(DOTFILES_TEST_PLATFORM=ubuntu DOTFILES_TEST_ARCH=x86_64 DOTFILES_TEST_OS_VERSION=24.04 \
        PATH="$TEST_ROOT/verify-bin:$TEST_SYSTEM_PATH" "$ROOT/bin/dotfiles" verify -v --tier work $diagnose 2>&1 || true)"
    if [[ -n "$diagnose" ]]; then
        grep -Fxq 'sbx diagnose' "$TEST_ROOT/sbx.log" || fail "--diagnose did not run sbx diagnose: $(<"$TEST_ROOT/sbx.log")"
        [[ "$output" == *"ok   bounded local sbx diagnostics"* ]] || fail "--diagnose: $output"
    else
        grep -Fxq 'sbx diagnose' "$TEST_ROOT/sbx.log" && fail "sbx diagnose ran without --diagnose"
    fi
done

reset_selection; SELECTED_CAPABILITIES=([tail]=yes); DRY_RUN=false
phase_verify_system() { return 0; }
apply_feature_requests() { return 0; }
phase_install_packages() { return 1; }
phase_setup_configs() { return 0; }
run_installation >/dev/null 2>&1 && fail "injected partial Tailscale install unexpectedly succeeded"

printf 'work-selection: ok\n'
