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
grep -Fq 'gpgv --keyring' "$ROOT/installers/install-aws-cli.sh" \
    || fail "AWS CLI installer does not verify the detached signature"
grep -Fq 'FB5DB77FD5C118B80511ADA8A6310ACC4672475C' "$ROOT/installers/install-aws-cli.sh" \
    || fail "AWS CLI signer fingerprint is not pinned"

dpkg_query_saved="$(declare -f dpkg-query 2>/dev/null || true)"
dpkg-query() { return 1; }
dpkg() { [[ "$2" == containerd ]]; }
command() { [[ "$1" == -v && "$2" == docker ]] && return 1; builtin command "$@"; }
INSTALL_FAIL=()
if install_docker_engine >/dev/null 2>&1; then fail "Docker conflict migration silently succeeded"; fi
[[ " ${INSTALL_FAIL[*]} " == *" docker "* ]] || fail "Docker conflict not tracked as failure"

printf 'work-installers: ok\n'
