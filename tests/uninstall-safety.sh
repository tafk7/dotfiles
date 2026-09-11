#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_REPO_ROOT="$ROOT"
source "$ROOT/tests/lib/harness.sh"
trap fixture_cleanup EXIT
fixture_init
source "$ROOT/bin/uninstall-tool"

TOOL_BINARY=(['demo']=demo)
TOOL_METHOD=(['demo']=installer)
TOOL_PATHS=(['demo']="$HOME/.local/demo")
TOOL_OWNERSHIP_ROOTS=(['demo']="$HOME/.local")
TOOL_REMOVAL_INSTRUCTIONS=()
mkdir -p "$HOME/.local/demo"
printf 'keep outside\n' > "$HOME/keep"
ledger_record demo yes dotfiles installed 1 "$HOME/.local/demo" test
ASSUME_YES=true
uninstall_tool demo >/dev/null
[[ ! -e "$HOME/.local/demo" ]] || fail "owned path not removed"
[[ -f "$HOME/keep" ]] || fail "uninstall removed unrelated data"

TOOL_PATHS[demo]="$HOME"
ledger_record demo yes dotfiles installed 1 "$HOME" malicious
if uninstall_tool demo >/dev/null 2>&1; then fail "broad HOME target accepted"; fi
[[ -f "$HOME/keep" ]] || fail "malformed registry deleted HOME data"

TOOL_PATHS[demo]="$TEST_ROOT/outside"
mkdir -p "$TEST_ROOT/outside"
ledger_record demo yes dotfiles installed 1 "$TEST_ROOT/outside" malicious
if uninstall_tool demo >/dev/null 2>&1; then fail "outside ownership root accepted"; fi
[[ -d "$TEST_ROOT/outside" ]] || fail "outside path was deleted"

printf 'uninstall-safety: ok\n'
