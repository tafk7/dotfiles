#!/bin/bash
# --upgrade moves only what is not pinned: the selection's installed APT
# packages through apt's only-upgrade, never removing, with its simulated
# transaction shown first and held packages skipped; the self-updating
# components and rustup through their update operation. Pinned components are
# not touched, and upgraded APT components reach the ledger.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_REPO_ROOT="$ROOT"
source "$ROOT/tests/lib/harness.sh"
trap fixture_cleanup EXIT
fixture_init
export NO_COLOR=1 DOTFILES_TEST_PLATFORM=ubuntu DOTFILES_TEST_ARCH=x86_64 DOTFILES_TEST_OS_VERSION=24.04
export APT_WORLD="$TEST_ROOT/apt"
mkdir -p "$APT_WORLD"
# Installed packages and their versions; docker-sbx and tailscale are held.
printf '%s\n' zsh=5.9-1 git=1:2.43-1 docker-ce=5:27.0-1 tailscale=1.80-1 docker-sbx=0.49.2-1 > "$APT_WORLD/installed"
cat > "$TEST_ROOT/bin/dpkg-query" <<'EOF'
#!/bin/sh
for pkg; do :; done
line="$(grep "^$pkg=" "$APT_WORLD/installed")" || exit 1
case "$*" in
    *Status-Status*) echo installed ;;
    *Status-Want*) case "$pkg" in docker-sbx|tailscale) echo hold ;; *) echo install ;; esac ;;
    *Version*) echo "${line#*=}" ;;
esac
EOF
# apt-get -s prints a simulated transaction: zsh and an unnamed dependency.
cat > "$TEST_ROOT/bin/apt-get" <<'EOF'
#!/bin/sh
echo "apt-get $*" >> "$APT_WORLD/apt.log"
case "$*" in
    *-s*) echo 'Inst zsh [5.9-1] (5.9-2 Ubuntu:24.04/noble-updates [amd64])'
          echo 'Inst libnew (1.0-1 Ubuntu:24.04/noble [amd64])' ;;
esac
EOF
printf '#!/bin/sh\necho "sudo $*" >> "$APT_WORLD/apt.log"\ncase "$*" in *install*) sed -i "s/^zsh=.*/zsh=5.9-2/" "$APT_WORLD/installed" ;; esac\n' > "$TEST_ROOT/bin/sudo"
chmod +x "$TEST_ROOT/bin/"*
export PATH="$TEST_ROOT/bin:$TEST_SYSTEM_PATH"
source "$ROOT/setup.sh"
installers=""
run_installer() { installers+=" $1${2:+:$2}"; }
configure_component() { :; }
feature_enabled() { return 1; }

parse_arguments --work --tail --claude --pi --upgrade
DRY_RUN=true
out="$(upgrade_selection 2>&1)"
[[ "$out" == *"Would upgrade zsh 5.9-1 -> 5.9-2"* && "$out" == *"Would upgrade libnew new -> 1.0-1 (dependency)"* ]] \
    || fail "the plan did not show apt's simulated transaction: $out"
[[ "$out" == *"Held, so not upgraded: tailscale"* && "$out" != *docker-sbx* ]] || fail "held packages: $out"
grep -q -- 'install --only-upgrade --no-remove ' "$APT_WORLD/apt.log" || fail "the simulation did not use only-upgrade"
! grep -q '^sudo' "$APT_WORLD/apt.log" || fail "a dry run ran apt as root: $(<"$APT_WORLD/apt.log")"

DRY_RUN=false
: > "$APT_WORLD/apt.log"; installers=""
upgrade_selection >/dev/null 2>&1 || fail "upgrade failed"
real="$(grep '^sudo .*install --only-upgrade' "$APT_WORLD/apt.log")" || fail "apt was not run: $(<"$APT_WORLD/apt.log")"
[[ "$real" == *"--no-remove -y "* && " $real " == *" zsh "* && " $real " == *" git "* && " $real " == *" docker-ce "* ]] \
    || fail "the selection's packages were not all upgraded: $real"
[[ " $real " != *" docker-sbx "* && " $real " != *" tailscale "* ]] || fail "a held or pinned package was upgraded: $real"
grep -q '^sudo .*apt-get .* update' "$APT_WORLD/apt.log" || fail "the package index was not updated first"
assert_eq "$installers" " rust:update claude:update pi:update" "update operations"
[[ "$(ledger_line zsh | cut -f5)" == 5.9-2 ]] || fail "the upgraded zsh version did not reach the ledger: $(ledger_line zsh)"

# --only narrows the upgrade to the named components, without APT.
: > "$APT_WORLD/apt.log"; installers=""
ONLY_COMPONENTS=claude upgrade_selection >/dev/null 2>&1
assert_eq "$installers" " claude:update" "--only claude --upgrade"
[[ ! -s "$APT_WORLD/apt.log" ]] || fail "--only ran apt"

printf 'upgrade: ok\n'
