#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NVIM_BIN="$(command -v nvim)" || { echo 'neovim required for editor-plugin tests' >&2; exit 1; }
source "$ROOT/tests/lib/harness.sh"
fixture_init
trap fixture_cleanup EXIT
export TEST_ROOT
export PATH="$TEST_ROOT/bin:$TEST_SYSTEM_PATH"
ln -s "$NVIM_BIN" "$TEST_ROOT/bin/nvim"
cat > "$TEST_ROOT/plug.vim" <<'EOF'
function! plug#begin(...) abort
  let g:plugs = {}
  command! -nargs=+ Plug echo ''
  command! -nargs=* PlugInstall call writefile(['installed'], $TEST_ROOT . '/plugins-ran')
endfunction
function! plug#end(...) abort
endfunction
EOF
cat > "$TEST_ROOT/bin/curl" <<'EOF'
#!/bin/bash
while (( $# )); do
    if [[ "$1" == --output ]]; then dest="$2"; shift; fi
    shift
done
cp "$TEST_ROOT/plug.vim" "$dest"
EOF
chmod +x "$TEST_ROOT/bin/curl"
# A download that is not the locked plug.vim is refused.
if "$ROOT/bin/install-editor-plugins" >/dev/null 2>&1; then fail "an unlocked plug.vim was installed"; fi
[[ ! -e "$XDG_CONFIG_HOME/nvim/autoload/plug.vim" ]] || fail "an unlocked plug.vim was left in place"
awk -F '\t' -v OFS='\t' -v d="$(sha256sum "$TEST_ROOT/plug.vim" | awk '{print $1}')" '$1 == "vim-plug" { $6 = d } 1' \
    "$ROOT/versions.lock" > "$TEST_ROOT/versions.lock"
export DOTFILES_VERSIONS_LOCK="$TEST_ROOT/versions.lock"
"$ROOT/bin/install-editor-plugins" >/dev/null
[[ -f "$XDG_CONFIG_HOME/nvim/autoload/plug.vim" && -f "$TEST_ROOT/plugins-ran" ]] || fail "explicit editor bootstrap incomplete"
[[ ! -e "$HOME/.config/nvim" ]] || fail "editor bootstrap ignored XDG"

# Plugins move to their pinned commits; a checkout with local changes stays.
export GIT_AUTHOR_NAME=Fixture GIT_AUTHOR_EMAIL=fixture@example.com GIT_COMMITTER_NAME=Fixture GIT_COMMITTER_EMAIL=fixture@example.com
remote="$TEST_ROOT/remote/demo"
git init -q "$remote"
git -C "$remote" commit -q --allow-empty -m first
first="$(git -C "$remote" rev-parse HEAD)"
git -C "$remote" commit -q --allow-empty -m second
second="$(git -C "$remote" rev-parse HEAD)"
plugin="$XDG_DATA_HOME/nvim/plugged/demo"
git clone -q "$remote" "$plugin"
git -C "$plugin" checkout -q --detach "$first"
printf "Plug 'example/demo', { 'commit': '%s' }\n" "$second" > "$TEST_ROOT/init.vim"
export DOTFILES_EDITOR_INIT="$TEST_ROOT/init.vim"
plugins() { local rc=0; PLUGINS_OUTPUT="$("$ROOT/bin/install-editor-plugins" "$@" 2>&1)" || rc=$?; PLUGINS_RC=$rc; }

plugins --check
[[ "$PLUGINS_RC" == 1 && "$PLUGINS_OUTPUT" == *"Would move demo from ${first:0:7} to ${second:0:12}"* ]] \
    || fail "--check did not report the moved commit ($PLUGINS_RC): $PLUGINS_OUTPUT"
assert_eq "$(git -C "$plugin" rev-parse HEAD)" "$first" "--check moved the plugin"
plugins
assert_eq "$PLUGINS_RC/$(git -C "$plugin" rev-parse HEAD)" "0/$second" "a plugin off its pin: $PLUGINS_OUTPUT"
plugins
assert_eq "$PLUGINS_RC" 2 "plugins at their pins"
plugins --check
assert_eq "$PLUGINS_RC" 0 "--check at the pins"
# A check writes no state, Neovim's log included, into a state dir it has
# never seen.
mkdir -p "$TEST_ROOT/state-check"
XDG_STATE_HOME="$TEST_ROOT/state-check" "$ROOT/bin/install-editor-plugins" --check >/dev/null 2>&1 || true
assert_eq "$(cd "$TEST_ROOT/state-check" && find . -mindepth 1 | sort | paste -sd' ')" "" "--check wrote state"

git -C "$plugin" checkout -q --detach "$first"
printf 'local\n' > "$plugin/LOCAL"
plugins
[[ "$PLUGINS_RC" == 2 && "$(git -C "$plugin" rev-parse HEAD)" == "$first" && "$PLUGINS_OUTPUT" == *"local changes, so it stays at"* ]] \
    || fail "a checkout with local changes was moved or not reported: $PLUGINS_OUTPUT"
rm "$plugin/LOCAL"

# vim-plug moves with its pin when dotfiles installed it, and not otherwise.
printf '" changed\n' >> "$XDG_CONFIG_HOME/nvim/autoload/plug.vim"
plugins --check
[[ "$PLUGINS_OUTPUT" == *"Would install vim-plug"* ]] || fail "an owned vim-plug off its pin was not planned: $PLUGINS_OUTPUT"
printf 'schema\t1\n' > "$XDG_STATE_HOME/dotfiles/components.tsv"
plugins --check
[[ "$PLUGINS_OUTPUT" != *"Would install vim-plug"* && "$PLUGINS_OUTPUT" == *"did not install it, so it is left alone"* ]] \
    || fail "a foreign vim-plug was planned for replacement: $PLUGINS_OUTPUT"

printf 'editor-plugins: ok\n'
