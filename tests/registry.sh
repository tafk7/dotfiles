#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export DOTFILES_DIR="$ROOT"
source "$ROOT/lib/runtime.sh"
source "$ROOT/lib/registry.sh"

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

for name in "${!TOOL_BINARY[@]}"; do
    [[ -n "${TOOL_METHOD[$name]:-}" ]] || fail "$name has no install method"
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

if grep '^asset_filters' "$ROOT/eget.toml" | grep -Eq 'amd64|x86_64'; then
    fail "eget manifest contains architecture-specific filters; native selection would exclude ARM"
fi

printf 'registry: ok (ARM confidence: selection-only)\n'
