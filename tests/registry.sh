#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export DOTFILES_DIR="$ROOT"
source "$ROOT/lib/runtime.sh"
source "$ROOT/lib/registry.sh"

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

(( ${#REGISTRY_ERRORS[@]} == 0 )) || fail "registry tables: ${REGISTRY_ERRORS[*]}"

for name in "${!TOOL_BINARY[@]}"; do
    case "${TOOL_METHOD[$name]:-}" in
        eget|apt|installer|external) ;;
        *) fail "$name has unknown install method '${TOOL_METHOD[$name]:-}'" ;;
    esac
    case "${TOOL_TIER[$name]:-}" in
        ""|bash|dev|work) ;;
        *) fail "$name has unknown tier '${TOOL_TIER[$name]}'" ;;
    esac
    read -r verify_type verify_arg <<< "${TOOL_VERIFY[$name]:-}"
    case "$verify_type" in
        command|runs) ;;
        service-active|file-nonempty) [[ -n "$verify_arg" ]] || fail "$name: $verify_type needs an argument" ;;
        function) declare -F "$verify_arg" >/dev/null || fail "$name: verify function '$verify_arg' is undefined" ;;
        *) fail "$name has unknown verify type '$verify_type'" ;;
    esac
    [[ -z "${TOOL_TIMEOUT[$name]:-}" || "$verify_type" == runs ]] || fail "$name: timeout only applies to verify runs"
    [[ -n "${TOOL_TIER[$name]:-}" || -n "${TOOL_CAPABILITIES[$name]:-}" ]] || fail "$name has no tier/capability"
    [[ -n "${TOOL_PLATFORM[$name]:-}" ]] || fail "$name has no platform"
    [[ -n "${TOOL_ARCHES[$name]:-}" ]] || fail "$name has no architectures"
    [[ -n "${TOOL_UPDATE_CONTRACT[$name]:-}" ]] || fail "$name has no update contract"
    if [[ "${TOOL_METHOD[$name]}" == apt ]]; then
        [[ -n "${TOOL_APT_PACKAGE[$name]:-}" ]] || fail "$name has no TOOL_APT_PACKAGE"
    elif [[ "${TOOL_METHOD[$name]}" == installer ]]; then
        [[ -f "$ROOT/installers/install-$name.sh" ]] || fail "$name has no installer script"
    fi
done

for capability in ai rdp tail azure gcloud aws; do
    [[ -n "$(tools_for_capability "$capability")" ]] || fail "$capability capability is empty"
done
[[ "${TOOL_TIER[docker]}" == work ]] || fail "docker lost work-tier compatibility"
[[ "${TOOL_TIER[sbx]}" == work ]] || fail "sbx is not part of the work tier"
tool_has_capability tailscale tail || fail "tailscale missing tail capability"
[[ "${TOOL_APT_PACKAGE[sbx]}" == docker-sbx ]] || fail "sbx apt mapping is incorrect"
DOTFILES_TEST_ARCH=x86_64 DOTFILES_TEST_PLATFORM=ubuntu DOTFILES_TEST_OS_VERSION=24.04 tool_applicable sbx \
    || fail "sbx not applicable on Ubuntu 24.04"
DOTFILES_TEST_ARCH=aarch64 DOTFILES_TEST_PLATFORM=ubuntu DOTFILES_TEST_OS_VERSION=26.04 tool_applicable sbx \
    || fail "sbx not applicable on Ubuntu 26.04 arm64"
DOTFILES_TEST_ARCH=x86_64 DOTFILES_TEST_PLATFORM=wsl DOTFILES_TEST_OS_VERSION=24.04 tool_applicable sbx \
    && fail "sbx work component applicable on WSL"
DOTFILES_TEST_ARCH=x86_64 DOTFILES_TEST_PLATFORM=ubuntu DOTFILES_TEST_OS_VERSION=26.04 tool_applicable azure-cli \
    && fail "Azure CLI incorrectly marked supported on Ubuntu 26.04"

for arch in x86_64 aarch64; do
    DOTFILES_TEST_ARCH="$arch" DOTFILES_TEST_PLATFORM=ubuntu tool_applicable starship \
        || fail "starship not applicable on ubuntu/$arch"
    DOTFILES_TEST_ARCH="$arch" DOTFILES_TEST_PLATFORM=wsl tool_applicable wsl2-ssh-agent \
        || fail "wsl2-ssh-agent not applicable on wsl/$arch"
done
DOTFILES_TEST_ARCH=x86_64 DOTFILES_TEST_PLATFORM=ubuntu tool_applicable wsl2-ssh-agent \
    && fail "WSL-only component applicable on native Ubuntu"

# wsl2-ssh-agent assets carry no OS, so eget needs explicit per-arch filters
# that leave exactly one of: wsl2-ssh-agent, wsl2-ssh-agent-arm64.
assert_asset_args() {
    local arch="$1" expected="$2" actual
    actual="$(DOTFILES_TEST_ARCH="$arch" tool_eget_asset_args wsl2-ssh-agent | paste -sd' ')"
    [[ "$actual" == "$expected" ]] || fail "wsl2-ssh-agent $arch asset args: got '$actual', want '$expected'"
}
assert_asset_args x86_64 '--asset wsl2-ssh-agent --asset ^arm64'
assert_asset_args aarch64 '--asset wsl2-ssh-agent-arm64'
[[ -z "$(DOTFILES_TEST_ARCH=aarch64 tool_eget_asset_args starship)" ]] \
    || fail "tools selected natively must not get per-arch asset args"

if grep '^asset_filters' "$ROOT/eget.toml" | grep -Eq 'amd64|x86_64'; then
    fail "eget manifest contains architecture-specific filters; native selection would exclude ARM"
fi

# tool_is_present: each verify type against stub commands on a private PATH.
STUBS="$(mktemp -d)"
trap 'rm -rf "$STUBS"' EXIT
stub() { printf '#!/bin/sh\n%s\n' "$2" > "$STUBS/$1"; chmod +x "$STUBS/$1"; }
present() { PATH="$STUBS" HOME="$STUBS/home" tool_is_present "$1"; }
TOOL_BINARY[t-command]=tc; TOOL_VERIFY[t-command]="command extra"; TOOL_COMPANIONS[t-command]=tcx
TOOL_BINARY[t-runs]="tr"; TOOL_VERIFY[t-runs]="runs"; TOOL_VERSION_FLAG[t-runs]=-V
TOOL_BINARY[t-slow]="ts"; TOOL_VERIFY[t-slow]="runs"; TOOL_TIMEOUT[t-slow]=1
TOOL_BINARY[t-service]=tsv; TOOL_VERIFY[t-service]="service-active unit"
TOOL_BINARY[t-file]=tf; TOOL_VERIFY[t-file]="file-nonempty $STUBS/home/marker"
stub tc 'exit 0'; stub tcx 'exit 0'
present t-command && fail "command verify passed without its extra command"
stub extra 'exit 0'
present t-command || fail "command verify failed with binary, companion, and extra"
stub tr '[ "$1" = -V ]'
present t-runs || fail "runs verify ignored the version flag"
stub tr 'exit 1'
present t-runs && fail "runs verify passed a broken launcher"
ln -s "$(command -v timeout)" "$STUBS/timeout"; ln -s "$(command -v sleep)" "$STUBS/sleep"
stub ts 'sleep 5'
present t-slow && fail "runs verify ignored its timeout"
stub systemctl '[ "$*" = "is-active --quiet unit" ]'
present t-service || fail "service-active verify did not query the unit"
mkdir -p "$STUBS/home"; : > "$STUBS/home/marker"
present t-file && fail "file-nonempty verify passed an empty file"
echo x > "$STUBS/home/marker"
present t-file || fail "file-nonempty verify failed a nonempty file"
present no-such-tool && fail "unknown tool reported present"

printf 'registry: ok (ARM confidence: selection-only)\n'
