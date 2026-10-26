#!/bin/bash
# Config state and retirement: each deployed entry is recorded after it is
# written; an entry whose source left the manifest is retired, with a backup,
# only while it is exactly what setup wrote and under the approved roots; a
# changed one is kept and reported; what this run skipped is never retired; a
# failure keeps the records made before it. The portable Git config's content
# is checked against what setup would render.
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
export PATH="$TEST_ROOT/bin:$TEST_SYSTEM_PATH"

setup_config() {
    local rc=0
    SETUP_OUTPUT="$("$ROOT/setup.sh" --config --no-hooks --no-theme --git-name Fixture --git-email fixture@example.com "$@" 2>&1)" || rc=$?
    SETUP_RC="$rc"
}
record() { deployed_line "$1" 2>/dev/null | cut -f2-4; }

# Each deployed entry is recorded with its exact identity.
setup_config
assert_eq "$SETUP_RC" 0 "fixture setup: $SETUP_OUTPUT"
assert_eq "$(record "$HOME/.bashrc")" "link	$ROOT/entry/bash.sh	bash.sh" "a link's record"
portable="$(portable_gitconfig_path)"
assert_eq "$(record "$portable")" "rendered	sha256:$(sha256sum "$portable" | awk '{print $1}')	gitconfig" "the rendered gitconfig's record"
assert_eq "$(record "$HOME/.gitconfig")" "merged	include:$portable	gitconfig" "the merged include's record"
[[ -z "$(record "$HOME/.tmux.conf")" ]] || fail "a config whose owner is absent was recorded"

# A change event only for a link that changed on disk: a first run over links
# already in place (no records yet) records none; a recreated link does. Under
# dotfiles apply, its refresh follows, so setup prints no next steps.
change_record shell "marker" 1000
rm "$DOTFILES_DEPLOYED_FILE"
DOTFILES_REFRESH_FOLLOWS=1 setup_config
assert_eq "$(change_line shell | cut -f2-)" "1000	marker" "links already in place"
[[ "$SETUP_OUTPUT" != *"Next Steps"* ]] || fail "next steps printed before apply's refresh: $SETUP_OUTPUT"
rm "$HOME/.bashrc"
setup_config
[[ "$(change_line shell | cut -f3)" == "bash.sh linked" ]] || fail "a recreated link recorded no change: $(change_line shell)"
[[ "$SETUP_OUTPUT" == *"Next Steps"*"dotfiles verify"* ]] || fail "setup's next steps: $SETUP_OUTPUT"

# Entries whose sources left the manifest: one unchanged, one redirected, one
# outside the approved roots, and an unchanged rendered file.
ln -s "$ROOT/configs/retired-thing" "$HOME/.retired-thing"
deployed_record "$HOME/.retired-thing" link "$ROOT/configs/retired-thing" retired-thing
ln -s /dev/null "$HOME/.redirected"
deployed_record "$HOME/.redirected" link "$ROOT/configs/redirected" redirected
mkdir -p "$TEST_ROOT/outside"
ln -s "$ROOT/configs/outside" "$TEST_ROOT/outside/link"
deployed_record "$TEST_ROOT/outside/link" link "$ROOT/configs/outside" outside
printf 'rendered\n' > "$XDG_CONFIG_HOME/old-rendered"
deployed_record "$XDG_CONFIG_HOME/old-rendered" rendered "sha256:$(sha256sum "$XDG_CONFIG_HOME/old-rendered" | awk '{print $1}')" old-rendered

# verify and diff-config report them; a dry run says what would happen.
verify_out="$("$ROOT/bin/dotfiles" verify 2>&1 || true)"
[[ "$verify_out" == *"$HOME/.retired-thing: its source retired-thing left the manifest"* ]] || fail "verify did not report a retirement: $verify_out"
[[ "$("$ROOT/bin/diff-config")" == *"retiring"*"retired-thing"* ]] || fail "diff-config did not list the retirement"
setup_config --dry-run
[[ "$SETUP_OUTPUT" == *"Would retire $HOME/.retired-thing"* && "$SETUP_OUTPUT" == *"Would retire $XDG_CONFIG_HOME/old-rendered"* \
   && "$SETUP_OUTPUT" == *"$HOME/.redirected changed since setup deployed it"* ]] || fail "dry run: $SETUP_OUTPUT"
[[ -L "$HOME/.retired-thing" ]] || fail "a dry run retired something"

setup_config
assert_eq "$SETUP_RC" 0 "retiring setup: $SETUP_OUTPUT"
[[ ! -e "$HOME/.retired-thing" && ! -L "$HOME/.retired-thing" ]] || fail "an unchanged retired link was kept"
[[ ! -e "$XDG_CONFIG_HOME/old-rendered" ]] || fail "an unchanged rendered file was kept"
backup="$(find "$DOTFILES_BACKUP_PREFIX" -name .retired-thing)"
[[ -L "$backup" && "$(readlink "$backup")" == "$ROOT/configs/retired-thing" ]] || fail "the retired link was not backed up"
[[ -n "$(find "$DOTFILES_BACKUP_PREFIX" -name old-rendered)" ]] || fail "the retired rendered file was not backed up"
[[ "$(readlink "$HOME/.redirected")" == /dev/null && "$SETUP_OUTPUT" == *"Kept $HOME/.redirected"* ]] \
    || fail "a redirected link was not kept and reported"
[[ -L "$TEST_ROOT/outside/link" && "$SETUP_OUTPUT" == *"outside the roots setup manages"* ]] \
    || fail "a target outside the approved roots was touched or not reported"
for target in "$HOME/.retired-thing" "$HOME/.redirected" "$TEST_ROOT/outside/link" "$XDG_CONFIG_HOME/old-rendered"; do
    [[ -z "$(record "$target")" ]] || fail "$target's record remained"
done
setup_config
[[ "$SETUP_OUTPUT" != *"Kept "* && "$SETUP_OUTPUT" != *"Retired "* ]] || fail "a retirement was reported twice"

# What a run skips is never retired: --no-git leaves the gitconfig records.
setup_config --no-git
[[ -n "$(record "$portable")" && -f "$portable" ]] || fail "--no-git retired the gitconfig"
"$ROOT/bin/dotfiles" profile --remove no-git --no-apply >/dev/null  # the opt-out is durable

# The portable Git config's content is checked against what setup renders.
printf '# local edit\n' >> "$portable"
verify_out="$("$ROOT/bin/dotfiles" verify 2>&1 || true)"
[[ "$verify_out" == *"$portable: differs from what setup renders"* ]] || fail "verify missed a changed gitconfig: $verify_out"
[[ "$("$ROOT/bin/diff-config")" == *"drifted"*"differs from what setup renders"* ]] || fail "diff-config missed a changed gitconfig"
setup_config
cmp -s <(render_portable_gitconfig "$ROOT/configs/gitconfig") "$portable" || fail "setup did not re-render the gitconfig"

# A failure keeps the records made before it, and records nothing it did not write.
rm "$HOME/.editorconfig"
deployed_remove "$HOME/.ssh/config"; deployed_remove "$HOME/.editorconfig"
rm -rf "$HOME/.ssh"; printf 'not a directory\n' > "$HOME/.ssh"
setup_config
[[ "$SETUP_RC" != 0 ]] || fail "a failed link reported success"
[[ -n "$(record "$HOME/.editorconfig")" && -z "$(record "$HOME/.ssh/config")" ]] \
    || fail "records after a partial failure: $(deployed_entries)"

printf 'config-retirement: ok\n'
