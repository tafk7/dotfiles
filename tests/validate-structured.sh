#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

python3 - <<'PY'
import json
import pathlib
import re
try:
    import tomllib
except ModuleNotFoundError:
    import tomli as tomllib
try:
    import yaml
except ModuleNotFoundError as exc:
    raise SystemExit("PyYAML is required for structured-file validation") from exc

root = pathlib.Path('.')
for path in root.rglob('*.json'):
    if '.git' not in path.parts:
        json.loads(path.read_text())
for path in root.rglob('*.jsonc'):
    text = re.sub(r'/\*.*?\*/', '', path.read_text(), flags=re.S)
    text = re.sub(r'(^|\s)//.*$', r'\1', text, flags=re.M)
    text = re.sub(r',\s*([}\]])', r'\1', text)
    json.loads(text)
for path in root.rglob('*.toml'):
    if '.git' not in path.parts:
        tomllib.loads(path.read_text())
for path in list(root.rglob('*.yml')) + list(root.rglob('*.yaml')):
    if '.git' not in path.parts:
        yaml.safe_load(path.read_text())
PY

export DOTFILES_DIR="$ROOT"
source lib/runtime.sh
source lib/config.sh
for key in "${!CONFIG_MAP[@]}"; do
    IFS=: read -r _ _ owner <<< "${CONFIG_MAP[$key]}"
    [[ -z "$owner" || -n "${TOOL_BINARY[$owner]:-}" ]] \
        || { echo "CONFIG_MAP[$key] has unknown owner: $owner" >&2; exit 1; }
done

required=(meta.sh palette.sh vim.vim tmux.conf shell.sh colors.sh starship.palette.toml delta.gitconfig btop.theme lazygit.yml)
for dir in themes/*; do
    [[ -d "$dir" ]] || continue
    theme="${dir##*/}"
    for file in "${required[@]}"; do
        [[ -f "$dir/$file" ]] || { echo "$theme missing $file" >&2; exit 1; }
    done
    grep -Fq "[palettes.$theme]" "$dir/starship.palette.toml" \
        || { echo "$theme Starship palette name mismatch" >&2; exit 1; }
done

plugins/sync-shared.sh --check
if grep -Fq 'plugins/shared/agent-badge.tmux' configs/tmux.conf; then
    echo "base tmux config directly wires optional agent-badge" >&2
    exit 1
fi
if grep -R -nE '\$HOME/dotfiles|~/dotfiles' \
    bin configs entry installers lib plugins shell setup.sh bootstrap.sh; then
    echo "functional source contains a hard-coded legacy checkout path" >&2
    exit 1
fi

# Verify the tracked unit itself. On machines where the optional bridge is not
# installed, systemd-analyze reports its %h-based ExecStart/ExecStop target as
# missing and exits non-zero even though the unit syntax is valid. Ignore only
# that exact environmental diagnostic; any other verifier output still fails.
unit_verify_output=""
unit_verify_rc=0
unit_verify_output="$(systemd-analyze verify configs/wsl2-ssh-agent.service 2>&1)" \
    || unit_verify_rc=$?
if (( unit_verify_rc != 0 )); then
    unexpected_unit_output="$(
        printf '%s\n' "$unit_verify_output" \
            | grep -Ev '^wsl2-ssh-agent\.service: Command .*/\.local/bin/wsl2-ssh-agent is not executable: No such file or directory$' \
            || true
    )"
    if [[ -n "$unexpected_unit_output" ]]; then
        printf '%s\n' "$unit_verify_output" >&2
        exit "$unit_verify_rc"
    fi
fi
for manifest in .claude-plugin/marketplace.json .agents/plugins/marketplace.json \
    plugins/agent-badge-claude/.claude-plugin/plugin.json \
    plugins/agent-badge-codex/.codex-plugin/plugin.json; do
    python3 -m json.tool "$manifest" >/dev/null
done

while IFS= read -r file; do
    [[ ! -x "$file" ]] || { echo "configuration file is executable: $file" >&2; exit 1; }
done < <(find configs -type f)

for command in setup.sh bin/theme-switcher bin/check-updates bin/diff-config \
    bin/uninstall-tool bin/ssh-bridge bin/opencode-contract bin/dotfiles-feature; do
    "$ROOT/$command" --help >/dev/null
done

printf 'validate-structured: ok\n'
