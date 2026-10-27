#!/bin/bash
# versions.lock: the one authority for what dotfiles downloads itself (and the
# sbx package it holds). Parsed with awk so the bash tier needs no Python.
#
# Columns (tab-separated; - for none):
#   component  registry name (or vim-plug)
#   arch       x86_64 | aarch64 | any
#   want       the release tag, version, commit, or APT version wanted
#   source     where it comes from: owner/repo on GitHub, a download host,
#              apt:PACKAGE, rustup (a channel toolchain), or node (bundled npm)
#   artifact   the downloaded file (release asset, script, archive)
#   sha256     the artifact's SHA-256
#   member     the file to extract from the artifact (- for the artifact itself)
#   identity   how the installed component is recognized: sha256:DIGEST of the
#              extracted binary, version:VERSION, or apt:VERSION
# Architectures are normalized: amd64 and arm64 are read as x86_64 and aarch64.

[[ -n "${_DOTFILES_VERSIONS_LOADED:-}" ]] && return 0
_DOTFILES_VERSIONS_LOADED=1

# The lock that belongs to this code, whichever checkout DOTFILES_DIR names.
DOTFILES_VERSIONS_LOCK="${DOTFILES_VERSIONS_LOCK:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/versions.lock}"
VERSIONS_FIELDS=(component arch want source artifact sha256 member identity)

versions_normalize_arch() {
    case "$1" in amd64) echo x86_64 ;; arm64) echo aarch64 ;; *) echo "$1" ;; esac
}

# versions_row COMPONENT [ARCH]: the component's row for ARCH (default: this
# machine's), or its arch-independent row.
versions_row() {
    local component="$1" arch="${2:-}"
    [[ -n "$arch" ]] || arch="$(tool_arch 2>/dev/null || get_arch)"
    arch="$(versions_normalize_arch "$arch")"
    [[ -r "$DOTFILES_VERSIONS_LOCK" ]] || return 1
    awk -F '\t' -v c="$component" -v a="$arch" '
        /^#/ || NF == 0 { next }
        { arch = $2; if (arch == "amd64") arch = "x86_64"; if (arch == "arm64") arch = "aarch64" }
        $1 == c && (arch == a || arch == "any") { print; found = 1; exit }
        END { exit found ? 0 : 1 }' "$DOTFILES_VERSIONS_LOCK"
}

# versions_field COMPONENT FIELD [ARCH]
versions_field() {
    local component="$1" field="$2" arch="${3:-}" row index
    for index in "${!VERSIONS_FIELDS[@]}"; do
        [[ "${VERSIONS_FIELDS[$index]}" == "$field" ]] && break
    done
    [[ "${VERSIONS_FIELDS[$index]}" == "$field" ]] || { printf 'versions_field: unknown field %s\n' "$field" >&2; return 2; }
    row="$(versions_row "$component" "$arch")" || return 1
    awk -F '\t' -v i="$((index + 1))" '{ print $i }' <<< "$row"
}

# Problems with the lock, one per line; nothing when it is valid. Every eget
# tool needs a row per architecture it supports.
versions_problems() {
    [[ -r "$DOTFILES_VERSIONS_LOCK" ]] || { printf 'versions.lock not found: %s\n' "$DOTFILES_VERSIONS_LOCK"; return; }
    awk -F '\t' '
        /^#/ || NF == 0 { next }
        NF != 8 { printf "line %d: %d fields, expected 8\n", NR, NF; next }
        {
            arch = $2; if (arch == "amd64") arch = "x86_64"; if (arch == "arm64") arch = "aarch64"
            if (arch != "x86_64" && arch != "aarch64" && arch != "any") printf "line %d: unknown arch %s\n", NR, $2
            for (i = 1; i <= 8; i++) if ($i == "") printf "line %d: empty field %d\n", NR, i
            if ($3 == "-") printf "line %d: %s has no wanted version\n", NR, $1
            # No {64}: the mawk in Ubuntu 22.04 has no interval expressions.
            if ($6 != "-" && !(length($6) == 64 && $6 ~ /^[0-9a-f]+$/)) printf "line %d: %s sha256 is malformed\n", NR, $1
            if ($8 != "-" && !(length($8) == 71 && $8 ~ /^sha256:[0-9a-f]+$/) && $8 !~ /^(version|apt):./) \
                printf "line %d: %s identity is malformed\n", NR, $1
            key = $1 SUBSEP arch
            if (key in seen) printf "line %d: duplicate %s %s\n", NR, $1, arch
            seen[key] = 1
            if (arch == "any") any[$1] = NR; else specific[$1] = NR
        }
        END { for (c in any) if (c in specific) printf "%s has both an arch-independent row and per-arch rows\n", c }
    ' "$DOTFILES_VERSIONS_LOCK"
    local name arch
    for name in "${!TOOL_METHOD[@]}"; do
        [[ "${TOOL_METHOD[$name]}" == eget ]] || continue
        for arch in ${TOOL_ARCHES[$name]//,/ }; do
            versions_row "$name" "$arch" >/dev/null || printf '%s has no row for %s\n' "$name" "$arch"
        done
    done
    for name in neovim tmux eget nvm vim-plug sbx node npm rust aws-cli; do
        for arch in x86_64 aarch64; do
            versions_row "$name" "$arch" >/dev/null || printf '%s has no row for %s\n' "$name" "$arch"
        done
    done
}
