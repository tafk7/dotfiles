#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/tests/lib/harness.sh"
trap fixture_cleanup EXIT
fixture_init

cat > "$TEST_ROOT/bin/codex" <<'EOF'
#!/bin/sh
printf '<%s>' "$@"
EOF
chmod +x "$TEST_ROOT/bin/codex"
export PATH="$TEST_ROOT/bin:$TEST_SYSTEM_PATH"

for test_shell in bash zsh; do
    "$test_shell" -c 'source "$DOTFILES_DIR/shell/local.sh"' || fail "$test_shell empty local config"
done
mkdir -p "$HOME/.shell.local.d"
printf 'LOCAL_ORDER=base\ntypeset LOCAL_DECLARED=present\n' > "$HOME/.shell.local"
printf 'LOCAL_ORDER="${LOCAL_ORDER}:first"\n' > "$HOME/.shell.local.d/10-first.sh"
printf 'LOCAL_ORDER="${LOCAL_ORDER}:last"\n' > "$HOME/.shell.local.d/90-last.sh"
ln -s missing "$HOME/.shell.local.d/50-missing.sh"
for test_shell in bash zsh; do
    "$test_shell" -c '
        source "$DOTFILES_DIR/shell/local.sh"
        [[ "$LOCAL_DECLARED" == present ]] || exit 10
        [[ "$LOCAL_ORDER" == base:first:last ]] || exit 1
        source "$DOTFILES_DIR/shell/local.sh"
        [[ "$LOCAL_ORDER" == base:first:last ]] || exit 2
        source "$DOTFILES_DIR/shell/tools/codex.sh"
        CODEX_DEFAULT_PROFILE=work
        CODEX_FLAGS="--no-alt-screen"
        [[ "$(codex exec "two words")" == "<--no-alt-screen><--profile><work><exec><two words>" ]] || exit 3
        for defaults in "--profile old" "--profile=old" "-p old" "-pold"; do
            CODEX_FLAGS="--no-alt-screen $defaults"
            for explicit in "--profile=new" "-pnew"; do
                [[ "$(codex "$explicit" prompt)" == "<--no-alt-screen><$explicit><prompt>" ]] || exit 4
            done
            [[ "$(codex -p new prompt)" == "<--no-alt-screen><-p><new><prompt>" ]] || exit 5
            [[ "$(codex exec --profile new prompt)" == "<--no-alt-screen><exec><--profile><new><prompt>" ]] || exit 6
        done
        CODEX_FLAGS="--profile old"
        [[ "$(codex -- -p)" == "<--profile><old><--><-p>" ]] || exit 7
        [[ "$(command codex prompt)" == "<prompt>" ]] || exit 8
        CODEX_FLAGS=""
        [[ "$(codex -p new)" == "<-p><new>" ]] || exit 9
        unset CODEX_FLAGS
        set -u
        [[ "$(codex prompt)" == "<--profile><work><prompt>" ]] || exit 11
    ' || fail "$test_shell local config and profile precedence (exit $?)"
done
mkdir -p "$HOME/.ssh/config.d"
sed "s|~/.ssh|$HOME/.ssh|g" "$ROOT/configs/ssh_config" > "$HOME/.ssh/config"
printf 'Host fixture\n  User local-user\n' > "$HOME/.ssh/config.local"
printf 'Host fixture\n  User named-user\n  HostName example.invalid\n' > "$HOME/.ssh/config.d/40-fixture.conf"
ssh_config=$(ssh -G -T -F "$HOME/.ssh/config" fixture)
[[ "$ssh_config" == *'user local-user'* && "$ssh_config" == *'hostname example.invalid'* ]] \
    || fail 'SSH local overrides and named configuration precedence'
printf 'local-config: ok\n'
