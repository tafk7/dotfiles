#!/bin/bash
# Component observation: structured fields, no side effects for any registry
# component, and exit 3 when the observation cannot be made.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_REPO_ROOT="$ROOT"
source "$ROOT/tests/lib/harness.sh"
trap fixture_cleanup EXIT
fixture_init
export DOTFILES_TEST_PLATFORM=ubuntu DOTFILES_TEST_ARCH=x86_64 DOTFILES_TEST_OS_VERSION=24.04
source "$ROOT/lib/install.sh"

field() { observation_field "$1" <<< "$2"; }

# --- Nothing observed changes anything, for every component, in-process and
# through each installer's --observe.
mkdir -p "$HOME/.local/bin"
printf '#!/bin/sh\necho "eza - banner\nv0.23.4 [+git]"\n' > "$HOME/.local/bin/eza"
chmod +x "$HOME/.local/bin/eza"
install_mutation_spies
# Service queries are reads; every other systemctl use is still a mutation.
printf '#!/bin/sh\ncase "$1" in is-active|is-enabled) exit 3 ;; esac\nprintf "systemctl\\t%%s\\n" "$*" >> "$DOTFILES_MUTATION_LOG"\nexit 97\n' \
    > "$TEST_ROOT/bin/systemctl"
before="$(fixture_managed_snapshot)"
for name in $(printf '%s\n' "${!TOOL_BINARY[@]}" | LC_ALL=C sort); do
    rc=0
    observe_component "$name" > "$TEST_ROOT/observation" 2>/dev/null || rc=$?
    [[ $rc -eq 0 || $rc -eq 3 ]] || fail "$name observation exited $rc"
    for key in applicable path owner identity want runnable companions ready; do
        grep -q "^$key=" "$TEST_ROOT/observation" || fail "$name observation lacks $key"
    done
    if [[ -f "$ROOT/installers/install-$name.sh" ]]; then
        rc=0
        "$ROOT/installers/install-$name.sh" --observe > "$TEST_ROOT/installer-observation" 2>/dev/null || rc=$?
        [[ $rc -eq 0 || $rc -eq 3 ]] || fail "install-$name.sh --observe exited $rc"
        cmp -s "$TEST_ROOT/observation" "$TEST_ROOT/installer-observation" \
            || fail "install-$name.sh --observe differs from the engine's observation"
    fi
done
[[ ! -s "$DOTFILES_MUTATION_LOG" ]] || fail "observation ran mutating commands: $(cat "$DOTFILES_MUTATION_LOG")"
assert_eq "$(fixture_managed_snapshot)" "$before" "observation changed HOME or XDG state"
export PATH="$TEST_SYSTEM_PATH"
rm -f "$TEST_ROOT"/bin/{mkdir,mv,rm,ln,cp,chmod,install,apt,apt-get,dpkg,tee,systemctl,sudo}

# --- Identity: an eget tool matching its recorded pin and digest is identified
# by tag; anything else by digest.
obs="$(observe_component eza)"
assert_eq "$(field owner "$obs")" external "an unrecorded binary is not owned"
[[ "$(field identity "$obs")" == sha256:* ]] || fail "unrecorded eget identity: $(field identity "$obs")"
assert_eq "$(field want "$obs")" "tag:$(eget_pinned_tag eza)" "eget want"
digest="$(sha256sum "$HOME/.local/bin/eza" | awk '{print $1}')"
ledger_record eza yes dotfiles installed v0.23.4 "$HOME/.local/bin/eza" "staged-release pin=v0.23.4 sha256=$digest"
obs="$(observe_component eza)"
assert_eq "$(field owner "$obs")/$(field identity "$obs")/$(field runnable "$obs")" "dotfiles/tag:v0.23.4/yes" "owned eget tool"
printf '#!/bin/sh\necho changed\n' >> "$HOME/.local/bin/eza"
[[ "$(field identity "$(observe_component eza)")" == sha256:* ]] || fail "a changed binary kept its tag identity"

# --- Absent, not applicable, external, and timed-out components.
obs="$(observe_component bat)"
assert_eq "$(field path "$obs")/$(field owner "$obs")/$(field ready "$obs")/$(field ready-reason "$obs")" "/none/no/not installed" "absent component"
obs="$(observe_component wsl2-ssh-agent)"
assert_eq "$(field applicable "$obs")" no "wsl-only component on native Ubuntu"
mkdir -p "$TEST_ROOT/usr/bin"
printf '#!/bin/sh\necho "fd 9.1.0"\n' > "$TEST_ROOT/usr/bin/fd"
printf '#!/bin/sh\nsleep 5\n' > "$TEST_ROOT/usr/bin/gdu"
chmod +x "$TEST_ROOT/usr/bin/fd" "$TEST_ROOT/usr/bin/gdu"
PATH="$TEST_ROOT/usr/bin:$PATH"
obs="$(observe_component fd)"
assert_eq "$(field owner "$obs")/$(field identity "$obs")" "external/sha256:$(sha256sum "$TEST_ROOT/usr/bin/fd" | awk '{print $1}')" "external eget tool"
rc=0
obs="$(DOTFILES_OBSERVE_TIMEOUT=1 observe_component gdu)" || rc=$?
assert_eq "$rc/$(field runnable "$obs")" "3/unknown" "a hung version probe"

# --- Unreadable state makes the observation incomplete.
printf 'schema\t1\nbroken row\n' > "$DOTFILES_LEDGER_FILE"
rc=0
observe_component eza >/dev/null || rc=$?
assert_eq "$rc" 3 "an unreadable ledger"

printf 'observe: ok\n'
