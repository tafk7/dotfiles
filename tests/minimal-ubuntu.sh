#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_REPO_ROOT="$ROOT"
source "$ROOT/tests/lib/harness.sh"
trap fixture_cleanup EXIT
fixture_init
source "$ROOT/setup.sh"

case " ${PACKAGES[core]} " in
    *' locales '*) ;;
    *) fail "dev package set does not install locales on minimal Ubuntu" ;;
esac

cat > "$TEST_ROOT/bin/locale" <<'EOF'
#!/bin/sh
printf 'C\nC.utf8\nPOSIX\n'
EOF
cat > "$TEST_ROOT/bin/locale-gen" <<'EOF'
#!/bin/sh
printf 'locale-gen %s\n' "$*" >> "$MINIMAL_CALLS"
EOF
cat > "$TEST_ROOT/bin/update-locale" <<'EOF'
#!/bin/sh
printf 'update-locale %s\n' "$*" >> "$MINIMAL_CALLS"
EOF
cat > "$TEST_ROOT/bin/apt-get" <<'EOF'
#!/bin/sh
printf 'apt-get %s\n' "$*" >> "$MINIMAL_CALLS"
EOF
chmod +x "$TEST_ROOT/bin/locale" "$TEST_ROOT/bin/locale-gen" \
    "$TEST_ROOT/bin/update-locale" "$TEST_ROOT/bin/apt-get"

export PATH="$TEST_ROOT/bin:$TEST_SYSTEM_PATH"
export MINIMAL_CALLS="$TEST_ROOT/calls"
: > "$MINIMAL_CALLS"
DRY_RUN=false
safe_sudo() { printf 'sudo %s\n' "$*" >> "$MINIMAL_CALLS"; "$@"; }

configure_locale >/dev/null
grep -Fxq 'locale-gen en_US.UTF-8' "$MINIMAL_CALLS" || fail "locale-gen was not run after package installation"
grep -Fxq 'update-locale LANG=en_US.UTF-8' "$MINIMAL_CALLS" || fail "update-locale was not run"

: > "$MINIMAL_CALLS"
DOTFILES_APT_LOCK_TIMEOUT=37 safe_apt_get update >/dev/null
grep -Fq 'DEBIAN_FRONTEND=noninteractive' "$MINIMAL_CALLS" || fail "APT was not noninteractive"
grep -Fq 'DPkg::Lock::Timeout=37 update' "$MINIMAL_CALLS" || fail "APT lock wait was not bounded/configurable"

grep -Fq 'DPkg::Lock::Timeout=' "$ROOT/bootstrap.sh" || fail "bootstrap does not wait for apt locks"
grep -Fq 'install -y git curl ca-certificates' "$ROOT/bootstrap.sh" || fail "bootstrap does not provision minimal prerequisites"

printf 'minimal-ubuntu: ok\n'
