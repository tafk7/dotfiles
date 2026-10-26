#!/bin/bash
# dotfiles update against a local bare remote: a normal update re-execs the
# pulled code and runs setup with the profile; dirty, diverged, detached, and
# non-install-path checkouts stop before pulling; an ahead-only branch skips
# the pull and still applies.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_REPO_ROOT="$ROOT"
source "$ROOT/tests/lib/harness.sh"
trap fixture_cleanup EXIT
fixture_init
unset DOTFILES_OPERATION
export NO_COLOR=1 DOTFILES_TEST_PLATFORM=ubuntu DOTFILES_TEST_ARCH=x86_64 DOTFILES_TEST_OS_VERSION=24.04
export DOTFILES_TEST_SYSTEMD_RUNNING=0 DOTFILES_OPERATION_WAIT=1
export GIT_AUTHOR_NAME=Fixture GIT_AUTHOR_EMAIL=fixture@example.com GIT_COMMITTER_NAME=Fixture GIT_COMMITTER_EMAIL=fixture@example.com
export GIT_CONFIG_NOSYSTEM=1
export PATH="$TEST_ROOT/bin:$TEST_SYSTEM_PATH"

# The remote holds this tree as one commit; the install-path checkout clones it.
seed="$TEST_ROOT/seed" remote="$TEST_ROOT/remote.git" checkout="$TEST_ROOT/checkout"
mkdir -p "$seed"
tar -C "$ROOT" --exclude=.git -cf - . | tar -x -C "$seed"
git -C "$seed" init -q -b main && git -C "$seed" add -A && git -C "$seed" commit -qm seed
git clone -q --bare "$seed" "$remote"
git clone -q "$remote" "$checkout"
"$checkout/setup.sh" --config --no-hooks --no-theme --git-name Fixture --git-email fixture@example.com >/dev/null 2>&1 \
    || fail "fixture setup failed"

update() {
    local dir="${1:-$checkout}" rc=0
    UPDATE_OUTPUT="$("$dir/bin/dotfiles" update 2>&1)" || rc=$?
    UPDATE_RC="$rc"
}
upstream_commit() {
    local work="$TEST_ROOT/upstream-work"
    [[ -d "$work" ]] || git clone -q "$remote" "$work"
    git -C "$work" pull -q
    "$@" "$work"
    git -C "$work" commit -qam "${COMMIT_MESSAGE:-upstream change}"
    git -C "$work" push -q
}

# Nothing upstream: setup still applies the profile, and verify runs.
update
assert_eq "$UPDATE_RC" 0 "update with nothing upstream: $UPDATE_OUTPUT"
[[ "$UPDATE_OUTPUT" == *"up to date with its upstream"* && "$UPDATE_OUTPUT" == *"Applying the profile: setup.sh --config --no-hooks"* ]] \
    || fail "no-op update did not apply the profile: $UPDATE_OUTPUT"

# A normal update pulls, re-execs the new code, and reports the revisions.
mark_new_code() { sed -i 's/^update_continue() {$/&\n    echo "new code running"/' "$1/bin/dotfiles"; }
before="$(git -C "$checkout" rev-parse --short HEAD)"
upstream_commit mark_new_code
update
assert_eq "$UPDATE_RC" 0 "normal update: $UPDATE_OUTPUT"
after="$(git -C "$checkout" rev-parse --short HEAD)"
[[ "$after" != "$before" && "$UPDATE_OUTPUT" == *"new code running"* && "$UPDATE_OUTPUT" == *"update: $before -> $after"* ]] \
    || fail "update did not pull and re-exec the new code: $UPDATE_OUTPUT"

# Uncommitted changes stop it before anything is pulled.
printf '\n' >> "$checkout/README.md"
COMMIT_MESSAGE=second upstream_commit sh -c 'printf "x\n" >> "$1/README.md"' _
head_before="$(git -C "$checkout" rev-parse HEAD)"
update
assert_eq "$UPDATE_RC" 3 "dirty checkout"
[[ "$UPDATE_OUTPUT" == *"uncommitted changes"* && "$(git -C "$checkout" rev-parse HEAD)" == "$head_before" ]] \
    || fail "a dirty checkout was updated: $UPDATE_OUTPUT"
git -C "$checkout" checkout -q -- README.md

# Diverged: a local commit plus a new upstream one stops it.
printf 'local\n' > "$checkout/LOCAL"
git -C "$checkout" add LOCAL && git -C "$checkout" commit -qm local
update
assert_eq "$UPDATE_RC" 3 "diverged branch"
[[ "$UPDATE_OUTPUT" == *"diverged"* ]] || fail "divergence not reported: $UPDATE_OUTPUT"

# Ahead only: catch up with upstream by rebasing, then nothing to pull.
git -C "$checkout" pull -q --rebase
update
assert_eq "$UPDATE_RC" 0 "ahead-only branch: $UPDATE_OUTPUT"
[[ "$UPDATE_OUTPUT" == *"ahead of its upstream; nothing to pull"* ]] || fail "ahead-only not reported: $UPDATE_OUTPUT"

# A detached HEAD stops it.
git -C "$checkout" checkout -q --detach
update
assert_eq "$UPDATE_RC" 3 "detached HEAD"
git -C "$checkout" checkout -q main

# Another worktree is not the install path.
git -C "$checkout" worktree add -q "$TEST_ROOT/other" -b other
update "$TEST_ROOT/other"
assert_eq "$UPDATE_RC" 3 "worktree update"
[[ "$UPDATE_OUTPUT" == *"not the install path"* ]] || fail "worktree not refused: $UPDATE_OUTPUT"

printf 'dotfiles-update: ok\n'
