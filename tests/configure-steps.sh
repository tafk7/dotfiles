#!/bin/bash
# Configure steps run after a component's install step whether or not it
# changed anything: a current, external Claude still gets its settings and its
# agent-badge plugin registered and brought up to date. A failed install step
# gets none, a dry run writes nothing, and a masked tailscaled is left alone.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_REPO_ROOT="$ROOT"
source "$ROOT/tests/lib/harness.sh"
trap fixture_cleanup EXIT
fixture_init
unset TMUX TMUX_PANE
export NO_COLOR=1 DOTFILES_TEST_PLATFORM=ubuntu DOTFILES_TEST_ARCH=x86_64 DOTFILES_TEST_OS_VERSION=24.04
source "$ROOT/setup.sh"

# An external Claude: on PATH, outside ~/.local/bin, recording plugin commands.
mkdir -p "$TEST_ROOT/external"
cat > "$TEST_ROOT/external/claude" <<EOF
#!/bin/sh
case "\$1" in
    --version) echo "2.1.300 (Claude Code)" ;;
    plugin) echo "\$*" >> "$TEST_ROOT/plugin.log" ;;
esac
EOF
chmod +x "$TEST_ROOT/external/claude"
export PATH="$TEST_ROOT/external:$TEST_SYSTEM_PATH"
# Its badge plugin is enabled but installed at an older version.
mkdir -p "$HOME/.claude/plugins"
printf '{"enabledPlugins": {"agent-badge@tafk7": true}}\n' > "$HOME/.claude/settings.json"
printf '{"plugins": {"agent-badge@tafk7": [{"scope": "user", "version": "0.0.1", "installPath": "%s"}]}}\n' \
    "$HOME/.claude/plugins/cache/tafk7/agent-badge/0.0.1" > "$HOME/.claude/plugins/installed_plugins.json"

select_run() { SELECTED_CAPABILITIES=() SELECTED_AI_TOOLS=(); INSTALL_TIER=config; parse_arguments "$@"; }
AGENT_BADGE_REQUEST=enabled
install_eget_tools() { :; }

# The installer finds the external Claude and skips (run_installer succeeds);
# configuration still runs.
run_installer() { return 0; }
select_run --claude
install_selection > "$TEST_ROOT/out" 2>&1 || fail "configuring an external Claude failed: $(<"$TEST_ROOT/out")"
python3 -c 'import json, sys; d = json.load(open(sys.argv[1])); assert d["enabledPlugins"]["agent-badge@tafk7"] and "env" in d' \
    "$HOME/.claude/settings.json" || fail "the external Claude did not get its portable settings"
grep -Fxq "plugin marketplace add $ROOT" "$TEST_ROOT/plugin.log" && grep -Fxq "plugin install agent-badge@tafk7" "$TEST_ROOT/plugin.log" \
    || fail "the badge was not registered with the external Claude: $(<"$TEST_ROOT/plugin.log")"
grep -Fxq "plugin update agent-badge@tafk7" "$TEST_ROOT/plugin.log" \
    || fail "the stale badge plugin was not updated: $(<"$TEST_ROOT/plugin.log")"
# Running sessions keep the plugin they loaded: the update is a change event.
[[ "$(change_line claude | cut -f3)" == "agent-badge plugin updated" ]] || fail "no change event for the badge: $(change_line claude)"

# A failed install step gets no configuration.
rm -f "$TEST_ROOT/plugin.log" "$HOME/.claude/settings.json"
run_installer() { return 1; }
select_run --claude
if install_selection >/dev/null 2>&1; then fail "a failed install step reported success"; fi
[[ ! -e "$HOME/.claude/settings.json" && ! -e "$TEST_ROOT/plugin.log" ]] || fail "a failed install step was configured"

# A dry run describes the steps and writes nothing.
run_installer() { return 0; }
before="$(fixture_managed_snapshot)"
select_run --claude --pi --dry-run
output="$(install_selection 2>&1)" || fail "dry run failed: $output"
[[ "$output" == *"Would reconcile claude's portable settings"* && "$output" == *"Would register the agent-badge plugin with claude"* \
   && "$output" == *"Would provision $HOME/.pi/agent/settings.json"* ]] || fail "dry run did not describe the configure steps: $output"
assert_eq "$(fixture_managed_snapshot)" "$before" "dry run changed HOME"
[[ ! -e "$TEST_ROOT/plugin.log" ]] || fail "dry run ran plugin commands"
DRY_RUN=false

# Pi's settings are seeded once and then left to their owner.
configure_pi_settings pi >/dev/null
cmp -s "$ROOT/configs/pi-settings.json" "$HOME/.pi/agent/settings.json" || fail "Pi settings were not seeded"
printf '{"mine": true}\n' > "$HOME/.pi/agent/settings.json"
configure_pi_settings pi >/dev/null
assert_eq "$(<"$HOME/.pi/agent/settings.json")" '{"mine": true}' "existing Pi settings"

# Neovim's plugins come with Neovim: its configure step plans vim-plug and
# the plugins init.vim declares, without a linter plugin.
printf '#!/bin/sh\nprintf "%%s\\n%%s\\n" "$HOME/.config/nvim" "$HOME/.local/share/nvim"\n' > "$TEST_ROOT/external/nvim"
chmod +x "$TEST_ROOT/external/nvim"
select_run --dev --only neovim --dry-run
output="$(install_selection 2>&1)" || fail "Neovim's dry run failed: $output"
[[ "$output" == *"Would install vim-plug"* && "$output" == *"Would install plugins: vim-fugitive"* \
   && "$output" != *"plugins:"*" ale"* ]] || fail "Neovim's step did not plan the plugins: $output"
DRY_RUN=false ONLY_COMPONENTS=""
rm "$TEST_ROOT/external/nvim"

# A masked tailscaled is the operator's decision.
printf '#!/bin/sh\necho tailscale\n' > "$TEST_ROOT/external/tailscale"
printf '#!/bin/sh\n[ "$1" = is-enabled ] && { echo masked; exit 1; }\nexit 3\n' > "$TEST_ROOT/external/systemctl"
printf '#!/bin/sh\necho "$*" >> "%s/sudo.log"\n' "$TEST_ROOT" > "$TEST_ROOT/external/sudo"
chmod +x "$TEST_ROOT/external/"{tailscale,systemctl,sudo}
DOTFILES_TEST_SYSTEMD_RUNNING=1 configure_tailscaled tailscale >/dev/null || fail "a masked tailscaled failed configuration"
[[ ! -e "$TEST_ROOT/sudo.log" ]] || fail "a masked tailscaled was enabled: $(<"$TEST_ROOT/sudo.log")"
printf '#!/bin/sh\nexit 1\n' > "$TEST_ROOT/external/systemctl"
DOTFILES_TEST_SYSTEMD_RUNNING=1 configure_tailscaled tailscale >/dev/null
grep -Fxq "systemctl enable --now tailscaled" "$TEST_ROOT/sudo.log" || fail "an inactive tailscaled was not enabled"

# uv's Python: installed only where the system's is older than 3.11, without
# links on PATH, and not in a dry run.
mkdir -p "$TEST_ROOT/pyold"
printf '#!/bin/sh\n[ "$1" = --version ] && { echo "Python 3.10.12"; exit 0; }\nexit 1\n' > "$TEST_ROOT/pyold/python3"
cat > "$TEST_ROOT/pyold/uv" <<EOF
#!/bin/sh
echo "\$*" >> "$TEST_ROOT/uv.log"
[ "\$1 \$2" = "python find" ] && [ -e "$TEST_ROOT/uv-has-python" ] && echo /bin/sh
exit 0
EOF
chmod +x "$TEST_ROOT/pyold/python3" "$TEST_ROOT/pyold/uv"
PATH="$TEST_ROOT/pyold:$PATH" DRY_RUN=true configure_uv_python uv > "$TEST_ROOT/out" 2>&1 || fail "uv Python dry run failed"
grep -q "Would install Python 3.12 with uv" "$TEST_ROOT/out" || fail "the dry run did not plan uv's Python: $(<"$TEST_ROOT/out")"
! grep -q "python install" "$TEST_ROOT/uv.log" || fail "a dry run installed a Python"
PATH="$TEST_ROOT/pyold:$PATH" configure_uv_python uv >/dev/null 2>&1 || fail "installing uv's Python failed"
grep -Fxq "python install --no-bin 3.12" "$TEST_ROOT/uv.log" || fail "uv's Python not installed as planned: $(<"$TEST_ROOT/uv.log")"
: > "$TEST_ROOT/uv.log"; touch "$TEST_ROOT/uv-has-python"
PATH="$TEST_ROOT/pyold:$PATH" configure_uv_python uv >/dev/null 2>&1
! grep -q "python install" "$TEST_ROOT/uv.log" || fail "uv's Python reinstalled although present"
# A new enough system Python: uv isn't asked at all.
if python3 -c 'import sys; sys.exit(sys.version_info < (3, 11))' 2>/dev/null; then
    mkdir -p "$TEST_ROOT/pynew"
    ln -sf "$(command -v python3)" "$TEST_ROOT/pynew/python3"
    ln -sf "$TEST_ROOT/pyold/uv" "$TEST_ROOT/pynew/uv"
    : > "$TEST_ROOT/uv.log"
    PATH="$TEST_ROOT/pynew:$PATH" configure_uv_python uv >/dev/null 2>&1 || fail "uv's Python step failed beside a new system Python"
    [[ ! -s "$TEST_ROOT/uv.log" ]] || fail "uv was asked although the system Python is new enough: $(<"$TEST_ROOT/uv.log")"
fi

printf 'configure-steps: ok\n'
