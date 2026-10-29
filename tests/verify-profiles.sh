#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_REPO_ROOT="$ROOT"
source "$ROOT/tests/lib/harness.sh"
trap fixture_cleanup EXIT
fixture_init
source "$ROOT/lib/runtime.sh"
source "$ROOT/lib/registry.sh"
source "$ROOT/lib/state.sh"

HOME="$HOME" XDG_CONFIG_HOME="$XDG_CONFIG_HOME" XDG_DATA_HOME="$XDG_DATA_HOME" \
    XDG_STATE_HOME="$XDG_STATE_HOME" XDG_CACHE_HOME="$XDG_CACHE_HOME" \
    "$ROOT/setup.sh" --config --no-theme --no-hooks >/dev/null

unset DOTFILES_OPERATION
export NO_COLOR=1

# bin/verify is the older name for `dotfiles verify -v`, with its options
# mapped; these run through it, so the mapping is covered too.
"$ROOT/bin/verify" --tier config > "$TEST_ROOT/config-verify.log" \
    || { cat "$TEST_ROOT/config-verify.log" >&2; fail "config-only verification failed"; }
# Setup sets no identity; its absence is a note, pointing at git profile.
grep -Fq 'note user: not configured; commits are refused (run: git profile add NAME --default)' \
    "$TEST_ROOT/config-verify.log" || fail "a missing Git identity was not reported"

# A cumulative tier includes the subset applicable to the current platform.
# Native Ubuntu must not fail because the bash tier also registers a WSL-only
# SSH bridge.
DOTFILES_TEST_PLATFORM=ubuntu DOTFILES_TEST_OS_VERSION=24.04 DOTFILES_TEST_ARCH=x86_64 \
    "$ROOT/bin/verify" --tier bash > "$TEST_ROOT/native-bash.log" 2>&1 || true
grep -Fq '  ok   wsl2-ssh-agent: not applicable here' "$TEST_ROOT/native-bash.log" \
    || { cat "$TEST_ROOT/native-bash.log" >&2; fail "native bash verification required the WSL-only SSH bridge"; }

# Delta settings are nested through the portable Git config, not written
# directly into ~/.gitconfig, and identity through ~/.gitconfig.local.
# Verification must follow include chains.
git config --file "$HOME/.gitconfig.local" user.name Fixture
git config --file "$HOME/.gitconfig.local" user.email fixture@example.com
"$ROOT/setup.sh" --config --theme --no-hooks >/dev/null
"$ROOT/bin/verify" --tier config > "$TEST_ROOT/theme-verify.log" \
    || { cat "$TEST_ROOT/theme-verify.log" >&2; fail "theme-enabled config verification failed"; }
grep -Fq 'ok   delta: palette-based colors' "$TEST_ROOT/theme-verify.log" \
    || fail "nested Delta settings were not verified"
grep -Fq 'ok   user: Fixture <fixture@example.com>' "$TEST_ROOT/theme-verify.log" \
    || fail "identity in the local Git include was not verified"
grep -Fq 'ok   theme: ' "$TEST_ROOT/theme-verify.log" || fail "the global theme was not reported"

# The agent shell: functions from other profiles are left alone; a dotfiles
# interactive function, an alias, or BASH_ENV is a note.
external_fixture_function() { :; }
export -f external_fixture_function
"$ROOT/bin/verify" > "$TEST_ROOT/external-functions.log"
grep -Fq 'ok   functions: no dotfiles interactive or private functions' "$TEST_ROOT/external-functions.log" \
    || fail "external function was mistaken for a dotfiles startup leak"
reload() { :; }
export -f reload
"$ROOT/bin/verify" > "$TEST_ROOT/leaked-functions.log"
grep -Fq 'note functions: 1 dotfiles interactive or private function(s): reload' "$TEST_ROOT/leaked-functions.log" \
    || fail "interactive function leak was not diagnosed"
unset -f reload external_fixture_function
printf ': agent shell fixture\n' > "$TEST_ROOT/bash-env"
BASH_ENV="$TEST_ROOT/bash-env" "$ROOT/bin/verify" > "$TEST_ROOT/bash-env.log"
grep -Fq "note BASH_ENV: set to $TEST_ROOT/bash-env" "$TEST_ROOT/bash-env.log" \
    || fail "BASH_ENV was not diagnosed"

# A minimal profile may define no functions; compgen then returns 1.
cat > "$TEST_ROOT/bin/bash" <<'EOF'
#!/bin/bash
if [[ "$1" == -lc ]]; then
    shift
    exec /bin/bash --noprofile --norc -c "$@"
fi
exec /bin/bash "$@"
EOF
chmod +x "$TEST_ROOT/bin/bash"
PATH="$TEST_ROOT/bin:$PATH" "$ROOT/bin/verify" --tier config > "$TEST_ROOT/no-functions.log" \
    || fail "empty function inventory aborted verification"
grep -Fq 'ok   functions: no dotfiles interactive or private functions' "$TEST_ROOT/no-functions.log" \
    || fail "empty function inventory was not verified"
rm "$TEST_ROOT/bin/bash"

# Without a profile, the ledger's components are what is expected (the old
# --installed). The rest of this block works from the ledger.
mv "$XDG_STATE_HOME/dotfiles/profile" "$TEST_ROOT/profile"

# Adoption must not expose a false ownership failure for agent-private rg:
# the owned copy is the one observed, at its pin or not.
mkdir -p "$HOME/.local/bin" "$TEST_ROOT/.codex/private"
fake_command "$HOME/.local/bin/rg" true
fake_command "$TEST_ROOT/.codex/private/rg" true
ledger_record ripgrep yes dotfiles installed 1 "$HOME/.local/bin/rg" test
PATH="$TEST_ROOT/.codex/private:$HOME/.local/bin:$PATH" "$ROOT/bin/verify" --installed \
    > "$TEST_ROOT/private-rg.log" 2>&1 || true
grep -Eq '(ok   ripgrep|fix  ripgrep: off its pin)' "$TEST_ROOT/private-rg.log" \
    || { cat "$TEST_ROOT/private-rg.log" >&2; fail "private rg shadowed the verified owned installation"; }
grep -Fq 'ripgrep: satisfied by an external install' "$TEST_ROOT/private-rg.log" \
    && fail "private rg was used for ownership verification"

# Distinguish a missing companion from a missing primary executable.
fake_command "$HOME/.local/bin/uv" true
ledger_record uv yes dotfiles installed 1 "$HOME/.local/bin/uv" test
rc=0
PATH="$HOME/.local/bin:$TEST_SYSTEM_PATH" "$ROOT/bin/verify" --installed \
    > "$TEST_ROOT/missing-uvx.log" 2>&1 || rc=$?
assert_eq "$rc" 1 "a missing companion"
grep -Fq 'fix  uv: companions uvx missing' "$TEST_ROOT/missing-uvx.log" \
    || { cat "$TEST_ROOT/missing-uvx.log" >&2; fail "missing companion was reported as a missing primary"; }

# A self-updating CLI that moved within its ownership roots is still owned; a
# component without that contract found away from its recorded path is not
# the install dotfiles recorded.
mkdir -p "$HOME/.local/share/claude/versions"
fake_command "$HOME/.local/share/claude/versions/2" true
ln -sf "$HOME/.local/share/claude/versions/2" "$HOME/.local/bin/claude"
ledger_record claude yes dotfiles installed 1 "$HOME/.local/share/claude/versions/1" test
fake_command "$HOME/.local/bin/sd" true
ledger_record sd yes dotfiles installed 1 "$HOME/.local/opt/sd" test
PATH="$HOME/.local/bin:$TEST_SYSTEM_PATH" "$ROOT/bin/verify" --installed \
    > "$TEST_ROOT/moved.log" 2>&1 || true
grep -Fq 'ok   claude' "$TEST_ROOT/moved.log" \
    || { cat "$TEST_ROOT/moved.log" >&2; fail "self-updated claude was not accepted"; }
grep -Fq "note sd: satisfied by an external install at $HOME/.local/bin/sd" "$TEST_ROOT/moved.log" \
    || { cat "$TEST_ROOT/moved.log" >&2; fail "moved staged-release tool was not reported"; }

# What the ledger knows beyond ownership: a component from before the ledger
# is not pinned until adopted, and a failed update leaves the earlier install.
fake_command "$HOME/.local/bin/glow" true
ledger_record glow yes unknown installed 1 "$HOME/.local/bin/glow" test
ledger_record uv yes dotfiles update-failed 1 "$HOME/.local/bin/uv" test
PATH="$HOME/.local/bin:$TEST_SYSTEM_PATH" "$ROOT/bin/verify" --installed \
    > "$TEST_ROOT/ledger-notes.log" 2>&1 || true
grep -Fq "note glow: at $HOME/.local/bin/glow from before the ledger; not pinned until adopted" "$TEST_ROOT/ledger-notes.log" \
    || { cat "$TEST_ROOT/ledger-notes.log" >&2; fail "an unadopted component was not noted"; }
grep -Fq 'note uv: its last update failed' "$TEST_ROOT/ledger-notes.log" || fail "a failed update was not noted"

ledger_record starship yes dotfiles installed 1 "$HOME/.local/bin/starship" test
if PATH="$TEST_SYSTEM_PATH" "$ROOT/bin/verify" --installed >/dev/null 2>&1; then
    fail "installed verification ignored missing recorded component"
fi
mv "$TEST_ROOT/profile" "$XDG_STATE_HOME/dotfiles/profile"

rc=0
PATH="$TEST_SYSTEM_PATH" DOTFILES_TEST_PLATFORM=ubuntu \
    DOTFILES_TEST_OS_VERSION=24.04 DOTFILES_TEST_ARCH=x86_64 DOTFILES_TEST_SYSTEMD_RUNNING=0 \
    "$ROOT/bin/verify" --tier work --tail > "$TEST_ROOT/work-profile.log" 2>&1 || rc=$?
[[ $rc -ne 64 ]] || fail "composed --tier work --tail verification was rejected by the parser"
grep -Fxq 'Docker' "$TEST_ROOT/work-profile.log" || fail "Docker readiness verification did not run"
grep -Fxq 'Local sandboxes' "$TEST_ROOT/work-profile.log" || fail "sandbox readiness verification did not run"
grep -Fxq 'Tailscale' "$TEST_ROOT/work-profile.log" || fail "Tailscale verification did not run"

# --tier ai and --tier rdp check only that capability.
rc=0
PATH="$TEST_SYSTEM_PATH" "$ROOT/bin/verify" --tier ai > "$TEST_ROOT/ai.log" 2>&1 || rc=$?
[[ $rc -ne 64 ]] || fail "--tier ai was rejected"
grep -Eq '(claude|codex|opencode|pi): ' "$TEST_ROOT/ai.log" || fail "--tier ai did not check the AI CLIs"
grep -Fq 'ripgrep:' "$TEST_ROOT/ai.log" && { cat "$TEST_ROOT/ai.log" >&2; fail "--tier ai checked another tier's tools"; }
rc=0; "$ROOT/bin/verify" --tier >/dev/null 2>&1 || rc=$?
assert_eq "$rc" 64 "--tier without a value"
rc=0; "$ROOT/bin/verify" --bogus >/dev/null 2>&1 || rc=$?
assert_eq "$rc" 64 "an unknown option"

printf 'verify-profiles: ok\n'
