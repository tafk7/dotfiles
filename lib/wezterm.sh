#!/usr/bin/env bash
# The revision stamp in configs/wezterm.lua. WezTerm runs on Windows from a
# copy of that file, so a host can't see whether the copy is current; instead
# the copy names its own revision and sends it over SSH as LC_TAFK_WEZTERM
# (configs/wezterm.lua), and `dotfiles verify` compares it with the repo's
# (verify_wezterm, lib/verify.sh).
#
# The revision is the first 12 hex digits of the file's sha256, taken with the
# stamp's own value blanked, so it changes with every edit. The pre-commit hook
# rejects a stale stamp; `bash lib/wezterm.sh --stamp` rewrites it.
#
#   wezterm_revision_of FILE   the revision FILE's content has
#   wezterm_revision_in FILE   the revision FILE's stamp names; fails without one

_WEZTERM_STAMP="^local CONFIG_REVISION = '[0-9a-f]*'$"

wezterm_revision_of() {
    sed "s/$_WEZTERM_STAMP/local CONFIG_REVISION = ''/" "$1" | sha256sum | cut -c1-12
}

wezterm_revision_in() {
    local line
    line="$(grep -m1 "$_WEZTERM_STAMP" "$1" 2>/dev/null)" || return 1
    line="${line#*\'}"
    printf '%s\n' "${line%\'}"
}

# Run directly: --stamp [FILE] writes FILE's revision into its stamp.
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    set -euo pipefail
    file="${2:-$(dirname "$0")/../configs/wezterm.lua}"
    [[ "${1:-}" == --stamp ]] || { echo "usage: bash lib/wezterm.sh --stamp [FILE]" >&2; exit 2; }
    grep -q "$_WEZTERM_STAMP" "$file" || { echo "no CONFIG_REVISION stamp in $file" >&2; exit 1; }
    revision="$(wezterm_revision_of "$file")"
    sed -i "s/$_WEZTERM_STAMP/local CONFIG_REVISION = '$revision'/" "$file"
    echo "$file: $revision"
fi
