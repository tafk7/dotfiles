#!/bin/bash
# Configuration steps: what a component needs beyond its binary (settings,
# plugin registration, services). The registry's configure column names them;
# setup runs them after a component's install step whether or not it changed
# anything, so a current or external CLI still gets them. Each takes the
# component name and returns non-zero only when its configuration failed.
# Sourced by lib/install.sh.

[[ -n "${_DOTFILES_CONFIGURE_LOADED:-}" ]] && return 0
_DOTFILES_CONFIGURE_LOADED=1

# configure_component NAME: run NAME's configure steps.
configure_component() {
    local name="$1" step failed=false
    for step in ${TOOL_CONFIGURE[$name]:-}; do
        "$step" "$name" || { warn "$name: $step failed"; failed=true; }
    done
    [[ "$failed" == false ]]
}

# The AI CLI a shell runs: the one on PATH, else the managed copy (a fresh
# machine's PATH may lack ~/.local/bin).
_ai_cli_command() {
    local name="$1"
    command -v "$name" 2>/dev/null && return 0
    [[ -x "$HOME/.local/bin/$name" ]] || return 1
    printf '%s\n' "$HOME/.local/bin/$name"
}

_agent_badge_wanted() {
    if [[ -n "${DOTFILES_AGENT_BADGE_ENABLED:-}" ]]; then
        [[ "$DOTFILES_AGENT_BADGE_ENABLED" == 1 ]]
    else
        feature_enabled agent-badge
    fi
}

# Portable settings, reconciled by bin/ai-config (backups stay in each
# application's home).
configure_ai_settings() {
    if [[ "${DRY_RUN:-false}" == true ]]; then
        log "[DRY RUN] Would reconcile $1's portable settings (bin/ai-config $1 --dry-run previews them)"
        return 0
    fi
    "$DOTFILES_DIR/bin/ai-config" "$1"
}

# Register the agent-badge plugin from this repository, which is also a
# marketplace, as a local directory: it tracks the working tree and needs no
# network. Never fatal: the badge is a convenience.
configure_agent_badge() {
    local name="$1" cmd
    if ! _agent_badge_wanted; then
        log "Agent-badge disabled; skipping $name plugin registration."
        return 0
    fi
    cmd="$(_ai_cli_command "$name")" || return 0
    if [[ "${DRY_RUN:-false}" == true ]]; then
        log "[DRY RUN] Would register the agent-badge plugin with $name"
        return 0
    fi
    case "$name" in
        claude)
            [[ -f "$DOTFILES_DIR/.claude-plugin/marketplace.json" ]] || return 0
            "$cmd" plugin marketplace add "$DOTFILES_DIR" >/dev/null 2>&1 \
                && "$cmd" plugin install agent-badge@tafk7 >/dev/null 2>&1
            ;;
        codex)
            # plugin add also replaces Codex's cache of the plugin.
            [[ -f "$DOTFILES_DIR/.agents/plugins/marketplace.json" ]] || return 0
            "$cmd" plugin marketplace add "$DOTFILES_DIR" >/dev/null 2>&1 \
                && "$cmd" plugin add agent-badge@tafk7 >/dev/null 2>&1
            ;;
    esac || { warn "Could not register the agent-badge plugin with $name; see plugins/agent-badge-$name/README.md."; return 0; }
    # tmux survives plugin cache replacement; repair its paths now.
    [[ -z "${TMUX:-}" ]] || "$DOTFILES_DIR/plugins/shared/agent-badge.tmux" wire >/dev/null 2>&1 || true
    log "Agent-badge registered with $name (tmux window badges; new sessions pick it up)."
}

# Bring an installed badge plugin up to this checkout's version: Claude Code
# keeps an installed plugin until it is updated. Separate from registration,
# which does not move an installed plugin.
update_agent_badge() {
    local name="$1" cmd
    _agent_badge_wanted || return 0
    cmd="$(_ai_cli_command "$name")" || return 0
    "$DOTFILES_DIR/bin/ai-config" "$name" --check-plugin >/dev/null 2>&1 && return 0
    if [[ "${DRY_RUN:-false}" == true ]]; then
        log "[DRY RUN] Would update $name's agent-badge plugin to this checkout's version"
        return 0
    fi
    case "$name" in
        claude) "$cmd" plugin marketplace update tafk7 >/dev/null 2>&1 && "$cmd" plugin update agent-badge@tafk7 >/dev/null 2>&1 ;;
        codex) "$cmd" plugin add agent-badge@tafk7 >/dev/null 2>&1 ;;
    esac || { warn "Could not update $name's agent-badge plugin; see plugins/agent-badge-$name/README.md."; return 0; }
    [[ -z "${TMUX:-}" ]] || "$DOTFILES_DIR/plugins/shared/agent-badge.tmux" wire >/dev/null 2>&1 || true
    log "Updated $name's agent-badge plugin (restart $name sessions to load it)."
}

# OpenCode's settings are V2's; an external V1 keeps its own.
configure_opencode_settings() {
    local cmd version
    cmd="$(_ai_cli_command opencode)" || return 0
    version="$("$cmd" --version 2>/dev/null || true)"
    if [[ ! "$version" =~ ^(opencode[[:space:]]+)?v?2\.[0-9]+\.[0-9]+$ ]]; then
        warn "opencode at $cmd is not V2 (${version:-no version}); its settings are left alone"
        return 0
    fi
    configure_ai_settings opencode
}

# Seed ~/.pi/agent/settings.json with install telemetry off, only when it is
# absent: the file is user-owned (models, keybindings, trust), so an existing
# one only gets a hint. The startup version check is controlled by
# PI_SKIP_VERSION_CHECK / PI_OFFLINE (see docs/ai-tools-egress.md).
configure_pi_settings() {
    local src="$DOTFILES_DIR/configs/pi-settings.json" dest="$HOME/.pi/agent/settings.json"
    [[ -f "$src" ]] || return 0
    if [[ -e "$dest" ]]; then
        log "Existing $dest left untouched."
        log "  To disable install/update telemetry, add \"enableInstallTelemetry\": false"
        log "  (see configs/pi-settings.json and docs/ai-tools-egress.md)."
        return 0
    fi
    if [[ "${DRY_RUN:-false}" == true ]]; then
        log "[DRY RUN] Would provision $dest (install/update telemetry off)"
        return 0
    fi
    mkdir -p "$(dirname "$dest")" && cp "$src" "$dest" || return 1
    success "Provisioned ~/.pi/agent/settings.json (install/update telemetry off)."
}

# tailscaled runs under systemd once installed. A masked unit is the
# operator's decision and is left as it is; nothing here enrolls the node.
configure_tailscaled() {
    command -v tailscale >/dev/null 2>&1 || return 0
    if ! host_systemd_running; then
        warn "systemd is unavailable, so tailscaled was not enabled"
        return 0
    fi
    # A preview runs no systemctl at all, queries included.
    if [[ "${DRY_RUN:-false}" == true ]]; then
        log "[DRY RUN] Would enable and start tailscaled unless it is masked or already running"
        return 0
    fi
    if [[ "$(systemctl is-enabled tailscaled 2>/dev/null || true)" == masked ]]; then
        log "tailscaled is masked; leaving it as it is"
        return 0
    fi
    if systemctl is-enabled --quiet tailscaled 2>/dev/null && systemctl is-active --quiet tailscaled 2>/dev/null; then
        return 0
    fi
    safe_sudo systemctl enable --now tailscaled || { error "tailscaled could not be enabled/started"; return 1; }
}
