#!/bin/bash
# tmux refresh: one targeted server's global environment gets the managed
# values and loses the guards and last time's PATH segments, keeping other
# entries; a session override is reported, not changed; a server older than
# the installed tmux is a health finding; no server, nothing to do.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_REPO_ROOT="$ROOT"
TMUX_BIN="$(command -v tmux)" || { echo 'tmux required for tmux-refresh tests' >&2; exit 1; }
source "$ROOT/tests/lib/harness.sh"
fixture_init
export DOTFILES_TMUX_SERVER="refresh-$$"
trap 'command tmux -L "$DOTFILES_TMUX_SERVER" kill-server 2>/dev/null || true; fixture_cleanup' EXIT
# tmux -V reports a newer client than the server whenever TMUX_CLIENT_VERSION
# says so.
cat > "$TEST_ROOT/bin/tmux" <<EOF
#!/bin/sh
if [ "\$1" = -V ] && [ -n "\${TMUX_CLIENT_VERSION:-}" ]; then echo "tmux \$TMUX_CLIENT_VERSION"; exit 0; fi
exec "$TMUX_BIN" "\$@"
EOF
chmod +x "$TEST_ROOT/bin/tmux"
export PATH="$TEST_ROOT/bin:$TEST_SYSTEM_PATH"
source "$ROOT/lib/install.sh"
source "$ROOT/lib/outcomes.sh"
source "$ROOT/lib/environment.sh"
source "$ROOT/lib/refresh.sh"
THEME_REQUEST=disabled AGENT_BADGE_REQUEST=disabled
mkdir -p "$XDG_STATE_HOME/dotfiles" "$HOME/go/bin"
printf '%s\n' "$ROOT" > "$XDG_STATE_HOME/dotfiles/install-path"
srv() { command tmux -L "$DOTFILES_TMUX_SERVER" "$@"; }
genv() { srv show-environment -g "$1" 2>/dev/null; }
records() { refresh_tmux 2>/dev/null; }

# No server: nothing to do.
assert_eq "$(records | cut -f1,4)" "ok	no tmux server is running" "no server"

# A server started with stale values, a guard, an old dotfiles segment, a
# user's own PATH entry, and a session that overrides a managed variable.
srv -f /dev/null new-session -d -s main
srv set-environment -g EDITOR stale-editor
srv set-environment -g _DOTFILES_ENV_LOADED 1
srv set-environment -g PATH "$HOME/old-dotfiles/bin:/opt/mine/bin:/usr/bin:/bin"
printf '%s\n' "$HOME/old-dotfiles/bin" > "$ENV_SEGMENTS_FILE"
srv set-environment -t main PROJECTS_DIRS /session/choice
srv set-environment -g GOPATH /stale/go
rm -rf "$HOME/go"

out="$(records)"
[[ "$(genv EDITOR)" != "EDITOR=stale-editor" && "$(genv PAGER)" == "PAGER=less" ]] || fail "managed values not refreshed: $(srv show-environment -g)"
assert_eq "$(genv DOTFILES_DIR)" "DOTFILES_DIR=$ROOT" "DOTFILES_DIR from the install path"
[[ "$(genv _DOTFILES_ENV_LOADED)" == "-_DOTFILES_ENV_LOADED" || -z "$(genv _DOTFILES_ENV_LOADED)" ]] || fail "a guard survived: $(genv _DOTFILES_ENV_LOADED)"
[[ "$(genv GOPATH)" == -GOPATH || -z "$(genv GOPATH)" ]] || fail "an owned variable that no longer applies stayed: $(genv GOPATH)"
path="$(genv PATH)"; path="${path#PATH=}"
[[ ":$path:" != *":$HOME/old-dotfiles/bin:"* ]] || fail "last time's segment stayed: $path"
[[ ":$path:" == *":/opt/mine/bin:"* && ":$path:" == *":$ROOT/bin:"* ]] || fail "PATH after refresh: $path"
[[ "$path" == *"/opt/mine/bin:/usr/bin:/bin" ]] || fail "the user's entries moved: $path"
[[ "$(<"$ENV_SEGMENTS_FILE")" == *"$ROOT/bin"* ]] || fail "the published segments were not recorded"
assert_eq "$(srv show-environment -t main PROJECTS_DIRS)" "PROJECTS_DIRS=/session/choice" "a session override was changed"
[[ "$out" == *$'advisory\ttmux\tsession main\toverrides PROJECTS_DIRS'* ]] || fail "the session override was not reported: $out"
[[ "$out" != *$'\tserver\t'* ]] || fail "matching versions were reported: $out"

# A server older than the installed client.
out="$(TMUX_CLIENT_VERSION=99.9 refresh_tmux 2>/dev/null)"
[[ "$out" == *$'health\ttmux\tserver\truns tmux '*'; the installed tmux is 99.9'* ]] || fail "version mismatch: $out"

# A second refresh changes nothing further.
before="$(srv show-environment -g | sort)"
records >/dev/null
assert_eq "$(srv show-environment -g | sort)" "$before" "a second refresh"

printf 'tmux-refresh: ok\n'
