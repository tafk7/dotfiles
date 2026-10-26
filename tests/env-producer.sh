#!/bin/bash
# The environment producer: the managed variables from the repo defaults and
# ~/.shell.env, never from direnv, user startup files, or inherited values;
# respected variables inherited; and PATH segments replaced without moving
# anyone else's.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_REPO_ROOT="$ROOT"
source "$ROOT/tests/lib/harness.sh"
trap fixture_cleanup EXIT
fixture_init
source "$ROOT/lib/environment.sh"
export PATH="$TEST_ROOT/bin:$TEST_SYSTEM_PATH"
value() { awk -F '\t' -v n="$1" '$1 == n { print $2; found=1 } END { exit !found }' <<< "$PRODUCED"; }

# direnv and every user startup file would leave a mark if they ran.
mkdir -p "$HOME/.local/bin"
printf '#!/bin/sh\ntouch "%s/direnv-ran"\n' "$TEST_ROOT" > "$HOME/.local/bin/direnv"
chmod +x "$HOME/.local/bin/direnv"
for file in .shell.local .bashrc .bash_profile .profile .zshrc; do
    printf 'touch "%s/startup-ran"\n' "$TEST_ROOT" > "$HOME/$file"
done
printf 'export PROJECTS_DIRS="$HOME/mine"\nexport PATH="$HOME/machine-bin:$PATH"\n' > "$HOME/.shell.env"
mkdir -p "$HOME/go/bin" "$HOME/machine-bin"

PRODUCED="$(EDITOR=bogus PAGER=most XDG_CONFIG_HOME="$TEST_ROOT/custom-config" env_produce "$ROOT")"
[[ ! -e "$TEST_ROOT/direnv-ran" && ! -e "$TEST_ROOT/startup-ran" ]] || fail "the producer ran direnv or a user startup file"
assert_eq "$(value PROJECTS_DIRS)" "$HOME/mine" "a machine override in ~/.shell.env"
[[ "$(value EDITOR)" != bogus && "$(value PAGER)" == less ]] || fail "an inherited owned value leaked: $PRODUCED"
assert_eq "$(value DOTFILES_DIR)" "$ROOT" "the checkout"
assert_eq "$(value GOPATH)" "$HOME/go" "GOPATH while ~/go exists"
segments="$(value PATH)"
[[ ":$segments:" == *":$HOME/machine-bin:"* && ":$segments:" == *":$HOME/go/bin:"* && ":$segments:" == *":$ROOT/bin:"* ]] \
    || fail "PATH segments: $segments"
[[ ":$segments:" != *":/usr/bin:"* ]] || fail "the base PATH counted as dotfiles' segments: $segments"
# Respected variables keep their inherited values, so none is published.
! grep -q '^-\?XDG_CONFIG_HOME' <<< "$PRODUCED" || fail "a respected variable was published"

# An owned variable that no longer applies is reported unset.
rm -rf "$HOME/go"
PRODUCED="$(env_produce "$ROOT")"
grep -qx -- '-GOPATH' <<< "$PRODUCED" || fail "GOPATH was not reported unset: $PRODUCED"
new_segments="$(value PATH)"
[[ ":$new_segments:" != *":$HOME/go/bin:"* ]] || fail "a removed directory stayed a segment"

# Replacing segments: the old set goes, the new set goes in front, and every
# other entry keeps its place.
replaced="$(env_path_replace "$segments" "$new_segments" "$segments:/opt/vendor/bin:/usr/bin:$HOME/go/bin")"
[[ ":$replaced:" != *":$HOME/go/bin:"* ]] || fail "a removed segment stayed on PATH: $replaced"
[[ "$replaced" == "$new_segments:/opt/vendor/bin:/usr/bin" ]] || fail "PATH after replacing segments: $replaced"
assert_eq "$(env_path_replace "" "/a" "/b:/a:/c")" "/a:/b:/c" "a new segment already on PATH moves to the front"

printf 'env-producer: ok\n'
