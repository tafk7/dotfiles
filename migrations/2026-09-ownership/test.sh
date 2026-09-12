#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$ROOT/migrations/2026-09-ownership/adopt.sh"
source "$ROOT/tests/lib/harness.sh"
fixture_init
trap fixture_cleanup EXIT
source "$ROOT/lib/registry.sh"
source "$ROOT/lib/state.sh"
export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$TEST_ROOT/bin:$TEST_SYSTEM_PATH"
mkdir -p "$HOME/.local/bin" "$HOME/.nvm" "$HOME/.cargo/bin" "$HOME/.codex/packages/standalone/releases/new/bin"

# Never execute an existing installation during preview or apply.
cat > "$HOME/.local/bin/eza" <<EOF
#!/bin/bash
touch "$TEST_ROOT/cli-executed"
exit 99
EOF
chmod +x "$HOME/.local/bin/eza"
cp "$HOME/.local/bin/eza" "$HOME/.local/bin/uv"
cp "$HOME/.local/bin/eza" "$HOME/.cargo/bin/rustup"
ln -s rustup "$HOME/.cargo/bin/rustc"
ln -s rustup "$HOME/.cargo/bin/cargo"
printf 'touch "%s"\n' "$TEST_ROOT/nvm-sourced" > "$HOME/.nvm/nvm.sh"
cp "$HOME/.local/bin/eza" "$HOME/.codex/packages/standalone/releases/new/bin/codex"
ln -s "$HOME/.codex/packages/standalone/releases/new/bin/codex" "$HOME/.local/bin/codex"
for name in eza uv codex nvm rust; do
    path="$HOME/.local/bin/$name"
    [[ "$name" != nvm ]] || path=-
    [[ "$name" != codex ]] || path="$HOME/.codex/packages/standalone/releases/old/bin/codex"
    ledger_record "$name" yes unknown present 'old-version' "$path" 'observed during reconciliation; ownership unclaimed'
done
ledger_record docker yes package-manager installed 1 /usr/bin/docker apt
ledger_record bat yes external present 1 /usr/bin/bat external
before="$(fixture_managed_snapshot)"
preview="$(bash "$SCRIPT")"
[[ "$preview" == *'missing uvx'* && "$preview" == *'Preview only'* ]] || fail 'preview omitted companion or mode'
assert_eq "$(fixture_managed_snapshot)" "$before" 'preview wrote managed state'
if bash "$SCRIPT" --apply </dev/null >/dev/null 2>&1; then fail 'unconfirmed adoption accepted'; fi
assert_eq "$(fixture_managed_snapshot)" "$before" 'cancelled adoption wrote state'

# One invalid selected candidate blocks the entire batch, with no partial adoption.
ledger_record delta yes unknown present 1 "$TEST_ROOT/outside" observed
cp "$HOME/.local/bin/eza" "$TEST_ROOT/outside"
ln -s "$TEST_ROOT/outside" "$HOME/.local/bin/delta"
ledger_before="$(sha256sum "$DOTFILES_LEDGER_FILE")"
if bash "$SCRIPT" --apply --yes eza delta >/dev/null 2>&1; then fail 'symlink escape accepted'; fi
assert_eq "$(sha256sum "$DOTFILES_LEDGER_FILE")" "$ledger_before" 'blocked batch partially adopted'

# Explicit selection changes only eligible records and preserves the old ledger.
cp "$DOTFILES_LEDGER_FILE" "$TEST_ROOT/original.tsv"
bash "$SCRIPT" --apply --yes eza uv codex nvm rust bat docker >/dev/null
for name in eza uv codex nvm rust; do
    [[ "$(ledger_line "$name")" == "$name"$'\tyes\tdotfiles\tinstalled\t'* ]] || fail "$name not adopted"
done
[[ "$(ledger_line nvm)" == *"$HOME/.nvm"* ]] || fail 'NVM directory not recorded'
[[ "$(ledger_line rust)" == *"$HOME/.cargo/bin/rustup"* ]] || fail 'Rust proxy not resolved'
[[ "$(ledger_line codex)" == $'codex\tyes\tdotfiles\tinstalled\t-\t'* ]] || fail 'stale release version retained'
for name in bat docker delta; do
    assert_eq "$(ledger_line "$name")" "$(awk -F '\t' -v name="$name" '$1 == name' "$TEST_ROOT/original.tsv")" "$name modified"
done
shopt -s nullglob
backups=("$DOTFILES_STATE_DIR"/components.before-ownership-2026-09.tsv.*)
assert_eq "${#backups[@]}" 1 'backup count'
cmp -s "${backups[0]}" "$TEST_ROOT/original.tsv" || fail 'backup not exact'
assert_eq "$(stat -c %a "${backups[0]}")" 600 'backup permissions'
after="$(fixture_managed_snapshot)"
bash "$SCRIPT" --apply --yes eza uv codex nvm rust >/dev/null
assert_eq "$(fixture_managed_snapshot)" "$after" 'rerun was not a no-op'
[[ ! -e "$TEST_ROOT/cli-executed" && ! -e "$TEST_ROOT/nvm-sourced" ]] || fail 'migration executed installed code'

# Simulate another writer during human review. Never overwrite that writer.
ledger_record eza yes unknown present 1 "$HOME/.local/bin/eza" observed
(
    source "$SCRIPT"
    confirm_adoption() { ledger_record bat yes external present 2 /usr/bin/bat concurrent; }
    if main --apply eza >/dev/null 2>&1; then fail 'ledger changed after review but adoption continued'; fi
)
[[ "$(ledger_line eza)" == $'eza\tyes\tunknown\t'* ]] || fail 'stale plan applied'
[[ "$(ledger_line bat)" == *concurrent* ]] || fail 'concurrent writer lost'

# A binary changing during review also invalidates the approved plan.
(
    source "$SCRIPT"
    confirm_adoption() { printf '\n# updated\n' >> "$HOME/.local/bin/eza"; }
    if main --apply eza >/dev/null 2>&1; then fail 'artifact changed after review but adoption continued'; fi
)
[[ "$(ledger_line eza)" == $'eza\tyes\tunknown\t'* ]] || fail 'changed artifact adopted'

# A failed atomic commit must leave the original ledger intact.
ledger_before="$(sha256sum "$DOTFILES_LEDGER_FILE")"
(
    source "$SCRIPT"
    mv() { return 73; }
    if main --apply --yes eza >/dev/null 2>&1; then fail 'failed ledger replacement reported success'; fi
)
assert_eq "$(sha256sum "$DOTFILES_LEDGER_FILE")" "$ledger_before" 'failed commit damaged ledger'

# Match the registry's durable-ripgrep rule when an agent adds its private rg.
mkdir -p "$TEST_ROOT/.codex/private"
cp "$HOME/.local/bin/eza" "$TEST_ROOT/.codex/private/rg"
cp "$HOME/.local/bin/eza" "$HOME/.local/bin/rg"
ledger_record ripgrep yes unknown present 1 "$HOME/.local/bin/rg" observed
PATH="$TEST_ROOT/.codex/private:$PATH" bash "$SCRIPT" --apply --yes ripgrep >/dev/null
[[ "$(ledger_line ripgrep)" == $'ripgrep\tyes\tdotfiles\tinstalled\t'* ]] || fail 'private rg prevented durable-ripgrep adoption'
printf 'one-time ownership migration: ok\n'
