#!/usr/bin/env bash
# Install (or refresh, or remove) agent-badge's hooks in ~/.codex/config.toml.
#
# Codex cannot load these from the plugin manifest yet -- see hooks.toml -- so
# they have to live in the user's own config. That file is rich and hand-edited,
# so this never rewrites it wholesale: it manages exactly one delimited block and
# leaves everything else byte-for-byte alone.
#
# Idempotent. Re-run after moving or updating the plugin to re-point the paths.
#
# Usage: install.sh [--uninstall] [--config PATH] [--dry-run]

set -euo pipefail

BEGIN='# >>> agent-badge (managed by plugins/agent-badge/codex/install.sh) >>>'
END='# <<< agent-badge (managed by plugins/agent-badge/codex/install.sh) <<<'

SELF_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
TEMPLATE="$SELF_DIR/hooks.toml"
SCRIPT="$(cd -- "$SELF_DIR/.." && pwd)/scripts/agent-status.sh"

CONFIG="${CODEX_HOME:-$HOME/.codex}/config.toml"
UNINSTALL=false
DRY_RUN=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --uninstall) UNINSTALL=true; shift ;;
        --config)    CONFIG="$2"; shift 2 ;;
        --dry-run)   DRY_RUN=true; shift ;;
        -h|--help)   sed -n '2,12p' "${BASH_SOURCE[0]}"; exit 0 ;;
        *) echo "unknown argument: $1" >&2; exit 2 ;;
    esac
done

[[ -f "$TEMPLATE" ]] || { echo "missing template: $TEMPLATE" >&2; exit 1; }
[[ -x "$SCRIPT"   ]] || { echo "missing or non-executable: $SCRIPT" >&2; exit 1; }

mkdir -p "$(dirname "$CONFIG")"
[[ -f "$CONFIG" ]] || : > "$CONFIG"

# ---------------------------------------------------------------------------
# Strip anything we own. Two categories, because installs predating this script
# wrote hooks by hand with no markers:
#
#   1. the managed block, delimited by BEGIN/END
#   2. any [[hooks.*]] table whose body mentions agent-status.sh
#
# A TOML table runs from its own header to the next line starting with '[', so
# that is the unit we drop. Nothing else is touched -- notably [hooks.state],
# whose trusted_hash entries are content-addressed and will simply re-prompt if
# a command changed, which is the behaviour we want anyway.
# ---------------------------------------------------------------------------
drop_managed_block() {
    awk -v b="$BEGIN" -v e="$END" '
        $0 == b { skip = 1; next }
        $0 == e { skip = 0; next }
        !skip
    '
}

drop_hook_tables() {
    awk '
        # A Codex hook is spread across two TOML tables:
        #     [[hooks.Stop]]
        #     [[hooks.Stop.hooks]]
        #     command = "..."
        # Only the second mentions our script, so dropping tables individually
        # deletes the body and leaves an orphaned [[hooks.Stop]] header behind --
        # which parses as a hook entry with no handler. So the unit here is the
        # whole GROUP: a [[hooks.NAME]] header plus every following table whose
        # header is nested under the same NAME.
        #
        # Leading comments belong to the table they document, so a trailing run
        # of comment/blank lines is handed forward to the next group rather than
        # being deleted with the one it follows.
        function flush(   j, keep, tail) {
            # Find where the trailing comment/blank run starts.
            tail = m + 1
            for (j = m; j >= 1; j--) {
                if (buf[j] ~ /^[[:space:]]*(#|$)/) tail = j; else break
            }
            keep = !(prefix != "" && is_ours)
            for (j = 1; j < tail; j++) if (keep) print buf[j]
            # Carry the trailing run into the next buffer.
            n = 0
            for (j = tail; j <= m; j++) carry[++n] = buf[j]
            m = 0
            for (j = 1; j <= n; j++) buf[++m] = carry[j]
            is_ours = 0
        }
        /^[[:space:]]*\[/ {
            name = $0
            if (match(name, /^[[:space:]]*\[\[hooks\.[A-Za-z0-9_]+\]\][[:space:]]*$/)) {
                flush()
                prefix = name
                sub(/^[[:space:]]*\[\[hooks\./, "", prefix)
                sub(/\]\][[:space:]]*$/, "", prefix)
            } else if (prefix != "" && \
                       index(name, "[hooks." prefix ".") == 0 && \
                       index(name, "[[hooks." prefix ".") == 0) {
                flush()
                prefix = ""
            }
        }
        /agent-status\.sh/ { is_ours = 1 }
                           { buf[++m] = $0 }
        END                { flush(); for (j = 1; j <= m; j++) print buf[j] }
    '
}

# Collapse the runs of blank lines the removals leave behind.
squeeze_blanks() { awk 'NF { blank = 0 } !NF { blank++ } blank < 2'; }

tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT

{
    drop_managed_block < "$CONFIG" | drop_hook_tables
    if [[ "$UNINSTALL" != true ]]; then
        echo
        echo "$BEGIN"
        sed "s|__SCRIPT__|$SCRIPT|g" "$TEMPLATE"
        echo "$END"
    fi
} | squeeze_blanks > "$tmp"

if cmp -s "$tmp" "$CONFIG"; then
    echo "$CONFIG already up to date."
    exit 0
fi

if [[ "$DRY_RUN" == true ]]; then
    echo "--- would write $CONFIG ---"
    diff -u "$CONFIG" "$tmp" || true
    exit 0
fi

backup="${CONFIG}.bak.$(date +%Y%m%d%H%M%S)"
cp -p "$CONFIG" "$backup"
cat "$tmp" > "$CONFIG"

if [[ "$UNINSTALL" == true ]]; then
    echo "Removed agent-badge hooks from $CONFIG (backup: $backup)"
else
    echo "Installed agent-badge hooks into $CONFIG (backup: $backup)"
    echo
    echo "IMPORTANT: start Codex interactively once and approve the hooks."
    echo "Their command paths changed, so the content-addressed trusted_hash"
    echo "entries no longer match -- and until you approve them, every hook is"
    echo "skipped SILENTLY. No badges, and no error to tell you why."
fi
