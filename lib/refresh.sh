#!/bin/bash
# Refresh: running processes only, never files outside state. Each function
# prints outcome records (lib/outcomes.sh).
#
# tmux: one server, $TMUX's, else the one DOTFILES_TMUX_SERVER names (shared
# with bin/theme-switcher), else the default; none running, nothing to do. The
# global environment gets the managed variables (lib/environment.sh) and
# loses the load guards; a session that overrides a managed variable is
# reported, not changed. Then ~/.tmux.conf is sourced, the agent badge
# rewired, and the theme applied. A server older than the installed tmux is
# reported: only a restart runs the new version.

[[ -n "${_DOTFILES_REFRESH_LOADED:-}" ]] && return 0
_DOTFILES_REFRESH_LOADED=1

refresh_tmux_cmd() {
    if [[ -z "${TMUX:-}" && -n "${DOTFILES_TMUX_SERVER:-}" ]]; then
        command tmux -L "$DOTFILES_TMUX_SERVER" "$@"
    else
        command tmux "$@"
    fi
}

refresh_tmux() {
    local section=tmux produced name value segments="" old_segments="" current_path new_path
    local session line socket server_version client_version failed=false
    local -A want=() unset_names=()
    command -v tmux >/dev/null 2>&1 || { outcome ok "$section" server "tmux is not installed"; return 0; }
    if ! refresh_tmux_cmd list-sessions >/dev/null 2>&1; then
        outcome ok "$section" server "no tmux server is running"
        return 0
    fi
    if ! produced="$(env_produce)"; then
        outcome incomplete "$section" environment "the environment producer failed"
        return 0
    fi
    while IFS=$'\t' read -r name value; do
        case "$name" in
            PATH) segments="$value" ;;
            -*) unset_names[${name#-}]=1 ;;
            ?*) want[$name]="$value" ;;
        esac
    done <<< "$produced"

    for name in "${!want[@]}"; do
        refresh_tmux_cmd set-environment -g "$name" "${want[$name]}" || failed=true
    done
    for name in "${!unset_names[@]}" "${ENV_GUARDS[@]}"; do
        refresh_tmux_cmd set-environment -gu "$name" 2>/dev/null || true
    done
    current_path="$(refresh_tmux_cmd show-environment -g PATH 2>/dev/null)" || current_path=""
    current_path="${current_path#PATH=}"
    [[ ! -r "$ENV_SEGMENTS_FILE" ]] || old_segments="$(<"$ENV_SEGMENTS_FILE")"
    new_path="$(env_path_replace "$old_segments" "$segments" "${current_path:-$ENV_BASE_PATH}")"
    refresh_tmux_cmd set-environment -g PATH "$new_path" || failed=true
    if [[ "$segments" != "$old_segments" ]]; then
        mkdir -p "$(dirname "$ENV_SEGMENTS_FILE")" && printf '%s\n' "$segments" > "$ENV_SEGMENTS_FILE.tmp" \
            && mv -f "$ENV_SEGMENTS_FILE.tmp" "$ENV_SEGMENTS_FILE" || failed=true
    fi
    if [[ "$failed" == true ]]; then
        outcome incomplete "$section" environment "could not update the server's global environment"
    else
        outcome ok "$section" environment "global environment refreshed (${#want[@]} variables, PATH)"
    fi

    # A session's own value wins in its new windows; report, never overwrite.
    while IFS= read -r session; do
        while IFS= read -r line; do
            if [[ "$line" == -* ]]; then
                name="${line#-}"
                [[ -n "${want[$name]+x}" ]] || continue
                outcome advisory "$section" "session $session" "removes $name; its new windows lack the managed value"
            else
                name="${line%%=*}" value="${line#*=}"
                if [[ -n "${want[$name]+x}" && "$value" != "${want[$name]}" ]]; then
                    outcome advisory "$section" "session $session" "overrides $name; its new windows keep that value"
                elif [[ "$name" == PATH && "$value" != "$new_path" ]]; then
                    outcome advisory "$section" "session $session" "overrides PATH; its new windows keep that value"
                fi
            fi
        done < <(refresh_tmux_cmd show-environment -t "$session" 2>/dev/null)
    done < <(refresh_tmux_cmd list-sessions -F '#{session_name}' 2>/dev/null)

    socket="$(refresh_tmux_cmd display-message -p '#{socket_path}' 2>/dev/null || true)"
    if [[ -f "$HOME/.tmux.conf" ]]; then
        if refresh_tmux_cmd source-file "$HOME/.tmux.conf" 2>/dev/null; then
            outcome ok "$section" config "sourced ~/.tmux.conf"
        else
            outcome incomplete "$section" config "sourcing ~/.tmux.conf failed"
        fi
    fi
    if feature_enabled agent-badge && [[ -x "$DOTFILES_DIR/plugins/shared/agent-badge.tmux" ]]; then
        TMUX="$socket,0,0" "$DOTFILES_DIR/plugins/shared/agent-badge.tmux" wire >/dev/null 2>&1 \
            && outcome ok "$section" badge "rewired" || outcome incomplete "$section" badge "rewiring the agent badge failed"
    fi
    if feature_enabled theme; then
        TMUX="$socket,0,0" "$DOTFILES_DIR/bin/theme-switcher" tmux-init >/dev/null 2>&1 \
            && outcome ok "$section" theme "applied" || outcome incomplete "$section" theme "applying the theme failed"
    else
        TMUX="$socket,0,0" "$DOTFILES_DIR/bin/theme-switcher" tmux-off >/dev/null 2>&1 || true
    fi

    server_version="$(refresh_tmux_cmd display-message -p '#{version}' 2>/dev/null || true)"
    client_version="$(command tmux -V 2>/dev/null | awk '{print $2}')"
    if [[ -n "$server_version" && -n "$client_version" && "$server_version" != "$client_version" ]]; then
        outcome health "$section" server "runs tmux $server_version; the installed tmux is $client_version (restart the server to use it)"
    fi
}
