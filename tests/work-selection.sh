#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_REPO_ROOT="$ROOT"; source "$ROOT/tests/lib/harness.sh"; trap fixture_cleanup EXIT; fixture_init
source "$ROOT/setup.sh"

reset_selection() {
    INSTALL_TIER=config; INSTALL_AI=false; AI_ALL=false; AI_TOOLS=(); INSTALL_RDP=false
    INSTALL_TAIL=false; INSTALL_AZURE=false; INSTALL_GCLOUD=false; INSTALL_AWS=false
    INSTALLATION_FAILED=false; INSTALL_OK=(); INSTALL_SKIP=(); INSTALL_FAIL=(); INSTALL_NA=()
}
calls=""
install_bash_packages() { calls+=" bash"; }
install_dev_packages() { calls+=" dev"; }
install_work_packages() { calls+=" work"; }
install_ai_packages() { calls+=" ai"; }
install_rdp_packages() { calls+=" rdp"; }
install_tail_packages() { calls+=" tail"; }
install_cloud_capability() { calls+=" cloud:$1"; }

reset_selection; INSTALL_TIER=work; INSTALL_AI=true; INSTALL_TAIL=true; INSTALL_GCLOUD=true
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

calls=""; reset_selection; INSTALL_TAIL=true
# shellcheck disable=SC2218
phase_install_packages >/dev/null
assert_eq "$calls" " tail" "--tail did not retain config baseline independence"

output="$(DOTFILES_TEST_PLATFORM=ubuntu DOTFILES_TEST_ARCH=x86_64 DOTFILES_TEST_OS_VERSION=24.04 \
    HOME="$HOME" XDG_CONFIG_HOME="$XDG_CONFIG_HOME" XDG_STATE_HOME="$XDG_STATE_HOME" \
    XDG_CACHE_HOME="$XDG_CACHE_HOME" "$ROOT/setup.sh" --work --dry-run --no-hooks --no-git --no-theme 2>&1)"
[[ "$output" == *"installer: sbx"* && "$output" != *"installer: tailscale"* \
   && "$output" != *"Azure CLI: yes"* && "$output" != *"Google Cloud CLI: yes"* \
   && "$output" != *"AWS CLI v2: yes"* ]] || fail "work did not include sbx cleanly"

reset_selection; INSTALL_TAIL=true; DRY_RUN=false
phase_verify_system() { return 0; }
apply_feature_requests() { return 0; }
phase_install_packages() { return 1; }
phase_setup_configs() { return 0; }
run_installation >/dev/null 2>&1 && fail "injected partial Tailscale install unexpectedly succeeded"

printf 'work-selection: ok\n'
