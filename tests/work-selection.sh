#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_REPO_ROOT="$ROOT"; source "$ROOT/tests/lib/harness.sh"; trap fixture_cleanup EXIT; fixture_init
source "$ROOT/setup.sh"

reset_selection() {
    INSTALL_TIER=config; SELECTED_CAPABILITIES=(); SELECTED_AI_TOOLS=()
    INSTALLATION_FAILED=false; INSTALL_OK=(); INSTALL_SKIP=(); INSTALL_FAIL=(); INSTALL_NA=()
}
calls=""
install_bash_packages() { calls+=" bash"; }
install_dev_packages() { calls+=" dev"; }
install_work_packages() { calls+=" work"; }
install_ai_selection() { calls+=" ai"; }
install_rdp_packages() { calls+=" rdp"; }
install_tail_packages() { calls+=" tail"; }
install_cloud_capability() { calls+=" cloud:$1"; }

reset_selection; INSTALL_TIER=work; SELECTED_CAPABILITIES=([ai]=all [tail]=yes [gcloud]=yes)
# setup.sh is sourced above; ShellCheck 0.9 otherwise binds these calls to the
# failure-injection override near the end of this test instead of the sourced
# production function.
# shellcheck disable=SC2218
phase_install_packages >/dev/null
assert_eq "$calls" " bash dev work ai tail cloud:gcloud" "composed work/tail/cloud install order"

calls=""; reset_selection; INSTALL_TIER=work
# shellcheck disable=SC2218
phase_install_packages >/dev/null
assert_eq "$calls" " bash dev work" "work unexpectedly selected Tailscale/cloud"

calls=""; reset_selection; SELECTED_CAPABILITIES=([tail]=yes)
# shellcheck disable=SC2218
phase_install_packages >/dev/null
assert_eq "$calls" " tail" "--tail did not retain config baseline independence"

output="$(DOTFILES_TEST_PLATFORM=ubuntu DOTFILES_TEST_ARCH=x86_64 DOTFILES_TEST_OS_VERSION=24.04 \
    HOME="$HOME" XDG_CONFIG_HOME="$XDG_CONFIG_HOME" XDG_STATE_HOME="$XDG_STATE_HOME" \
    XDG_CACHE_HOME="$XDG_CACHE_HOME" "$ROOT/setup.sh" --work --dry-run --no-hooks --no-git --no-theme 2>&1)"
[[ "$output" == *"installer: sbx"* && "$output" != *"installer: tailscale"* \
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
    [[ "$output" == *"Would ensure Docker apt repo"* && "$output" == *"installer: nvm"* \
       && "$output" != *"installer: sbx"* && "$output" != *"Would ensure the sbx kit builder"* \
       && "$output" == *"sbx is not applicable"* ]] || fail "--work on $platform did not skip only sbx: $output"
done
(
    # This test replaced install_work_packages above; load the real one.
    unset _DOTFILES_INSTALL_LOADED
    source "$ROOT/lib/install.sh"
    calls=""
    install_apt() { :; }
    install_docker_engine() { calls+=" docker"; }
    configure_docker_host_access() { calls+=" docker-access"; }
    configure_work_host() { calls+=" kvm"; }
    ensure_sbx_kits_builder() { calls+=" builder"; }
    run_installer() { calls+=" $1"; }
    tool_applicable() { [[ "$1" != sbx ]]; }
    INSTALL_NA=()
    DRY_RUN=false install_work_packages >/dev/null
    assert_eq "$calls" " docker docker-access nvm rust" "work tools where sbx does not apply"
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
        PATH="$TEST_ROOT/verify-bin:$TEST_SYSTEM_PATH" "$ROOT/bin/verify" --tier work 2>&1 || true)"
    [[ "$output" == *"Docker readiness"* ]] || fail "verify skipped Docker on $platform"
    if [[ "$platform" == wsl ]]; then
        [[ "$output" != *"Local sandbox readiness"* && "$output" != *"sbx package missing"* ]] \
            || fail "verify checked sbx where it does not apply"
    else
        [[ "$output" == *"Local sandbox readiness"* ]] || fail "verify skipped sbx where it applies"
    fi
done

reset_selection; SELECTED_CAPABILITIES=([tail]=yes); DRY_RUN=false
phase_verify_system() { return 0; }
apply_feature_requests() { return 0; }
phase_install_packages() { return 1; }
phase_setup_configs() { return 0; }
run_installation >/dev/null 2>&1 && fail "injected partial Tailscale install unexpectedly succeeded"

printf 'work-selection: ok\n'
