#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_ROOT="$(mktemp -d)"
trap 'rm -rf "$TEST_ROOT"' EXIT

repo="$TEST_ROOT/repo"
git init -q "$repo"
mkdir -p "$repo/hooks" "$repo/bin" "$repo/lib"
cp "$ROOT/hooks/pre-commit" "$repo/hooks/pre-commit"
cp "$ROOT/bin/install-git-hooks" "$repo/bin/install-git-hooks"
cp "$ROOT/lib/runtime.sh" "$repo/lib/runtime.sh"

DOTFILES_DIR="$repo" "$repo/bin/install-git-hooks" --check >/dev/null 2>&1 && {
    echo "FAIL: check unexpectedly succeeded before install" >&2; exit 1;
}
DOTFILES_DIR="$repo" "$repo/bin/install-git-hooks" --quiet
DOTFILES_DIR="$repo" "$repo/bin/install-git-hooks" --check >/dev/null
[[ "$(readlink "$repo/.git/hooks/pre-commit")" == "$repo/hooks/pre-commit" ]] \
    || { echo "FAIL: standalone hook target" >&2; exit 1; }
DOTFILES_DIR="$repo" "$repo/bin/install-git-hooks" --uninstall --quiet
[[ ! -e "$repo/.git/hooks/pre-commit" ]] || { echo "FAIL: hook uninstall" >&2; exit 1; }

git -C "$repo" config user.name Test
git -C "$repo" config user.email test@example.com
touch "$repo/file"; git -C "$repo" add file; git -C "$repo" commit -qm initial
git -C "$repo" worktree add -q "$TEST_ROOT/linked" -b linked-test
mkdir -p "$TEST_ROOT/linked/bin" "$TEST_ROOT/linked/lib" "$TEST_ROOT/linked/hooks"
cp "$ROOT/bin/install-git-hooks" "$TEST_ROOT/linked/bin/install-git-hooks"
cp "$ROOT/lib/runtime.sh" "$TEST_ROOT/linked/lib/runtime.sh"
cp "$ROOT/hooks/pre-commit" "$TEST_ROOT/linked/hooks/pre-commit"
if DOTFILES_DIR="$TEST_ROOT/linked" "$TEST_ROOT/linked/bin/install-git-hooks" --quiet >/dev/null 2>&1; then
    echo "FAIL: linked worktree modified shared hooks without --shared" >&2; exit 1
fi
[[ ! -e "$repo/.git/hooks/pre-commit" ]] || { echo "FAIL: shared hook mutated" >&2; exit 1; }

# Denylist: skipped when unset; whole words only; the list stays outside the repo.
printf '# comment\n\nAcmeCorp\n' > "$TEST_ROOT/denylist"
printf 'contact acmecorp support\n' > "$repo/notes.txt"
git -C "$repo" add notes.txt
(cd "$repo" && hooks/pre-commit) || { echo "FAIL: unset denylist blocked a commit" >&2; exit 1; }
if (cd "$repo" && DOTFILES_DENYLIST="$TEST_ROOT/denylist" hooks/pre-commit 2>/dev/null); then
    echo "FAIL: denylisted word was not blocked" >&2; exit 1
fi
printf 'contact acmecorporation support\n' > "$repo/notes.txt"
git -C "$repo" add notes.txt
(cd "$repo" && DOTFILES_DENYLIST="$TEST_ROOT/denylist" hooks/pre-commit) \
    || { echo "FAIL: denylist matched inside a longer word" >&2; exit 1; }
if (cd "$repo" && DOTFILES_DENYLIST="$TEST_ROOT/missing" hooks/pre-commit 2>/dev/null); then
    echo "FAIL: unreadable denylist was ignored" >&2; exit 1
fi

printf 'git-hooks: ok\n'
