#!/usr/bin/env bash
# Copy plugins/shared/ into each per-harness plugin directory.
#
# Claude and Codex each auto-load hooks from the fixed path <plugin>/hooks/hooks.json
# and neither offers a way to name a different file -- Codex rejects the `hooks`
# manifest field outright, and putting a Codex-only event in a file Claude reads
# makes Claude discard the whole file. So the two harnesses cannot share a plugin,
# and the event vocabularies live in separate hooks/hooks.json files.
#
# Everything *else* is identical, and duplicating a 350-line state machine by hand
# is how it silently diverges. So plugins/shared/ is the single source of truth and
# the copies are generated. shared/ deliberately mirrors the plugin layout
# (scripts/ + agent-badge.tmux at the root) so every relative path inside those
# files resolves the same whether it is running from shared/ or from a plugin.
#
# Symlinks would be the obvious alternative and do not work: Codex silently omits
# symlinked directories when it copies a plugin into its cache, so the scripts
# simply would not be there. Claude dereferences them correctly. Verified both.
#
# Usage: sync-shared.sh            copy shared/ into every plugin
#        sync-shared.sh --check    exit 1 if any copy is stale (pre-commit)

set -euo pipefail

SELF_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
SHARED="$SELF_DIR/shared"
PLUGINS=(agent-badge-claude agent-badge-codex)
# Paths under shared/ that get mirrored, relative to shared/.
ITEMS=(scripts agent-badge.tmux README.md)

CHECK=false
[[ "${1:-}" == "--check" ]] && CHECK=true

[[ -d "$SHARED" ]] || { echo "missing $SHARED" >&2; exit 1; }

stale=()
for p in "${PLUGINS[@]}"; do
    dest="$SELF_DIR/$p"
    [[ -d "$dest" ]] || { echo "missing plugin dir: $dest" >&2; exit 1; }
    for item in "${ITEMS[@]}"; do
        src="$SHARED/$item"
        [[ -e "$src" ]] || continue
        if [[ "$CHECK" == true ]]; then
            diff -rq "$src" "$dest/$item" >/dev/null 2>&1 || stale+=("$p/$item")
        else
            rm -rf "${dest:?}/$item"
            cp -R "$src" "$dest/$item"
        fi
    done
done

if [[ "$CHECK" == true ]]; then
    if (( ${#stale[@]} )); then
        echo "agent-badge: generated copies are stale:" >&2
        printf '    plugins/%s\n' "${stale[@]}" >&2
        echo "  Run: plugins/sync-shared.sh   (edit plugins/shared/, never the copies)" >&2
        exit 1
    fi
    exit 0
fi

echo "Synced plugins/shared/ -> ${PLUGINS[*]}"
