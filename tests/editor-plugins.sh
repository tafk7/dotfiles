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
"$ROOT/bin/install-editor-plugins" >/dev/null
[[ -f "$XDG_CONFIG_HOME/nvim/autoload/plug.vim" && -f "$TEST_ROOT/plugins-ran" ]] || fail "explicit editor bootstrap incomplete"
[[ ! -e "$HOME/.config/nvim" ]] || fail "editor bootstrap ignored XDG"
printf 'editor-plugins: ok\n'
