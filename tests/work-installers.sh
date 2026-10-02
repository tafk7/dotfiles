#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_REPO_ROOT="$ROOT"; source "$ROOT/tests/lib/harness.sh"; trap fixture_cleanup EXIT; fixture_init

before="$(fixture_managed_snapshot)"
for installer in install-sbx.sh install-tailscale.sh install-azure-cli.sh install-gcloud.sh install-aws-cli.sh; do
    HOME="$HOME" XDG_CONFIG_HOME="$XDG_CONFIG_HOME" XDG_STATE_HOME="$XDG_STATE_HOME" \
        XDG_CACHE_HOME="$XDG_CACHE_HOME" TMPDIR="$TMPDIR" PATH="$TEST_SYSTEM_PATH" \
        "$ROOT/installers/$installer" --dry-run >/dev/null
done
assert_eq "$(fixture_managed_snapshot)" "$before" "direct installer dry-run mutated XDG/HOME"

printf '#!/bin/sh\n[ "$1" = version ]\n' > "$TEST_ROOT/bin/sbx"
printf '#!/bin/sh\nexit 0\n' > "$TEST_ROOT/bin/tailscale"
printf '#!/bin/sh\nexit 0\n' > "$TEST_ROOT/bin/tailscaled"
printf '#!/bin/sh\nexit 0\n' > "$TEST_ROOT/bin/dpkg-query"
printf '#!/bin/sh\nexit 0\n' > "$TEST_ROOT/bin/systemctl"
chmod +x "$TEST_ROOT/bin/sbx" "$TEST_ROOT/bin/tailscale" "$TEST_ROOT/bin/tailscaled" \
    "$TEST_ROOT/bin/dpkg-query" "$TEST_ROOT/bin/systemctl"
for installer in install-sbx.sh install-tailscale.sh; do
    rc=0
    PATH="$TEST_ROOT/bin:$TEST_SYSTEM_PATH" DOTFILES_TEST_SYSTEMD_RUNNING=1 \
        "$ROOT/installers/$installer" >/dev/null 2>&1 || rc=$?
    [[ $rc -eq 2 ]] || fail "$installer idempotent check returned $rc instead of 2"
done

source "$ROOT/setup.sh"
sources="$TEST_ROOT/apt/sources.list.d"; keys="$TEST_ROOT/apt/keyrings"
mkdir -p "$sources" "$keys"
printf 'Types: deb\nURIs: https://download.docker.com/linux/ubuntu\nSuites: noble\nComponents: stable\n' > "$sources/docker.sources"
DOTFILES_APT_SOURCES_DIR="$sources" DOTFILES_APT_KEYRINGS_DIR="$keys"
export DOTFILES_APT_SOURCES_DIR DOTFILES_APT_KEYRINGS_DIR
sudo_calls=""
safe_sudo() { sudo_calls+=" $*"; }
ensure_docker_repo >/dev/null
[[ -z "$sudo_calls" ]] || fail "compatible Docker repository was duplicated or modified"
if declare -f ensure_docker_repo | grep -Eq 'apt-get remove|docker\.io.*remove'; then
    fail "Docker repository preparation still removes container packages"
fi
if grep -REn '^[[:space:]]*(safe_sudo[[:space:]]+)?tailscale[[:space:]]+(up|login)|sbx[[:space:]]+diagnose[[:space:]]+--upload' \
    "$ROOT/installers" "$ROOT/lib/work-host.sh"; then
    fail "work/tail automation performs enrollment or diagnostic upload"
fi
if grep -REn 'cp .*(\.claude|\.codex|\.config/opencode|\.pi)' "$ROOT/installers" "$ROOT/lib"; then
    fail "work/tail automation copies host AI credential/configuration state"
fi

# Docker conflict discovery must not depend on host state or execute package
# probes during a dry-run. A developer machine with Docker installed used to
# hide this path while clean CI containers exposed it.
package_probe_log="$TEST_ROOT/package-probes.log"
dpkg-query() { printf 'dpkg-query\t%s\n' "$*" >> "$package_probe_log"; return 1; }
dpkg() { printf 'dpkg\t%s\n' "$*" >> "$package_probe_log"; return 1; }
DRY_RUN=true
install_docker_engine >/dev/null
[[ ! -s "$package_probe_log" ]] || fail "Docker dry-run executed package probes"
DRY_RUN=false

grep -Fq 'gpgv --keyring' "$ROOT/installers/install-aws-cli.sh" \
    || fail "AWS CLI installer does not verify the detached signature"
grep -Fq 'FB5DB77FD5C118B80511ADA8A6310ACC4672475C' "$ROOT/installers/install-aws-cli.sh" \
    || fail "AWS CLI signer fingerprint is not pinned"

dpkg-query() { return 1; }
dpkg() { [[ "$2" == containerd ]]; }
command() { [[ "$1" == -v && "$2" == docker ]] && return 1; builtin command "$@"; }
INSTALL_FAIL=()
if install_docker_engine >/dev/null 2>&1; then fail "Docker conflict migration silently succeeded"; fi
[[ " ${INSTALL_FAIL[*]} " == *" docker "* ]] || fail "Docker conflict not tracked as failure"

# sbx is pinned: another installed version is reported, never silently moved.
printf '#!/bin/sh\n[ "$1" = version ] && echo "sbx version: v0.1.0 abc"\n' > "$TEST_ROOT/bin/sbx"
rc=0
out="$(PATH="$TEST_ROOT/bin:$TEST_SYSTEM_PATH" "$ROOT/installers/install-sbx.sh" 2>&1)" || rc=$?
[[ $rc -eq 2 ]] || fail "install-sbx.sh with another version returned $rc instead of 2"
[[ "$out" == *"pins $SBX_VERSION"* ]] || fail "install-sbx.sh did not report the pin: $out"
grep -Fq 'apt-mark hold' "$ROOT/installers/install-sbx.sh" || fail "install-sbx.sh does not hold the pin"

# The sbx kit builder: created once with the documented arguments, never
# replaced, and nothing is run on a dry run.
unset -f command dpkg-query dpkg
docker_log="$TEST_ROOT/docker.log"; : > "$docker_log"
builder_exists=false
docker() {
    printf '%s\n' "$*" >> "$docker_log"
    case "$1 ${2:-}" in
        "info "*) return 0 ;;
        "buildx inspect") [[ "$builder_exists" == true ]] ;;
        *) return 0 ;;
    esac
}
SBX_KITS_BUILDKITD_CONFIG="$TEST_ROOT/buildkitd.toml"; : > "$SBX_KITS_BUILDKITD_CONFIG"
DRY_RUN=true ensure_sbx_kits_builder >/dev/null
[[ ! -s "$docker_log" ]] || fail "builder dry-run ran docker"
DRY_RUN=false ensure_sbx_kits_builder >/dev/null 2>&1
grep -Fxq "buildx create --name $SBX_KITS_BUILDER --driver docker-container --driver-opt network=host --buildkitd-config $SBX_KITS_BUILDKITD_CONFIG" "$docker_log" \
    || fail "builder not created as documented: $(cat "$docker_log")"
: > "$docker_log"; builder_exists=true
DRY_RUN=false ensure_sbx_kits_builder >/dev/null 2>&1
! grep -q 'buildx create' "$docker_log" || fail "an existing builder was recreated"
unset -f docker

printf 'work-installers: ok\n'
