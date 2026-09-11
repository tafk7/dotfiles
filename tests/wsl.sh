#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_REPO_ROOT="$ROOT"
source "$ROOT/tests/lib/harness.sh"
trap fixture_cleanup EXIT
fixture_init
export WSL_DISTRO_NAME=Ubuntu DOTFILES_TEST_WSL_VERSION=2

source "$ROOT/lib/runtime.sh"
is_wsl || fail "mocked WSL was not detected"
assert_eq "$(wsl_version)" 2
before="$(fixture_managed_snapshot)"
source "$ROOT/shell/platform/wsl.sh"
after="$(fixture_managed_snapshot)"
assert_eq "$after" "$before" "disabled WSL SSH bridge mutated state"

printf 'wsl: ok (mocked WSL2 shell fallback)\n'
