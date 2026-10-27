#!/bin/bash
# The machine profile: merge rules for setup flags, explicit removal and
# exclusion, validation before saving, previews that never write, and a
# proposal derived only from what dotfiles or the package manager installed.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_REPO_ROOT="$ROOT"
source "$ROOT/tests/lib/harness.sh"
trap fixture_cleanup EXIT
fixture_init
export NO_COLOR=1 DOTFILES_TEST_PLATFORM=ubuntu DOTFILES_TEST_ARCH=x86_64 DOTFILES_TEST_OS_VERSION=24.04
source "$ROOT/lib/runtime.sh"
source "$ROOT/lib/config.sh"
source "$ROOT/lib/state.sh"
source "$ROOT/lib/profile.sh"

profile_value() { awk -F '\t' -v key="$1" '$1 == key { print $2 }' "$DOTFILES_PROFILE_FILE"; }
dotfiles() { "$ROOT/bin/dotfiles" "$@"; }

# --- Merge rules: flags only add.
profile_reset
profile_merge work tail all "" no-git
assert_eq "${PROFILE[tier]}/${PROFILE[capabilities]}/${PROFILE[ai]}/${PROFILE[opt-outs]}" "work/tail/all/no-git" "first merge"
profile_merge bash "" some claude ""
assert_eq "${PROFILE[tier]}/${PROFILE[ai]}" "work/all" "a lower tier or one AI tool lowered the profile"
(( ${#PROFILE_CHANGES[@]} == 0 )) || fail "a no-op merge reported changes: ${PROFILE_CHANGES[*]}"
PROFILE[ai.exclude]=pi
profile_merge config "" some pi ""
assert_eq "${PROFILE[ai.exclude]}" "" "an explicit AI flag did not lift its exclusion"
profile_reset
profile_merge dev gcloud some "claude,codex" ""
assert_eq "${PROFILE[ai]}" "claude,codex" "per-tool AI flags"
assert_eq "$(profile_setup_args | paste -sd ' ')" "--dev --gcloud --claude --codex" "setup arguments for a tool list"

# --- setup merges its flags after validation; previews and refusals never write.
run_setup() {
    "$ROOT/setup.sh" "$@" --no-hooks --no-theme --git-name Fixture --git-email fixture@example.com >/dev/null 2>&1
}
run_setup --config --dry-run
profile_exists && fail "a preview wrote the profile"
printf 'ID=ubuntu\nVERSION_ID="26.04"\n' > "$TEST_ROOT/os-release"
DOTFILES_OS_RELEASE="$TEST_ROOT/os-release" DOTFILES_TEST_OS_VERSION=26.04 run_setup --azure && fail "unsupported --azure accepted"
profile_exists && fail "a refused request wrote the profile"
run_setup --config --no-git
assert_eq "$(profile_value tier)/$(profile_value opt-outs)" "config/no-git,no-hooks" "setup --config created the profile"
"$ROOT/setup.sh" --config --no-hooks --no-theme --git-name Fixture --git-email fixture@example.com >/dev/null 2>&1
assert_eq "$(profile_value opt-outs)" "no-git,no-hooks" "a later run without an opt-out removed it"

# --- dotfiles profile: show, add, remove, tier. The editor-plugins key, from
# profiles before the dev tier included the plugins, is ignored and dropped.
printf 'schema\t1\ntier\twork\ncapabilities\ttail\nai\tall\nai.exclude\t-\nopt-outs\t-\neditor-plugins\tno\n' > "$DOTFILES_PROFILE_FILE"
shown="$(dotfiles profile)"
[[ "$shown" == *"tier            work"* && "$shown" == *"ai              all"* ]] || fail "profile display: $shown"
out="$(dotfiles profile --remove pi)"
assert_eq "$(profile_value ai)/$(profile_value ai.exclude)" "all/pi" "removing one tool under ai=all"
! grep -q '^editor-plugins' "$DOTFILES_PROFILE_FILE" || fail "a retired key survived a save"
[[ "$out" == *"uninstall-tool pi"* ]] || fail "removal did not print the uninstall command: $out"
profile_load
assert_eq "$(profile_setup_args | paste -sd ' ')" "--work --tail --claude --codex --opencode" "an exclusion in the setup arguments"
out="$(dotfiles profile --add gcloud --no-apply)"
assert_eq "$(profile_value capabilities)" "gcloud,tail" "adding a capability"
[[ "$out" == *"plan:"*"Would install nvm"* && "$out" == *"not applied"* ]] || fail "add did not show the plan: $out"
rc=0
DOTFILES_TEST_OS_VERSION=26.04 dotfiles profile --add azure --no-apply >/dev/null 2>&1 || rc=$?
[[ $rc -ne 0 && "$(profile_value capabilities)" == "gcloud,tail" ]] || fail "an unsupported addition was saved"
rc=0
dotfiles profile --add bogus --no-apply >/dev/null 2>&1 || rc=$?
assert_eq "$rc" 64 "unknown selection"
# Non-interactive changes are saved but not applied without --yes.
out="$(dotfiles profile --add rdp </dev/null)"
[[ "$out" == *"Saved; not applied"* ]] || fail "a non-interactive add applied without --yes: $out"
mkdir -p "$HOME/.local/bin"
ledger_record docker yes package-manager installed 1 /usr/bin/docker apt-in-place
out="$(dotfiles profile --tier dev)"
assert_eq "$(profile_value tier)" dev "lowering the tier"
[[ "$out" == *"uninstall-tool docker"* && "$out" != *"Saved; not applied"* ]] || fail "lowering the tier: $out"

# --- A proposal comes from what is installed: dotfiles' own installs and APT
# packages, whatever the ledger recorded (an older checkout recorded Docker and
# Tailscale external), never an external tool or a failed install. It is saved
# only when confirmed.
rm -f "$DOTFILES_PROFILE_FILE" "$DOTFILES_LEDGER_FILE"
printf '#!/bin/sh\nfor package; do :; done\ncase "$package" in docker-ce|tailscale) ;; *) exit 1 ;; esac\ncase "$*" in *Status*) printf installed ;; *) printf 1.0 ;; esac\n' \
    > "$TEST_ROOT/bin/dpkg-query"
chmod +x "$TEST_ROOT/bin/dpkg-query"
for tool in docker tailscale gcloud; do fake_command "$TEST_ROOT/bin/$tool" true; done
for tool in eza claude; do fake_command "$HOME/.local/bin/$tool" true; done
ledger_record eza yes dotfiles installed 1 "$HOME/.local/bin/eza" staged-release
ledger_record docker yes external present 1 /usr/bin/docker apt-in-place
ledger_record tailscale yes external present 1 /usr/bin/tailscale apt-in-place
ledger_record claude yes dotfiles installed 1 "$HOME/.local/bin/claude" moving-vendor-installer
ledger_record gcloud yes external present 1 /snap/bin/gcloud apt-in-place
ledger_record codex yes dotfiles failed "" "" x
propose_path="$TEST_ROOT/bin:$HOME/.local/bin:$TEST_SYSTEM_PATH"
out="$(PATH="$propose_path" dotfiles profile --propose </dev/null)"
[[ "$out" == *"tier            work"* && "$out" == *"capabilities    tail"* && "$out" == *"ai              claude"* ]] \
    || fail "proposal: $out"
profile_exists && fail "a proposal was saved without confirmation"
PATH="$propose_path" dotfiles profile --propose --yes >/dev/null
assert_eq "$(profile_value tier)/$(profile_value capabilities)/$(profile_value ai)" "work/tail/claude" "saved proposal"

# A damaged profile is reported, not silently replaced.
printf 'schema\t1\ntier\tgalaxy\n' > "$DOTFILES_PROFILE_FILE"
rc=0
dotfiles profile >/dev/null 2>&1 || rc=$?
assert_eq "$rc" 3 "an invalid profile was shown as valid"

printf 'profile: ok\n'
