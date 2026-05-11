#!/bin/bash
# Theme cascade resolution helpers.
#
# Cascade rule:  surface override  >  group override  >  global default
#
# State sources (read-only at resolve-time):
#   - DOTFILES_THEME                             : global default
#   - DOTFILES_THEME_<GROUP>                     : group override (uppercased)
#   - DOTFILES_THEME_<SURFACE>                   : surface override (uppercased)
#
# State files (managed by bin/theme-switcher; sourced by shell/env.sh):
#   - generated/theme.sh                         : emits DOTFILES_THEME + resolved per-surface exports
#   - generated/theme-overrides.sh               : user-set overrides (DOTFILES_THEME_<KEY>=...)
#
# This file is pure logic — no I/O beyond reading env vars and listing
# the canonical group/surface tables. Safe to source on every shell start.

[[ -n "${_DOTFILES_THEME_RESOLVE_LOADED:-}" ]] && return 0
_DOTFILES_THEME_RESOLVE_LOADED=1

# ==============================================================================
# Canonical taxonomy — groups and their surfaces.
# Keep in sync with bin/theme-switcher's apply_<surface>_theme functions
# and docs/theme-system.md "Per-component overrides" section.
# ==============================================================================

# Group → space-separated surfaces. Order within a group is the apply order.
_THEME_GROUP_CODE_SURFACES="vim bat delta"
_THEME_GROUP_CHROME_SURFACES="tmux starship fzf"
_THEME_GROUP_APPS_SURFACES="btop lazygit"

# All groups, in display order.
list_all_groups() {
    printf '%s\n' code chrome apps
}

# All surfaces, in apply order (group order × within-group order).
list_all_surfaces() {
    printf '%s\n' vim bat delta tmux starship fzf btop lazygit
}

# Surfaces in a given group. Empty stdout + non-zero exit if unknown group.
list_surfaces_in_group() {
    local group="$1"
    case "$group" in
        code)   printf '%s\n' $_THEME_GROUP_CODE_SURFACES ;;
        chrome) printf '%s\n' $_THEME_GROUP_CHROME_SURFACES ;;
        apps)   printf '%s\n' $_THEME_GROUP_APPS_SURFACES ;;
        *) return 1 ;;
    esac
}

# Reverse lookup: which group does this surface belong to?
group_for_surface() {
    local surface="$1"
    case "$surface" in
        vim|bat|delta)      printf 'code\n' ;;
        tmux|starship|fzf)  printf 'chrome\n' ;;
        btop|lazygit)       printf 'apps\n' ;;
        *) return 1 ;;
    esac
}

# True if name is a known group.
is_group() { list_surfaces_in_group "$1" >/dev/null 2>&1; }

# True if name is a known surface.
is_surface() { group_for_surface "$1" >/dev/null 2>&1; }

# ==============================================================================
# Cascade resolution
# ==============================================================================

# uppercase helper (POSIX-portable, no `${var^^}` because lib must work in sh
# contexts that test functions; bash 4+ is fine for the actual shell, but
# keeping this portable makes the helpers easier to audit).
_theme_upper() { printf '%s' "$1" | tr '[:lower:]' '[:upper:]'; }

# Effective theme for a surface. Cascade: surface > group > global.
# Returns the resolved theme name on stdout. Empty + exit 1 if global also unset.
resolve_surface_theme() {
    local surface="$1"
    is_surface "$surface" || { echo "resolve_surface_theme: unknown surface '$surface'" >&2; return 2; }

    local surface_var group_var group
    surface_var="DOTFILES_THEME_$(_theme_upper "$surface")"
    if [[ -n "${!surface_var:-}" ]]; then
        printf '%s\n' "${!surface_var}"
        return 0
    fi

    group="$(group_for_surface "$surface")"
    group_var="DOTFILES_THEME_$(_theme_upper "$group")"
    if [[ -n "${!group_var:-}" ]]; then
        printf '%s\n' "${!group_var}"
        return 0
    fi

    if [[ -n "${DOTFILES_THEME:-}" ]]; then
        printf '%s\n' "$DOTFILES_THEME"
        return 0
    fi

    return 1
}

# Effective theme for a group. Cascade: group override > global default.
# (Surface overrides within the group are NOT considered — this is the
#  "what does the group banner say" function; per-surface drift is shown
#  by `theme-switcher show` separately.)
resolve_group_theme() {
    local group="$1"
    is_group "$group" || { echo "resolve_group_theme: unknown group '$group'" >&2; return 2; }

    local group_var
    group_var="DOTFILES_THEME_$(_theme_upper "$group")"
    if [[ -n "${!group_var:-}" ]]; then
        printf '%s\n' "${!group_var}"
        return 0
    fi

    if [[ -n "${DOTFILES_THEME:-}" ]]; then
        printf '%s\n' "$DOTFILES_THEME"
        return 0
    fi

    return 1
}

# True if the group has an explicit override (the var is set & non-empty).
group_has_override() {
    local group="$1"
    is_group "$group" || return 2
    local v
    v="DOTFILES_THEME_$(_theme_upper "$group")"
    [[ -n "${!v:-}" ]]
}

# True if the surface has an explicit override.
surface_has_override() {
    local surface="$1"
    is_surface "$surface" || return 2
    local v
    v="DOTFILES_THEME_$(_theme_upper "$surface")"
    [[ -n "${!v:-}" ]]
}

# ==============================================================================
# Override file I/O
# Pure exports of the form: export DOTFILES_THEME_<KEY>="value"
# Atomic via temp-file + mv.
# ==============================================================================

# Path resolution — DOTFILES_DIR is set by lib/runtime.sh or env.sh.
_theme_overrides_file() {
    printf '%s\n' "${DOTFILES_DIR:?DOTFILES_DIR must be set}/generated/theme-overrides.sh"
}

# Ensure the file exists with a header. No-op if already present.
_theme_overrides_init() {
    local file
    file="$(_theme_overrides_file)" || return 1
    [[ -f "$file" ]] && return 0
    mkdir -p "$(dirname "$file")"
    cat > "$file" << 'EOF'
# Auto-managed by bin/theme-switcher — per-component theme overrides.
# Cascade: surface override > group override > global default ($DOTFILES_THEME).
# Edit via: theme-switcher set|unset|reset (do not edit by hand).
EOF
}

# Set or replace a single override. Args: <KEY> <value>
# KEY is the bare suffix (e.g. "BAT", "CODE") — uppercased here.
_theme_overrides_set() {
    local key value file tmp
    key="$(_theme_upper "$1")"
    value="$2"
    file="$(_theme_overrides_file)" || return 1
    _theme_overrides_init
    tmp="$(mktemp "${file}.XXXXXX")"
    awk -v k="DOTFILES_THEME_$key" '
        $0 ~ "^export " k "=" { next }
        { print }
    ' "$file" > "$tmp"
    printf 'export DOTFILES_THEME_%s="%s"\n' "$key" "$value" >> "$tmp"
    mv "$tmp" "$file"
}

# Remove a single override. Args: <KEY>. No-op if not present.
_theme_overrides_unset() {
    local key file tmp
    key="$(_theme_upper "$1")"
    file="$(_theme_overrides_file)" || return 1
    [[ -f "$file" ]] || return 0
    tmp="$(mktemp "${file}.XXXXXX")"
    awk -v k="DOTFILES_THEME_$key" '
        $0 ~ "^export " k "=" { next }
        { print }
    ' "$file" > "$tmp"
    mv "$tmp" "$file"
}

# Truncate the overrides file (back to header only).
_theme_overrides_reset() {
    local file
    file="$(_theme_overrides_file)" || return 1
    rm -f "$file"
    _theme_overrides_init
}

# List active overrides. Output: lines of "<KEY>=<value>" (no `export ` prefix).
_theme_overrides_list() {
    local file
    file="$(_theme_overrides_file)" || return 1
    [[ -f "$file" ]] || return 0
    grep -oP '^export DOTFILES_THEME_\K[A-Z]+="[^"]*"' "$file" 2>/dev/null \
        | sed 's/="/=/; s/"$//'
}

# Source the overrides file into the current shell (used by env.sh and by
# theme-switcher between mutations + apply). Idempotent: clears all cascade
# env vars first so removed lines actually take effect.
# Safe under `set -u` because the file only contains `export VAR=value`.
load_theme_overrides() {
    local file s g
    file="${DOTFILES_DIR:-}/generated/theme-overrides.sh"

    # Clear any previously-loaded cascade vars so file edits propagate.
    for g in code chrome apps; do
        unset "DOTFILES_THEME_$(_theme_upper "$g")"
    done
    for s in vim bat delta tmux starship fzf btop lazygit; do
        unset "DOTFILES_THEME_$(_theme_upper "$s")"
    done

    [[ -f "$file" ]] && source "$file"
    return 0
}
