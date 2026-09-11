#!/bin/bash
# Versioned, data-only machine state for dotfiles preferences and component
# outcomes. Writers use a bounded inter-process lock and atomic replacement.

[[ -n "${_DOTFILES_STATE_LOADED:-}" ]] && return 0
_DOTFILES_STATE_LOADED=1

DOTFILES_STATE_SCHEMA=1
DOTFILES_STATE_DIR="${DOTFILES_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles}"
DOTFILES_PREFERENCES_FILE="$DOTFILES_STATE_DIR/preferences.tsv"
DOTFILES_LEDGER_FILE="$DOTFILES_STATE_DIR/components.tsv"
DOTFILES_JOURNAL_FILE="$DOTFILES_STATE_DIR/transaction.tsv"
DOTFILES_THEME_STATE_FILE="$DOTFILES_STATE_DIR/theme.tsv"
DOTFILES_STATE_LOCK="$DOTFILES_STATE_DIR/.lock"

_state_error() { printf 'Error: %s\n' "$*" >&2; }

_state_valid_atom() {
    [[ "$1" =~ ^[A-Za-z0-9._/@:+-]+$ ]]
}

_state_clean_field() {
    local value="$1"
    value="${value//$'\t'/ }"
    value="${value//$'\n'/ }"
    value="${value//$'\r'/ }"
    [[ -n "$value" ]] && printf '%s' "$value" || printf '%s' '-'
}

_state_validate_file() {
    local file="$1" kind="$2" fields="$3"
    [[ -f "$file" ]] || return 0
    awk -F '\t' -v kind="$kind" -v fields="$fields" '
        NR == 1 { ok = ($1 == "schema" && $2 == "1"); next }
        NF == 0 { next }
        NF != fields { ok = 0 }
        $1 !~ /^[A-Za-z0-9._\/@:+-]+$/ { ok = 0 }
        END { exit ok ? 0 : 1 }
    ' "$file" || {
        _state_error "Invalid $kind state file: $file"
        return 1
    }
}

state_validate() {
    _state_validate_file "$DOTFILES_PREFERENCES_FILE" preferences 2 &&
        _state_validate_file "$DOTFILES_LEDGER_FILE" ledger 8 &&
        _state_validate_file "$DOTFILES_THEME_STATE_FILE" theme 2 &&
        _state_validate_file "$DOTFILES_JOURNAL_FILE" journal 2
}

_state_lock_acquire() {
    local attempts="${DOTFILES_STATE_LOCK_ATTEMPTS:-100}" holder="" i empty_seen=0
    local owner="${BASHPID:-$$}"
    mkdir -p "$DOTFILES_STATE_DIR"
    for ((i = 0; i < attempts; i++)); do
        if mkdir "$DOTFILES_STATE_LOCK" 2>/dev/null; then
            printf '%s\n' "$owner" > "$DOTFILES_STATE_LOCK/pid"
            return 0
        fi
        if [[ -r "$DOTFILES_STATE_LOCK/pid" ]]; then
            read -r holder < "$DOTFILES_STATE_LOCK/pid" || holder=""
            empty_seen=0
        else
            empty_seen=$((empty_seen + 1))
            if (( empty_seen < 5 )); then
                sleep 0.05
                continue
            fi
        fi
        if [[ -n "$holder" && "$holder" =~ ^[0-9]+$ ]] && kill -0 "$holder" 2>/dev/null; then
            sleep 0.05
            continue
        fi
        # A lock without a live numeric owner is stale. Only remove the exact
        # state lock path; never follow or derive this target from state data.
        rm -rf -- "$DOTFILES_STATE_LOCK"
    done
    _state_error "Timed out waiting for dotfiles state lock: $DOTFILES_STATE_LOCK (owner ${holder:-unknown})"
    return 1
}

_state_lock_release() {
    [[ -d "$DOTFILES_STATE_LOCK" ]] || return 0
    local holder=""
    [[ -r "$DOTFILES_STATE_LOCK/pid" ]] && read -r holder < "$DOTFILES_STATE_LOCK/pid" || true
    if [[ -z "$holder" || "$holder" == "${BASHPID:-$$}" ]]; then
        rm -rf -- "$DOTFILES_STATE_LOCK"
    fi
}

_state_commit_file() {
    local staged="$1" target="$2"
    chmod 600 "$staged"
    if [[ -f "$target" ]] && cmp -s "$staged" "$target"; then
        rm -f "$staged"
    else
        mv -f "$staged" "$target"
    fi
}

preference_get() {
    local key="$1"
    _state_valid_atom "$key" || return 1
    _state_validate_file "$DOTFILES_PREFERENCES_FILE" preferences 2 || return 1
    [[ -f "$DOTFILES_PREFERENCES_FILE" ]] || return 1
    awk -F '\t' -v key="$key" 'NR > 1 && $1 == key { value=$2; found=1 } END { if (found) print value; else exit 1 }' \
        "$DOTFILES_PREFERENCES_FILE"
}

preference_set() {
    local key="$1" value="$2"
    _state_valid_atom "$key" || { _state_error "Invalid preference key: $key"; return 1; }
    value="$(_state_clean_field "$value")"
    [[ "$(preference_get "$key" 2>/dev/null || true)" == "$value" ]] && return 0
    (
        _state_lock_acquire || exit 1
        trap _state_lock_release EXIT INT TERM
        _state_validate_file "$DOTFILES_PREFERENCES_FILE" preferences 2 || exit 1
        local staged
        staged="$(mktemp "$DOTFILES_STATE_DIR/preferences.tsv.tmp.XXXXXX")"
        {
            if [[ -f "$DOTFILES_PREFERENCES_FILE" ]]; then
                awk -F '\t' -v key="$key" 'NR > 1 && $1 != key { print $1 "\t" $2 }' "$DOTFILES_PREFERENCES_FILE"
            fi
            printf '%s\t%s\n' "$key" "$value"
        } | LC_ALL=C sort -t $'\t' -k1,1 > "$staged.body"
        { printf 'schema\t%s\n' "$DOTFILES_STATE_SCHEMA"; cat "$staged.body"; } > "$staged"
        rm -f "$staged.body"
        _state_commit_file "$staged" "$DOTFILES_PREFERENCES_FILE"
    )
}

feature_enabled() {
    local feature="$1" request="" value=""
    case "$feature" in
        theme) request="${THEME_REQUEST:-}" ;;
        agent-badge) request="${AGENT_BADGE_REQUEST:-}" ;;
        *) return 1 ;;
    esac
    case "$request" in enabled) return 0 ;; disabled) return 1 ;; esac
    value="$(preference_get "feature.$feature" 2>/dev/null || true)"
    [[ "$value" != "disabled" ]]
}

apply_feature_requests() {
    if [[ -n "${THEME_REQUEST:-}" ]]; then
        if [[ "${DRY_RUN:-false}" == "true" ]]; then
            printf '  [DRY RUN] Would set theme feature: %s\n' "$THEME_REQUEST"
        else
            preference_set feature.theme "$THEME_REQUEST"
        fi
    fi
    if [[ -n "${AGENT_BADGE_REQUEST:-}" ]]; then
        if [[ "${DRY_RUN:-false}" == "true" ]]; then
            printf '  [DRY RUN] Would set agent-badge feature: %s\n' "$AGENT_BADGE_REQUEST"
        else
            preference_set feature.agent-badge "$AGENT_BADGE_REQUEST"
        fi
    fi
    if feature_enabled agent-badge; then
        export DOTFILES_AGENT_BADGE_ENABLED=1
    else
        export DOTFILES_AGENT_BADGE_ENABLED=0
    fi
    if feature_enabled theme; then
        export DOTFILES_THEME_ENABLED=1
    else
        export DOTFILES_THEME_ENABLED=0
    fi
}

ledger_record() {
    local component="$1" applicable="$2" ownership="$3" status="$4"
    local version="${5:-}" path="${6:-}" note="${7:-}" now
    _state_valid_atom "$component" || { _state_error "Invalid component name: $component"; return 1; }
    applicable="$(_state_clean_field "$applicable")"
    ownership="$(_state_clean_field "$ownership")"
    status="$(_state_clean_field "$status")"
    version="$(_state_clean_field "$version")"
    path="$(_state_clean_field "$path")"
    note="$(_state_clean_field "$note")"
    local existing=""
    existing="$(ledger_line "$component" 2>/dev/null || true)"
    if [[ -n "$existing" ]]; then
        local _c _a _o _s _v _p _n _t
        IFS=$'\t' read -r _c _a _o _s _v _p _n _t <<< "$existing"
        if [[ "$_a" == "$applicable" && "$_o" == "$ownership" && "$_s" == "$status" \
           && "$_v" == "$version" && "$_p" == "$path" && "$_n" == "$note" ]]; then
            return 0
        fi
    fi
    now="$(date +%s)"
    (
        _state_lock_acquire || exit 1
        trap _state_lock_release EXIT INT TERM
        _state_validate_file "$DOTFILES_LEDGER_FILE" ledger 8 || exit 1
        local staged
        staged="$(mktemp "$DOTFILES_STATE_DIR/components.tsv.tmp.XXXXXX")"
        {
            printf 'schema\t%s\n' "$DOTFILES_STATE_SCHEMA"
            if [[ -f "$DOTFILES_LEDGER_FILE" ]]; then
                awk -F '\t' -v key="$component" 'NR > 1 && $1 != key { print }' "$DOTFILES_LEDGER_FILE"
            fi
            printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
                "$component" "$applicable" "$ownership" "$status" "$version" "$path" "$note" "$now"
        } > "$staged"
        _state_commit_file "$staged" "$DOTFILES_LEDGER_FILE"
    )
}

ledger_line() {
    local component="$1"
    _state_validate_file "$DOTFILES_LEDGER_FILE" ledger 8 || return 1
    [[ -f "$DOTFILES_LEDGER_FILE" ]] || return 1
    awk -F '\t' -v key="$component" 'NR > 1 && $1 == key { print; found=1 } END { exit found ? 0 : 1 }' "$DOTFILES_LEDGER_FILE"
}

journal_begin() {
    local component="$1" old_path="$2" staged_path="$3" new_path="$4"
    _state_valid_atom "$component" || return 1

    if ! declare -F tool_owned_path >/dev/null 2>&1 \
       || ! tool_owned_path "$component" "$new_path"; then
        _state_error "Cannot reconcile $component: target is outside declared ownership: $new_path"
        return 1
    fi
    if [[ "$old_path" != "$new_path" ]] && ! tool_owned_path "$component" "$old_path"; then
        _state_error "Cannot reconcile $component: rollback path is outside declared ownership: $old_path"
        return 1
    fi
    (
        _state_lock_acquire || exit 1
        trap _state_lock_release EXIT INT TERM
        local staged
        staged="$(mktemp "$DOTFILES_STATE_DIR/transaction.tsv.tmp.XXXXXX")"
        printf 'schema\t%s\ncomponent\t%s\nold_path\t%s\nstaged_path\t%s\nnew_path\t%s\n' \
            "$DOTFILES_STATE_SCHEMA" "$component" "$(_state_clean_field "$old_path")" \
            "$(_state_clean_field "$staged_path")" "$(_state_clean_field "$new_path")" > "$staged"
        _state_commit_file "$staged" "$DOTFILES_JOURNAL_FILE"
    )
}

journal_clear() {
    (
        _state_lock_acquire || exit 1
        trap _state_lock_release EXIT INT TERM
        rm -f "$DOTFILES_JOURNAL_FILE"
    )
}

journal_pending() {
    [[ -s "$DOTFILES_JOURNAL_FILE" ]]
}

journal_field() {
    local key="$1"
    [[ -f "$DOTFILES_JOURNAL_FILE" ]] || return 1
    awk -F '\t' -v key="$key" '$1 == key { print $2; found=1 } END { exit found ? 0 : 1 }' "$DOTFILES_JOURNAL_FILE"
}

journal_reconcile() {
    journal_pending || return 0
    local component old_path new_path binary observed version=""
    component="$(journal_field component)" || return 1
    old_path="$(journal_field old_path)" || return 1
    new_path="$(journal_field new_path)" || return 1
    _state_valid_atom "$component" || return 1

    if ! declare -F tool_owned_path >/dev/null 2>&1 \
       || ! tool_owned_path "$component" "$new_path"; then
        _state_error "Cannot reconcile $component: target is outside declared ownership: $new_path"
        return 1
    fi
    if [[ "$old_path" != "$new_path" ]] && ! tool_owned_path "$component" "$old_path"; then
        _state_error "Cannot reconcile $component: rollback path is outside declared ownership: $old_path"
        return 1
    fi

    if [[ ! -e "$new_path" && -e "$old_path" && "$old_path" != "$new_path" ]]; then
        mv "$old_path" "$new_path"
        case "$(basename "$(dirname "$old_path")")" in
            .dotfiles-*-rollback) rmdir "$(dirname "$old_path")" 2>/dev/null || true ;;
        esac
    fi

    binary="${TOOL_BINARY[$component]:-}"
    observed="${binary:+$(command -v "$binary" 2>/dev/null || true)}"
    [[ -n "$observed" || ! -x "$new_path" ]] || observed="$new_path"
    if [[ -z "$observed" && -n "${TOOL_RELATIVE_BINARY[$component]:-}" \
       && -x "$new_path/${TOOL_RELATIVE_BINARY[$component]}" ]]; then
        observed="$new_path/${TOOL_RELATIVE_BINARY[$component]}"
    fi
    if [[ -n "$observed" ]] && "$observed" --version >/dev/null 2>&1; then
        [[ -n "$observed" ]] && version="$("$observed" --version 2>/dev/null | head -n1 || true)"
        ledger_record "$component" yes dotfiles installed "$version" "$observed" "recovered interrupted transaction"
    else
        ledger_record "$component" yes unknown failed "" "$new_path" "interrupted transaction artifact missing"
    fi
    journal_clear
}

record_install_path() {
    local path="$1"
    [[ "$path" == /* && "$path" != *$'\n'* && "$path" != *$'\r'* && -d "$path" ]] \
        || { _state_error "Invalid dotfiles install path: $path"; return 1; }
    if [[ -f "$DOTFILES_STATE_DIR/install-path" ]] \
       && [[ "$(<"$DOTFILES_STATE_DIR/install-path")" == "$path" ]]; then
        return 0
    fi
    (
        _state_lock_acquire || exit 1
        trap _state_lock_release EXIT INT TERM
        local staged
        staged="$(mktemp "$DOTFILES_STATE_DIR/install-path.tmp.XXXXXX")"
        printf '%s\n' "$path" > "$staged"
        _state_commit_file "$staged" "$DOTFILES_STATE_DIR/install-path"
    )
}

theme_state_value() {
    local key="$1"
    _state_valid_atom "$key" || return 1
    _state_validate_file "$DOTFILES_THEME_STATE_FILE" theme 2 || return 1
    [[ -f "$DOTFILES_THEME_STATE_FILE" ]] || return 1
    awk -F '\t' -v key="$key" 'NR > 1 && $1 == key { value=$2; found=1 } END { if (found) print value; else exit 1 }' \
        "$DOTFILES_THEME_STATE_FILE"
}

theme_state_write_unlocked() {
    # Arguments are key/value pairs and replace the complete theme state in one
    # locked transaction. Empty values are omitted.
    (( $# % 2 == 0 )) || { _state_error "theme_state_write requires key/value pairs"; return 1; }
    mkdir -p "$DOTFILES_STATE_DIR"
    local staged key value
    staged="$(mktemp "$DOTFILES_STATE_DIR/theme.tsv.tmp.XXXXXX")"
    printf 'schema\t%s\n' "$DOTFILES_STATE_SCHEMA" > "$staged"
        while (( $# )); do
            key="$1"; value="$2"; shift 2
            _state_valid_atom "$key" || { _state_error "Invalid theme-state key: $key"; rm -f "$staged"; return 1; }
            [[ -n "$value" ]] || continue
            value="$(_state_clean_field "$value")"
            printf '%s\t%s\n' "$key" "$value" >> "$staged"
    done
    _state_commit_file "$staged" "$DOTFILES_THEME_STATE_FILE"
}

theme_state_write() {
    (
        _state_lock_acquire || exit 1
        trap _state_lock_release EXIT INT TERM
        theme_state_write_unlocked "$@"
    )
}
