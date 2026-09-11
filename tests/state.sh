#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_REPO_ROOT="$ROOT"
source "$ROOT/tests/lib/harness.sh"
trap fixture_cleanup EXIT
fixture_init
export DOTFILES_LEGACY_GENERATED_DIR="$TEST_ROOT/legacy-generated"
mkdir -p "$DOTFILES_LEGACY_GENERATED_DIR"
source "$ROOT/lib/runtime.sh"
source "$ROOT/lib/registry.sh"
source "$ROOT/lib/state.sh"

preference_set feature.theme disabled & first=$!
preference_set feature.agent-badge enabled & second=$!
wait "$first"; wait "$second"
assert_eq "$(preference_get feature.theme)" disabled "concurrent theme preference"
assert_eq "$(preference_get feature.agent-badge)" enabled "concurrent badge preference"
state_validate || fail "valid state rejected"
THEME_REQUEST=""; DOTFILES_THEME_ENABLED=""
feature_enabled theme && fail "disabled theme preference did not persist"
THEME_REQUEST=enabled
feature_enabled theme || fail "explicit theme enable did not override stored preference"
THEME_REQUEST=""

mkdir -p "$DOTFILES_STATE_LOCK"
printf '99999999\n' > "$DOTFILES_STATE_LOCK/pid"
preference_set feature.theme enabled
assert_eq "$(preference_get feature.theme)" enabled "stale lock recovery"

mkdir -p "$DOTFILES_STATE_LOCK"
printf '%s\n' "$$" > "$DOTFILES_STATE_LOCK/pid"
DOTFILES_STATE_LOCK_ATTEMPTS=2 preference_set feature.theme disabled >/dev/null 2>&1 \
    && fail "live state lock was stolen"
[[ -d "$DOTFILES_STATE_LOCK" ]] || fail "live state lock was removed"
rm -rf "$DOTFILES_STATE_LOCK"

ledger_record demo yes dotfiles installed 1.0 "$HOME/.local/bin/demo" ok
line="$(ledger_line demo)"
[[ "$line" == $'demo\tyes\tdotfiles\tinstalled\t1.0\t'* ]] || fail "ledger record malformed"

TOOL_BINARY[demo]=demo
TOOL_OWNERSHIP_ROOTS[demo]="$HOME/.local/bin"
journal_begin demo "$HOME/.local/bin/demo" "$TEST_ROOT/staged/demo" "$HOME/.local/bin/demo"
journal_pending || fail "journal was not recorded"
journal_clear
journal_pending && fail "journal was not cleared"

mkdir -p "$HOME/.local/bin"
cat > "$HOME/.local/bin/recovered" <<'EOF'
#!/bin/sh
[ "${1:-}" = --version ] && echo 'recovered 1'
EOF
chmod +x "$HOME/.local/bin/recovered"
TOOL_BINARY=(['recovered']=recovered)
TOOL_OWNERSHIP_ROOTS=(['recovered']="$HOME/.local/bin")
PATH="$HOME/.local/bin:$PATH"
journal_begin recovered "$HOME/.local/bin/recovered" "$TEST_ROOT/staged" "$HOME/.local/bin/recovered"
journal_reconcile
line="$(ledger_line recovered)"
[[ "$line" == $'recovered\tyes\tdotfiles\tinstalled\t'* ]] || fail "journal recovery did not reconcile ledger"
journal_pending && fail "recovered journal was not cleared"

printf 'schema\t999\ndefault\tbroken\n' > "$DOTFILES_THEME_STATE_FILE"
source "$ROOT/lib/theme-resolve.sh"
unset DOTFILES_THEME
load_global_theme_state
assert_eq "$DOTFILES_THEME" gruvbox "corrupt theme state did not fall back"

printf 'schema\t1\nfeature.theme\t$(touch %s)\n' "$TEST_ROOT/executed" > "$DOTFILES_PREFERENCES_FILE"
preference_get feature.theme >/dev/null
[[ ! -e "$TEST_ROOT/executed" ]] || fail "state data was evaluated as shell code"

printf 'state: ok\n'
