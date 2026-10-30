#!/bin/bash
# The Python for tools that need 3.11 or newer (lib/python.sh): the system's
# when it is new enough, else uv's, cached, with DOTFILES_PYTHON over both, and
# a plain message when there is none. bin/keymap runs through it.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_REPO_ROOT="$ROOT"
source "$ROOT/tests/lib/harness.sh"
trap fixture_cleanup EXIT
fixture_init

real="$(command -v python3)"
"$real" -c 'import sys; sys.exit(sys.version_info < (3, 11))' || { echo "python-select: skipped (needs a host Python 3.11+)"; exit 0; }

# pick [PATH]: run dotfiles_python in a fresh shell with PATH.
pick() {
    PATH="${1:-$PATH}" "$BASH" -c 'source "$1/lib/python.sh"; dotfiles_python' _ "$ROOT"
}
cache="$XDG_CACHE_HOME/dotfiles/python"

# A new enough system Python is chosen and cached; the cache is used after.
assert_eq "$(pick)" "$real" "a new enough system Python"
assert_eq "$(<"$cache")" "$real" "the cached choice"
assert_eq "$(pick /nonexistent)" "$real" "a cached choice, without PATH"
assert_eq "$(DOTFILES_PYTHON=/opt/py pick)" /opt/py "DOTFILES_PYTHON"

# An older system Python: uv's, asked without the current project's pin.
rm -f "$cache"
mkdir -p "$TEST_ROOT/old"
printf '#!/bin/sh\n[ "$1" = --version ] && { echo "Python 3.10.12"; exit 0; }\nexit 1\n' > "$TEST_ROOT/old/python3"
cat > "$TEST_ROOT/old/uv" <<EOF
#!/bin/sh
echo "\$*" >> "$TEST_ROOT/uv.log"
[ "\$1 \$2 \$3" = "python find --no-project" ] && echo "$real"
EOF
chmod +x "$TEST_ROOT/old/python3" "$TEST_ROOT/old/uv"
assert_eq "$(pick "$TEST_ROOT/old:$TEST_SYSTEM_PATH")" "$real" "uv's Python under an older system's"
assert_eq "$(<"$TEST_ROOT/uv.log")" "python find --no-project >=3.11" "the uv request"

# Neither: a message, and nothing cached. A stale cache is found afresh.
rm -f "$cache" "$TEST_ROOT/old/uv"
if out="$(pick "$TEST_ROOT/old:$TEST_SYSTEM_PATH" 2>&1)"; then fail "no Python succeeded: $out"; fi
[[ "$out" == "Python 3.11 or newer is needed. The system has Python 3.10.12; install one with: uv python install 3.12" ]] \
    || fail "no Python: $out"
[[ ! -e "$cache" ]] || fail "a failed choice was cached"
mkdir -p "${cache%/*}" && echo /gone/python3 > "$cache"
assert_eq "$(pick)" "$real" "a stale cache"

# bin/keymap starts through it, from anywhere.
(cd "$TEST_ROOT" && "$ROOT/bin/keymap" --help) | grep -q '^usage: keymap' || fail "keymap --help through the launcher"

printf 'python-select: ok\n'
