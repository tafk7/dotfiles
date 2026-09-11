#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export DOTFILES_DIR="$ROOT"
source "$ROOT/lib/runtime.sh"
source "$ROOT/lib/registry.sh"

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

for name in "${!TOOL_BINARY[@]}"; do
    [[ -n "${TOOL_METHOD[$name]:-}" ]] || fail "$name has no install method"
    [[ -n "${TOOL_TIER[$name]:-}" ]] || fail "$name has no tier/feature"
    [[ -n "${TOOL_PLATFORM[$name]:-}" ]] || fail "$name has no platform"
    [[ -n "${TOOL_ARCHES[$name]:-}" ]] || fail "$name has no architectures"
    [[ -n "${TOOL_UPDATE_CONTRACT[$name]:-}" ]] || fail "$name has no update contract"
done

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
