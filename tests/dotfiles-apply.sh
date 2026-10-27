#!/bin/bash
# dotfiles apply: the profile applied from observations. A dry run on an
# up-to-date machine prints no actions and names exactly what differs; --only
# installs nothing whose needs are missing, and refuses what the profile does
# not select; --reinstall=X reinstalls only X.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_REPO_ROOT="$ROOT"
source "$ROOT/tests/lib/harness.sh"
trap fixture_cleanup EXIT
fixture_init
unset DOTFILES_OPERATION TMUX
export NO_COLOR=1 DOTFILES_TEST_PLATFORM=ubuntu DOTFILES_TEST_ARCH=x86_64 DOTFILES_TEST_OS_VERSION=24.04
export DOTFILES_TEST_SYSTEMD_RUNNING=0
source "$ROOT/lib/install.sh"
# Nothing may download, build, or touch packages.
printf '#!/bin/sh\necho "curl $*" >> "%s/forbidden"\nexit 1\n' "$TEST_ROOT" > "$TEST_ROOT/bin/curl"
printf '#!/bin/sh\nexit 1\n' > "$TEST_ROOT/bin/dpkg-query"
chmod +x "$TEST_ROOT/bin/curl" "$TEST_ROOT/bin/dpkg-query"
mkdir -p "$HOME/.local/bin"
export PATH="$HOME/.local/bin:$TEST_ROOT/bin:$TEST_SYSTEM_PATH"

# An up-to-date bash tier: every applicable eget tool is a binary whose digest
# the fixture's lock records, owned by dotfiles; eget itself is the pin.
lock="$TEST_ROOT/versions.lock"
cp "$ROOT/versions.lock" "$lock"
export DOTFILES_VERSIONS_LOCK="$lock"
fake_tool() { # NAME BINARY
    printf '#!/bin/sh\necho "%s fixture"\n' "$1" > "$HOME/.local/bin/$2"
    chmod +x "$HOME/.local/bin/$2"
}
for name in "${REGISTRY_ORDER[@]}"; do
    [[ "$name" != packages:* && "${TOOL_METHOD[$name]}" == eget && "${TOOL_TIER[$name]:-}" == bash ]] || continue
    tool_applicable "$name" || continue
    fake_tool "$name" "${TOOL_BINARY[$name]}"
    for companion in ${TOOL_COMPANIONS[$name]:-}; do fake_tool "$companion" "$companion"; done
    digest="$(sha256sum "$HOME/.local/bin/${TOOL_BINARY[$name]}" | awk '{print $1}')"
    awk -F '\t' -v OFS='\t' -v n="$name" -v d="sha256:$digest" '$1 == n && $2 == "x86_64" { $8 = d } 1' "$lock" > "$lock.new"
    mv "$lock.new" "$lock"
    ledger_record "$name" yes dotfiles installed fixture "$HOME/.local/bin/${TOOL_BINARY[$name]}" "staged-release"
done
printf '#!/bin/sh\necho "eget version %s"\n' "$EGET_VERSION" > "$HOME/.local/bin/eget"
chmod +x "$HOME/.local/bin/eget"
ledger_record eget yes dotfiles installed "$EGET_VERSION" "$HOME/.local/bin/eget" staged-release
"$ROOT/setup.sh" --config --no-hooks --no-theme >/dev/null 2>&1 \
    || fail "fixture setup failed"
"$ROOT/bin/dotfiles" profile --tier bash --no-apply >/dev/null

apply() {
    local rc=0
    APPLY_OUTPUT="$("$ROOT/bin/dotfiles" apply "$@" 2>&1)" || rc=$?
    APPLY_RC="$rc"
    APPLY_ACTIONS="$(grep -Ei 'would|unknown|blocked' <<< "$APPLY_OUTPUT" || true)"
}

apply --dry-run
assert_eq "$APPLY_RC" 0 "dry run: $APPLY_OUTPUT"
assert_eq "$APPLY_ACTIONS" "" "a dry run on an up-to-date machine planned actions"

# A missing tool, another build of a pinned one, and a moved config link are
# exactly what the plan names.
rm "$HOME/.local/bin/fd"
printf '#!/bin/sh\necho other build\n' > "$HOME/.local/bin/bat"
rm "$HOME/.editorconfig"; ln -s /dev/null "$HOME/.editorconfig"
apply --dry-run
[[ "$APPLY_ACTIONS" == *"Would install fd $(versions_field fd want)"* \
   && "$APPLY_ACTIONS" == *"Would move bat from "*" to $(versions_field bat want)"* \
   && "$APPLY_ACTIONS" == *"$HOME/.editorconfig (links to /dev/null; would relink)"* ]] \
    || fail "the plan did not name what differs: $APPLY_ACTIONS"
assert_eq "$(grep -c . <<< "$APPLY_ACTIONS")" 3 "plan lines: $APPLY_ACTIONS"

# --reinstall=X plans a reinstall of X alone.
apply --dry-run --reinstall=sd
[[ "$APPLY_ACTIONS" == *"Would reinstall sd"* && "$APPLY_ACTIONS" != *"reinstall fzf"* ]] \
    || fail "--reinstall=sd: $APPLY_ACTIONS"

# --only installs nothing whose needs are missing.
"$ROOT/bin/dotfiles" profile --tier work --no-apply >/dev/null
apply --only tmux
assert_eq "$APPLY_RC" 1 "--only with a missing need"
[[ "$APPLY_OUTPUT" == *"Blocked: tmux needs packages:dev (package "* ]] || fail "tmux was not blocked: $APPLY_OUTPUT"
apply --only node
[[ "$APPLY_RC" == 1 && "$APPLY_OUTPUT" == *"Blocked: node needs nvm, which is not installed"* ]] \
    || fail "node was not blocked on nvm: $APPLY_OUTPUT"
[[ "$APPLY_OUTPUT" == *"Configs left as they are (--only)"* ]] || fail "--only deployed configs: $APPLY_OUTPUT"
[[ ! -e "$TEST_ROOT/forbidden" ]] || fail "a blocked component was installed: $(<"$TEST_ROOT/forbidden")"
# ... and refuses what the profile does not select.
apply --only claude
assert_eq "$APPLY_RC" 64 "--only outside the profile"
[[ "$APPLY_OUTPUT" == *"claude is not selected"* ]] || fail "--only claude: $APPLY_OUTPUT"

printf 'dotfiles-apply: ok\n'
