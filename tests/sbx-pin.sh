#!/bin/bash
# sbx converges on its pin and holds it, writing a receipt; it moves only holds
# it placed or adopted, asks once about any other hold, and remembers a no.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_REPO_ROOT="$ROOT"
source "$ROOT/tests/lib/harness.sh"
trap fixture_cleanup EXIT
fixture_init
export NO_COLOR=1 DOTFILES_TEST_PLATFORM=ubuntu DOTFILES_TEST_ARCH=x86_64 DOTFILES_TEST_OS_VERSION=24.04
source "$ROOT/lib/install.sh"
pin="$SBX_VERSION"

# A fake package world: dpkg-query reads it, sudo apt-get and apt-mark change
# it, and sbx reports the installed version.
world="$TEST_ROOT/world"; mkdir -p "$world"
export SBX_WORLD="$world"
cat > "$TEST_ROOT/bin/dpkg-query" <<'EOF'
#!/bin/sh
[ -f "$SBX_WORLD/version" ] || exit 1
case "$*" in
    *Status-Status*) echo installed ;;
    *Status-Want*) cat "$SBX_WORLD/want" 2>/dev/null || echo install ;;
    *Version*) cat "$SBX_WORLD/version" ;;
esac
EOF
cat > "$TEST_ROOT/bin/sudo" <<'EOF'
#!/bin/sh
echo "$*" >> "$SBX_WORLD/sudo.log"
case "$*" in
    *apt-mark\ hold\ docker-sbx*) echo hold > "$SBX_WORLD/want" ;;
    *apt-get*install*docker-sbx=*)
        for arg; do case "$arg" in docker-sbx=*) v="${arg#docker-sbx=}"; echo "${v%-\*}-1~ubuntu.24.04~noble" > "$SBX_WORLD/version" ;; esac; done ;;
esac
EOF
cat > "$TEST_ROOT/bin/sbx" <<'EOF'
#!/bin/sh
[ "$1" = version ] && v="$(cat "$SBX_WORLD/version")" && echo "sbx version: v${v%%-*} abc"
EOF
chmod +x "$TEST_ROOT/bin/"*
export PATH="$TEST_ROOT/bin:$TEST_SYSTEM_PATH"
# Docker's repository is already configured.
sources="$TEST_ROOT/apt/sources.list.d"; mkdir -p "$sources" "$TEST_ROOT/apt/keyrings"
printf 'Types: deb\nURIs: https://download.docker.com/linux/ubuntu\nSuites: noble\nComponents: stable\n' > "$sources/docker.sources"
export DOTFILES_APT_SOURCES_DIR="$sources" DOTFILES_APT_KEYRINGS_DIR="$TEST_ROOT/apt/keyrings"

state() { # VERSION HELD
    printf '%s-1~ubuntu.24.04~noble\n' "$1" > "$world/version"
    if [[ "$2" == held ]]; then echo hold > "$world/want"; else echo install > "$world/want"; fi
    rm -f "$world/sudo.log"
}
sbx_install() { local rc=0; "$ROOT/installers/install-sbx.sh" "$@" < /dev/null > "$TEST_ROOT/out" 2>&1 || rc=$?; RC=$rc; }
sudo_log() { cat "$world/sudo.log" 2>/dev/null || true; }

# Not installed: install the pin, hold it, write the receipt.
rm -f "$world/version" "$world/want"
sbx_install
assert_eq "$RC" 0 "fresh install: $(<"$TEST_ROOT/out")"
[[ "$(sudo_log)" == *"docker-sbx=$pin-*"* && "$(<"$world/want")" == hold ]] || fail "the pin was not installed and held: $(sudo_log)"
assert_eq "$(hold_line docker-sbx | cut -f1-3)" "docker-sbx	$pin	placed" "receipt"

# At the pin and held by dotfiles: nothing to do.
rm -f "$world/sudo.log"
sbx_install
assert_eq "$RC/$(sudo_log)" "2/" "a held pin"

# At the pin but not held: hold it.
state "$pin" unheld
sbx_install
assert_eq "$RC" 0 "an unheld pin"
[[ "$(sudo_log)" == *"apt-mark hold docker-sbx"* && "$(sudo_log)" != *install* ]] || fail "an unheld pin was not just held: $(sudo_log)"

# Its own hold on an old version: moved with the pin.
state 0.40.0 held
sbx_install
assert_eq "$RC" 0 "a moved pin: $(<"$TEST_ROOT/out")"
[[ "$(sudo_log)" == *"--allow-change-held-packages -y docker-sbx=$pin-*"* ]] || fail "the owned hold was not moved: $(sudo_log)"
assert_eq "$(dpkg-query -W -f='${Version}' docker-sbx)" "$pin-1~ubuntu.24.04~noble" "version after the move"

# Someone else's hold: never moved without a decision, asked only in a terminal.
rm -f "$DOTFILES_HOLDS_FILE"
state 0.40.0 held
sbx_install
assert_eq "$RC/$(sudo_log)" "2/" "someone else's hold, non-interactively"
[[ "$(<"$TEST_ROOT/out")" == *"rerun setup in a terminal"* ]] || fail "the foreign hold was not reported: $(<"$TEST_ROOT/out")"
[[ -z "$(hold_status docker-sbx)" ]] || fail "a receipt was written without an answer"
ask() { # ANSWER
    printf '%s\n' "$1" | script -qec "$ROOT/installers/install-sbx.sh" /dev/null > "$TEST_ROOT/out" 2>&1 || true
}
ask n
assert_eq "$(hold_status docker-sbx)/$(sudo_log)" "declined/" "a declined adoption"
sbx_install
[[ "$RC" == 2 && "$(<"$TEST_ROOT/out")" == *"who moves it"* ]] || fail "a declined hold was asked about again: $(<"$TEST_ROOT/out")"
rm -f "$DOTFILES_HOLDS_FILE"
ask y
assert_eq "$(hold_line docker-sbx | cut -f1-3)" "docker-sbx	$pin	adopted" "an adopted hold, moved to the pin"
[[ "$(sudo_log)" == *"docker-sbx=$pin-*"* ]] || fail "the adopted hold was not moved: $(sudo_log)"

# Dry runs change nothing.
state 0.40.0 unheld
before="$(fixture_managed_snapshot)"
sbx_install --dry-run
assert_eq "$RC/$(sudo_log)" "0/" "dry run"
[[ "$(<"$TEST_ROOT/out")" == *"install docker-sbx $pin (replacing 0.40.0)"* ]] || fail "dry run plan: $(<"$TEST_ROOT/out")"
assert_eq "$(fixture_managed_snapshot)" "$before" "dry run changed state"

# Verify reports each hold state.
source "$ROOT/lib/outcomes.sh"
source "$ROOT/lib/profile.sh"
source "$ROOT/lib/verify.sh"
feature_enabled() { return 1; }
verify_expected_components() { echo sbx; }
observe_component() { printf 'applicable=yes\n'; }
hold_outcome() { verify_components 2>/dev/null | awk -F '\t' '$3 == "sbx hold" { print $1 ": " $4 }'; }
state "$pin" unheld
[[ "$(hold_outcome)" == "convergence: "*"not held"* ]] || fail "an unheld sbx: $(hold_outcome)"
state "$pin" held
hold_record docker-sbx "$pin" placed
[[ "$(hold_outcome)" == "ok: held by dotfiles" ]] || fail "an owned hold: $(hold_outcome)"
rm -f "$DOTFILES_HOLDS_FILE"
[[ "$(hold_outcome)" == "health: "*"decide whether dotfiles adopts"* ]] || fail "a foreign hold: $(hold_outcome)"

printf 'sbx-pin: ok\n'
