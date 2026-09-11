#!/bin/bash
# Theme state and cascade resolution.
#
# Resolution is intentionally scope-first:
#   window tool > window group > window default
#   session tool > session group > session default
#   global tool > global group > global default

[[ -n "${_DOTFILES_THEME_RESOLVE_LOADED:-}" ]] && return 0
_DOTFILES_THEME_RESOLVE_LOADED=1

source "$(dirname "${BASH_SOURCE[0]}")/state.sh"

THEME_DEFAULT="${THEME_DEFAULT:-gruvbox}"

list_all_groups() { printf '%s\n' code chrome apps; }
list_all_surfaces() { printf '%s\n' vim bat delta tmux starship fzf btop lazygit; }

list_surfaces_in_group() {
    case "$1" in
        code) printf '%s\n' vim bat delta ;;
        chrome) printf '%s\n' tmux starship fzf ;;
        apps) printf '%s\n' btop lazygit ;;
        *) return 1 ;;
    esac
}

# Hot-path convention: helpers suffixed `_into` (and `_theme_group_of`) return
# their result in the global `_THEME_REPLY` instead of on stdout. Capturing
# stdout requires `$(...)`, and a command substitution is a fork — measured at
# ~1.8ms here, which turned `theme-switcher env` into 356 clone() calls for 28
# real commands and ~960ms of startup. The printing wrappers below are kept for
# callers outside the hot path (bin/verify, `theme resolve`).
_THEME_REPLY=""

_theme_group_of() {
    case "$1" in
        vim|bat|delta) _THEME_REPLY=code ;;
        tmux|starship|fzf) _THEME_REPLY=chrome ;;
        btop|lazygit) _THEME_REPLY=apps ;;
        *) return 1 ;;
    esac
}

group_for_surface() { _theme_group_of "$1" && printf '%s\n' "$_THEME_REPLY"; }

is_group() { list_surfaces_in_group "$1" >/dev/null 2>&1; }
is_surface() { _theme_group_of "$1"; }
is_theme_target() { [[ "$1" == default ]] || is_group "$1" || is_surface "$1"; }

_theme_generated_dir() { printf '%s\n' "${DOTFILES_THEME_CACHE_DIR:-${DOTFILES_GENERATED_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/dotfiles/theme}}"; }

theme_tmux() {
    if [[ -n "${DOTFILES_TMUX_SERVER:-}" ]]; then
        command tmux -L "$DOTFILES_TMUX_SERVER" "$@"
    else
        command tmux "$@"
    fi
}

# Memoised for the life of the process: `list-sessions` is a fork, and cmd_env
# asks 3-4 times per run. A tmux server that dies mid-run only affects a single
# short-lived invocation, and every tmux call downstream is already `|| true`.
_THEME_TMUX_AVAILABLE=""
theme_tmux_available() {
    if [[ -z "$_THEME_TMUX_AVAILABLE" ]]; then
        if command -v tmux >/dev/null 2>&1 && theme_tmux list-sessions >/dev/null 2>&1; then
            _THEME_TMUX_AVAILABLE=yes
        else
            _THEME_TMUX_AVAILABLE=no
        fi
    fi
    [[ "$_THEME_TMUX_AVAILABLE" == yes ]]
}

_theme_clear_prefix() {
    local prefix="$1" key
    unset "DOTFILES_THEME_${prefix}"
    for key in code chrome apps vim bat delta tmux starship fzf btop lazygit; do
        unset "DOTFILES_THEME_${prefix}_${key^^}"
    done
}

load_global_theme_state() {
    local state legacy key value
    unset DOTFILES_THEME DOTFILES_THEME_GENERATION DOTFILES_THEME_PREVIOUS
    for key in code chrome apps vim bat delta tmux starship fzf btop lazygit; do
        unset "DOTFILES_THEME_${key^^}"
    done

    state="$DOTFILES_THEME_STATE_FILE"
    if [[ -f "$state" ]] && _state_validate_file "$state" theme 2 2>/dev/null; then
        while IFS=$'\t' read -r key value; do
            [[ "$key" == schema ]] && continue
            case "$key" in
                default) DOTFILES_THEME="$value" ;;
                previous) DOTFILES_THEME_PREVIOUS="$value" ;;
                generation) DOTFILES_THEME_GENERATION="$value" ;;
                code|chrome|apps|vim|bat|delta|tmux|starship|fzf|btop|lazygit)
                    printf -v "DOTFILES_THEME_${key^^}" '%s' "$value"
                    export "DOTFILES_THEME_${key^^}"
                    ;;
            esac
        done < "$state"
    else
        # Preserve the old global state during migration. Reading never writes.
        local legacy_dir="${DOTFILES_LEGACY_GENERATED_DIR:-${DOTFILES_DIR:?}/generated}"
        legacy="$legacy_dir/theme.sh"
        if [[ -f "$legacy" ]]; then
            while IFS='=' read -r key value; do
                key="${key#export }"
                case "$key" in DOTFILES_THEME|_DOTFILES_PREVIOUS_THEME) ;; *) continue ;; esac
                value="${value#\"}"; value="${value%\"}"; value="${value#\'}"; value="${value%\'}"
                [[ "$value" =~ ^[A-Za-z0-9._-]+$ ]] || continue
                if [[ "$key" == DOTFILES_THEME ]]; then
                    DOTFILES_THEME="$value"
                else
                    DOTFILES_THEME_PREVIOUS="$value"
                fi
            done < "$legacy"
        fi
        legacy="$legacy_dir/theme-overrides.sh"
        if [[ -f "$legacy" ]]; then
            while IFS='=' read -r key value; do
                key="${key#export }"
                [[ "$key" == DOTFILES_THEME_* ]] || continue
                value="${value#\"}"; value="${value%\"}"; value="${value#\'}"; value="${value%\'}"
                [[ "$value" =~ ^[A-Za-z0-9._-]+$ ]] || continue
                case "$key" in
                    DOTFILES_THEME_CODE|DOTFILES_THEME_CHROME|DOTFILES_THEME_APPS|DOTFILES_THEME_VIM|DOTFILES_THEME_BAT|DOTFILES_THEME_DELTA|DOTFILES_THEME_TMUX|DOTFILES_THEME_STARSHIP|DOTFILES_THEME_FZF|DOTFILES_THEME_BTOP|DOTFILES_THEME_LAZYGIT)
                        printf -v "$key" '%s' "$value"; export "${key?}" ;;
                esac
            done < "$legacy"
        fi
    fi

    export DOTFILES_THEME="${DOTFILES_THEME:-$THEME_DEFAULT}"
    export DOTFILES_THEME_GENERATION="${DOTFILES_THEME_GENERATION:-0}"
    export DOTFILES_THEME_PREVIOUS="${DOTFILES_THEME_PREVIOUS:-}"
}

# Compatibility name used by older callers and bin/verify.
load_theme_overrides() { load_global_theme_state; }

_theme_tmux_option_name() {
    [[ "$1" == default ]] && printf '@dotfiles_theme_default\n' \
        || printf '@dotfiles_theme_%s\n' "$1"
}

_theme_load_tmux_scope() {
    local scope="$1" target="$2" prefix="$3" key option value line
    local -a flag=()
    [[ -n "$target" ]] || return 0
    [[ "$scope" == window ]] && flag=(-w)

    while IFS= read -r line; do
        option="${line%% *}"
        value="${line#* }"
        value="${value#\"}"; value="${value%\"}"
        key="${option#@dotfiles_theme_}"
        case "$key" in default|code|chrome|apps|vim|bat|delta|tmux|starship|fzf|btop|lazygit) ;; *) continue ;; esac
        if [[ "$key" == default ]]; then
            printf -v "DOTFILES_THEME_${prefix}" '%s' "$value"
            export "DOTFILES_THEME_${prefix}"
        else
            printf -v "DOTFILES_THEME_${prefix}_${key^^}" '%s' "$value"
            export "DOTFILES_THEME_${prefix}_${key^^}"
        fi
    done < <(theme_tmux show-options -q "${flag[@]}" -t "$target" 2>/dev/null | awk '$1 ~ /^@dotfiles_theme_/')
    return 0
}

theme_window_sessions() {
    local window_id="$1"
    theme_tmux list-windows -a -F '#{window_id} #{session_id}' 2>/dev/null \
        | awk -v w="$window_id" '$1 == w { print $2 }' \
        | sort -t'$' -k2,2n -u
}

theme_window_owner_session() {
    local window_id="$1" sessions
    sessions="$(theme_window_sessions "$window_id")"
    [[ -n "$sessions" ]] || return 1
    # Linked windows own one pane tree and one option set. The lowest stable
    # session id is the deterministic inheritance owner when no window value
    # masks session state. Moving an unlinked window naturally changes owner.
    printf '%s\n' "$sessions" | head -1
}

theme_detect_context() {
    local requested_session="${1:-}" requested_window="${2:-}" detected
    THEME_CONTEXT_SESSION="$requested_session"
    THEME_CONTEXT_WINDOW="$requested_window"

    if [[ -z "$THEME_CONTEXT_WINDOW" && -n "${TMUX:-}" ]] && theme_tmux_available; then
        detected="$(theme_tmux display-message -p '#{session_id} #{window_id}' 2>/dev/null || true)"
        THEME_CONTEXT_SESSION="${detected%% *}"
        THEME_CONTEXT_WINDOW="${detected#* }"
    fi

    if [[ -n "$THEME_CONTEXT_WINDOW" ]]; then
        # One `list-windows` pass feeds both values. Calling theme_window_sessions
        # and theme_window_owner_session separately re-ran the same tmux query.
        local -a linked=()
        local sess
        mapfile -t linked < <(theme_window_sessions "$THEME_CONTEXT_WINDOW")
        if (( ${#linked[@]} )); then
            THEME_CONTEXT_LINKED_SESSIONS="${linked[0]}"
            for sess in "${linked[@]:1}"; do
                THEME_CONTEXT_LINKED_SESSIONS+=",$sess"
            done
            # Linked windows own one pane tree and one option set. The lowest
            # stable session id is the deterministic inheritance owner when no
            # window value masks session state.
            THEME_CONTEXT_SESSION="${linked[0]}"
        else
            THEME_CONTEXT_LINKED_SESSIONS=""
        fi
    else
        THEME_CONTEXT_LINKED_SESSIONS=""
    fi
    export THEME_CONTEXT_SESSION THEME_CONTEXT_WINDOW THEME_CONTEXT_LINKED_SESSIONS
}

load_theme_context() {
    local requested_session="${1:-}" requested_window="${2:-}"
    load_global_theme_state
    _theme_clear_prefix SESSION
    _theme_clear_prefix WINDOW
    theme_detect_context "$requested_session" "$requested_window"
    [[ -n "$THEME_CONTEXT_SESSION" ]] && _theme_load_tmux_scope session "$THEME_CONTEXT_SESSION" SESSION
    [[ -n "$THEME_CONTEXT_WINDOW" ]] && _theme_load_tmux_scope window "$THEME_CONTEXT_WINDOW" WINDOW
    return 0
}

# Resolve into $_THEME_REPLY. Fork-free — this is the hot path, called once per
# surface on every shell start and every prompt refresh.
resolve_surface_theme_into() {
    local surface="$1" group upper gupper scope var
    _theme_group_of "$surface" || {
        echo "resolve_surface_theme: unknown surface '$surface'" >&2; return 2
    }
    group="$_THEME_REPLY"
    upper="${surface^^}"; gupper="${group^^}"

    for scope in WINDOW SESSION; do
        for var in \
            "DOTFILES_THEME_${scope}_${upper}" \
            "DOTFILES_THEME_${scope}_${gupper}" \
            "DOTFILES_THEME_${scope}"
        do
            if [[ -n "${!var:-}" ]]; then _THEME_REPLY="${!var}"; return 0; fi
        done
    done

    for var in "DOTFILES_THEME_${upper}" "DOTFILES_THEME_${gupper}" DOTFILES_THEME; do
        if [[ -n "${!var:-}" ]]; then _THEME_REPLY="${!var}"; return 0; fi
    done
    _THEME_REPLY=""
    return 1
}

resolve_surface_theme() { resolve_surface_theme_into "$1" && printf '%s\n' "$_THEME_REPLY"; }

resolve_surface_source() {
    local surface="$1" group upper gupper scope label var
    _theme_group_of "$surface" || return 2
    group="$_THEME_REPLY"
    upper="${surface^^}"; gupper="${group^^}"
    for scope in WINDOW SESSION; do
        label="${scope,,}"
        var="DOTFILES_THEME_${scope}_${upper}"
        [[ -n "${!var:-}" ]] && { printf '%s:tool\n' "$label"; return; }
        var="DOTFILES_THEME_${scope}_${gupper}"
        [[ -n "${!var:-}" ]] && { printf '%s:group(%s)\n' "$label" "$group"; return; }
        var="DOTFILES_THEME_${scope}"
        [[ -n "${!var:-}" ]] && { printf '%s:default\n' "$label"; return; }
    done
    var="DOTFILES_THEME_${upper}"
    [[ -n "${!var:-}" ]] && { printf 'global:tool\n'; return; }
    var="DOTFILES_THEME_${gupper}"
    [[ -n "${!var:-}" ]] && { printf 'global:group(%s)\n' "$group"; return; }
    printf 'global:default\n'
}

resolve_group_theme() {
    local surface
    is_group "$1" || return 2
    surface="$(list_surfaces_in_group "$1" | head -1)"
    resolve_surface_theme "$surface"
}

group_has_override() {
    local var="DOTFILES_THEME_${1^^}"
    [[ -n "${!var:-}" ]]
}

surface_has_override() {
    local var="DOTFILES_THEME_${1^^}"
    [[ -n "${!var:-}" ]]
}
