#!/bin/bash
# Tiered dotfiles installer. See --help.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

DOTFILES_DIR="$SCRIPT_DIR"
export DOTFILES_DIR

source "$SCRIPT_DIR/lib/install.sh"
source "$SCRIPT_DIR/lib/setup-log.sh"
source "$SCRIPT_DIR/lib/operation.sh"
source "$SCRIPT_DIR/lib/profile.sh"

INSTALL_TIER="config"  # Base when only orthogonal flags are given: config, bash, dev, work

# Selected capabilities. ai is "all" for --ai / --full (every registry tool
# with the ai capability), else "some" for the per-tool flags recorded in
# SELECTED_AI_TOOLS. rdp opens a network listener and is never implied by --full.
declare -A SELECTED_CAPABILITIES=()
declare -a SELECTED_AI_TOOLS=() # --claude / --codex / --opencode / --pi, in flag order.
THEME_REQUEST=""       # Empty preserves preference; enabled/disabled are explicit changes.
AGENT_BADGE_REQUEST=""
FORCE_OVERWRITE=false
FORCE_REINSTALL=false
REINSTALL_COMPONENTS=""  # --reinstall=X,Y: reinstall only these components.
ONLY_COMPONENTS=""       # --only X,Y: install only these, configs untouched.
SHOW_HELP=false
DRY_RUN=false
NO_HOOKS=false
NO_GIT=false          # --no-git: skip ~/.gitconfig entirely (no prompt, no write).
EDITOR_PLUGINS=false  # --editor-plugins: vim-plug and the Neovim plugins at their pins.
PARSE_ERROR=false

tier_rank() {
    case "$1" in
        config) echo 0 ;;
        bash) echo 1 ;;
        dev) echo 2 ;;
        work) echo 3 ;;
        *) return 1 ;;
    esac
}

request_tier() {
    local requested="$1" current_rank requested_rank
    current_rank="$(tier_rank "$INSTALL_TIER")"
    requested_rank="$(tier_rank "$requested")"
    if (( requested_rank > current_rank )); then
        INSTALL_TIER="$requested"
    fi
}

require_option_value() {
    local option="$1" value="${2:-}"
    if [[ -z "$value" || "$value" == --* ]]; then
        error "$option requires a value"
        PARSE_ERROR=true
        return 1
    fi
}

# require_components OPTION LIST: every comma-separated name is a component.
require_components() {
    local name
    [[ -n "$2" ]] || { error "$1 requires component names"; PARSE_ERROR=true; return 1; }
    for name in ${2//,/ }; do
        [[ -n "${TOOL_BINARY[$name]:-}" ]] && continue
        error "$1: unknown component: $name"
        PARSE_ERROR=true
    done
}

# Git identity (optional; falls back to existing config or interactive prompt).
# Read by process_git_config() in lib/install.sh.
DOTFILES_GIT_NAME="${DOTFILES_GIT_NAME:-}"
DOTFILES_GIT_EMAIL="${DOTFILES_GIT_EMAIL:-}"

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --config)
                # Reconcile action: lay down base configs + configs for whatever
                # tools are currently installed. No package installs, no sudo.
                request_tier "config"
                shift
                ;;
            --bash)
                request_tier "bash"
                shift
                ;;
            --dev)
                request_tier "dev"
                shift
                ;;
            --work)
                request_tier "work"
                shift
                ;;
            --full)
                # Convenience: exactly --work --ai.
                request_tier "work"
                SELECTED_CAPABILITIES[ai]=all
                shift
                ;;
            --ai)
                SELECTED_CAPABILITIES[ai]=all
                shift
                ;;
            --claude|--codex|--opencode|--pi)
                SELECTED_AI_TOOLS+=("${1#--}")
                [[ "${SELECTED_CAPABILITIES[ai]:-}" == all ]] || SELECTED_CAPABILITIES[ai]=some
                shift
                ;;
            --theme)
                THEME_REQUEST="enabled"
                shift
                ;;
            --no-theme)
                THEME_REQUEST="disabled"
                shift
                ;;
            --agent-badge)
                AGENT_BADGE_REQUEST="enabled"
                shift
                ;;
            --no-agent-badge)
                AGENT_BADGE_REQUEST="disabled"
                shift
                ;;
            --force)
                FORCE_OVERWRITE=true
                FORCE_REINSTALL=true
                shift
                ;;
            --reinstall)
                FORCE_REINSTALL=true
                shift
                ;;
            --reinstall=*)
                REINSTALL_COMPONENTS="${1#--reinstall=}"
                require_components --reinstall "$REINSTALL_COMPONENTS"
                shift
                ;;
            --overwrite-configs)
                FORCE_OVERWRITE=true
                shift
                ;;
            --only)
                require_option_value "$1" "${2:-}" || { shift; continue; }
                ONLY_COMPONENTS="$2"
                require_components --only "$ONLY_COMPONENTS"
                shift 2
                ;;
            --only=*)
                ONLY_COMPONENTS="${1#--only=}"
                require_components --only "$ONLY_COMPONENTS"
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --no-hooks)
                NO_HOOKS=true
                shift
                ;;
            --no-git)
                NO_GIT=true
                shift
                ;;
            --editor-plugins)
                EDITOR_PLUGINS=true
                shift
                ;;
            --git-name)
                require_option_value "$1" "${2:-}" || { shift; continue; }
                DOTFILES_GIT_NAME="$2"
                shift 2
                ;;
            --git-email)
                require_option_value "$1" "${2:-}" || { shift; continue; }
                DOTFILES_GIT_EMAIL="$2"
                shift 2
                ;;
            --help)
                SHOW_HELP=true
                shift
                ;;
            *)
                # Any other capability is selected by its own --NAME flag.
                if [[ "$1" == --?* && -n "${CAPABILITY_LABEL[${1#--}]:-}" ]]; then
                    SELECTED_CAPABILITIES[${1#--}]=yes
                else
                    error "Unknown option: $1"
                    PARSE_ERROR=true
                fi
                shift
                ;;
        esac
    done
    # --only names components this run selects; the rest of the profile is not
    # installed behind the operator's back.
    local name
    for name in ${ONLY_COMPONENTS//,/ }; do
        [[ -n "${TOOL_BINARY[$name]:-}" ]] || continue
        component_selected "$name" && continue
        error "--only: $name is not selected by this run's tier or capabilities"
        PARSE_ERROR=true
    done
    [[ "$PARSE_ERROR" == "false" ]]
}

# Whether the selected cumulative tier (config → bash → dev → work) includes $1.
# Orthogonal selections such as AI are checked with capability_selected.
tier_includes() {
    local required="$1"
    case "$INSTALL_TIER" in
        work) return 0 ;;
        dev) [[ "$required" != "work" ]] ;;
        bash) [[ "$required" == "config" || "$required" == "bash" ]] ;;
        config) [[ "$required" == "config" ]] ;;
    esac
}

capability_selected() {
    [[ -n "${SELECTED_CAPABILITIES[$1]:-}" ]]
}

any_capability_selected() {
    (( ${#SELECTED_CAPABILITIES[@]} > 0 ))
}

capability_requires() {
    [[ " ${CAPABILITY_REQUIRES[$1]:-} " == *" $2 "* ]]
}

# Whether any selected capability has requirement $1.
selected_capabilities_need() {
    local name
    for name in "${!SELECTED_CAPABILITIES[@]}"; do
        capability_requires "$name" "$1" && return 0
    done
    return 1
}

# Whether this run selects component $1: its tier, a selected capability, or
# for AI CLIs --ai or its own flag. jq comes with the AI CLIs agent-badge
# decorates.
component_selected() {
    local name="$1" capability
    tool_in_cumulative_tier "$name" "$INSTALL_TIER" && return 0
    if tool_has_capability "$name" ai; then
        case "${SELECTED_CAPABILITIES[ai]:-}" in
            all) return 0 ;;
            some) [[ " ${SELECTED_AI_TOOLS[*]} " == *" $name "* ]] && return 0 ;;
        esac
        return 1
    fi
    if tool_has_capability "$name" agent-badge; then
        feature_enabled agent-badge && { component_selected claude || component_selected codex; }
        return
    fi
    for capability in "${CAPABILITY_NAMES[@]}"; do
        [[ "$capability" != ai ]] || continue
        capability_selected "$capability" && tool_has_capability "$name" "$capability" && return 0
    done
    return 1
}

package_set_selected() {
    tier_includes "${PACKAGE_SET_TIER[$1]}"
}

# Validate, save, then apply: once the system check accepts this run's flags,
# they join the machine profile before anything is installed. Flags only add
# (lib/profile.sh); a preview never writes the profile. An unreadable profile
# is reported and left alone, without stopping setup.
setup_save_profile() {
    [[ "$DRY_RUN" == true ]] && return 0
    if ! profile_load; then
        warn "Machine profile not updated; repair or remove $DOTFILES_PROFILE_FILE"
        return 0
    fi
    local capability capabilities="" opt_outs="" ai_tools=""
    for capability in "${CAPABILITY_NAMES[@]}"; do
        if [[ "$capability" != ai ]] && capability_selected "$capability"; then
            capabilities+="${capabilities:+,}$capability"
        fi
    done
    [[ "$NO_GIT" != true ]] || opt_outs+="no-git,"
    [[ "$NO_HOOKS" != true ]] || opt_outs+="no-hooks,"
    (( ${#SELECTED_AI_TOOLS[@]} == 0 )) || ai_tools="$(IFS=,; printf '%s' "${SELECTED_AI_TOOLS[*]}")"
    profile_merge "$INSTALL_TIER" "$capabilities" "${SELECTED_CAPABILITIES[ai]:-}" "$ai_tools" "${opt_outs%,}" \
        "$([[ "$EDITOR_PLUGINS" == true ]] && echo yes)"
    profile_save || return 1
    (( ${#PROFILE_CHANGES[@]} == 0 )) || log "Machine profile: ${PROFILE_CHANGES[*]}"
}

# help_entry FLAG TEXT: one option, its text wrapped beside it.
help_entry() {
    printf '%s\n' "$2" | fold -s -w 56 | sed 's/ *$//' \
        | awk -v flag="$1" 'NR == 1 { printf "    %-20s%s\n", flag, $0; next } { printf "%24s%s\n", "", $0 }'
}

# help_components TIER: the tier's components in install order, with platform
# limits noted. eget (the bootstrap) and package-set members are left out.
help_components() {
    local name entry out=""
    for name in "${REGISTRY_ORDER[@]}"; do
        [[ "$name" != packages:* && "${TOOL_TIER[$name]:-}" == "$1" ]] || continue
        [[ "${TOOL_INSTALL[$name]}" != bootstrap && "${TOOL_INSTALL[$name]}" != packages:* ]] || continue
        entry="$name"
        case "${TOOL_PLATFORM[$name]}" in
            wsl) entry+=" (WSL)" ;;
            native-ubuntu) entry+=" (native Ubuntu ${TOOL_UBUNTU_VERSIONS[$name]//,//})" ;;
        esac
        out+="${out:+, }$entry"
    done
    printf '%s' "$out"
}

show_help() {
    local ai_tools name capability text
    ai_tools="$(tools_for_capability ai | paste -sd, - | sed 's/,/, /g')"
    cat << 'EOF'
Dotfiles Installation Script - Tiered Installation System

USAGE:
    ./setup.sh <TIER|ACTION> [OPTIONS]

    Bare `./setup.sh` (no arguments) prints this help and changes nothing —
    installing packages and rewriting $HOME configs must always be explicit.

    --config            Reconcile action: (re)create symlinks for base configs
                        plus configs for whatever tools are already installed.
                        Zero package installs. No sudo. Safe to re-run anytime —
                        it syncs your symlinks to what's actually on the system.

TIERS (cumulative - each tier includes all previous tiers):
EOF
    help_entry --bash "Config + modern CLI tools. NO SUDO: every tool installs to ~/.local/bin via eget: $(help_components bash). The non-sudo base for managed systems. (git is assumed present; a tool already installed system-wide is left alone unless --force.)"
    echo
    help_entry --dev "Bash + development tools. Requires sudo (the first APT layer): zsh, build tools, clipboard, graphviz, and more, then $(help_components dev)."
    echo
    help_entry --work "Dev + local development and agent execution. Requires sudo. Adds $(help_components work), at the versions versions.lock pins; sbx brings KVM host access. Where sbx does not apply (WSL, 22.04) it is skipped and the rest installs. AI, Tailscale, RDP, and cloud CLIs stay orthogonal; leave AI off where an organization manages those CLIs."
    echo
    help_entry --full "Work tier plus all AI CLIs. Requires sudo. Equivalent to: --work --ai"
    echo
    echo "AI TOOLING (orthogonal - combines with any tier):"
    help_entry --ai "${CAPABILITY_HELP[ai]} ($ai_tools)"
    for name in $(tools_for_capability ai); do
        help_entry "--$name" "Only $name."
    done
    help_entry "" "Per-tool flags combine: --claude --opencode installs just those two; --ai and --full install all of them. Pi is an npm package, so it needs Node >=22.19 (the work tier's pinned Node); without it, the request fails with instructions rather than pulling in a toolchain."
    echo
    echo "CAPABILITIES (orthogonal - combine with any tier):"
    for capability in "${CAPABILITY_NAMES[@]}"; do
        [[ "$capability" != ai ]] || continue
        text="${CAPABILITY_HELP[$capability]}"
        capability_requires "$capability" sudo && text+=" Requires sudo."
        help_entry "--$capability" "$text"
    done
    cat << 'EOF'

OPTIONS:
    --dry-run           Show what would change, from what is installed now;
                        change nothing. Lines marked Unknown could not be
                        checked in advance.
    --only X[,Y]        Install only these selected components, in order;
                        a need that is not installed blocks one rather than
                        being installed. Configs are left as they are.
    --reinstall[=X,Y]   Reinstall every selected component, or the named ones.
    --overwrite-configs Replace configs that differ, keeping backups.
    --force             Both: --reinstall --overwrite-configs
    --no-hooks          Don't install dotfiles git hooks (pre-commit lint)
    --no-git            Skip ~/.gitconfig (no identity prompt; leaves any existing
                        one alone). Also skips the delta pager wiring.
    --editor-plugins    Install vim-plug and the Neovim plugins configs/init.vim
                        pins, and move them to their pinned commits (with Neovim).
    --theme             Enable tmux themes (default).
    --no-theme          Persistently disable tmux themes.
    --agent-badge       Enable agent-badge for supported AI CLIs (default with AI).
    --no-agent-badge    Install AI CLIs without registering agent-badge.
    --git-name NAME     Set git user.name (for non-interactive installs)
    --git-email EMAIL   Set git user.email (for non-interactive installs)
    --help              Show this help message

ENVIRONMENT:
    DOTFILES_GIT_NAME   Same as --git-name
    DOTFILES_GIT_EMAIL  Same as --git-email
    DOTFILES_APT_LOCK_TIMEOUT
                        Seconds APT waits for another package operation (default: 120)

EXAMPLES:
    ./setup.sh                       # Prints this help; changes nothing
    ./setup.sh --config              # Reconcile symlinks to installed tools
    ./setup.sh --bash                # Modern shell experience, NO sudo
    ./setup.sh --dev                 # Development setup (no AI CLIs)
    ./setup.sh --dev --ai            # Development setup + all AI CLIs
    ./setup.sh --dev --claude        # Development setup + only Claude Code
    ./setup.sh --claude --opencode   # Config + just those two AI CLIs
    ./setup.sh --work                # Local work environment, AI stays separate
    ./setup.sh --full                # Exactly --work --ai
    ./setup.sh --work --tail         # Local sbx work environment + Tailscale
    ./setup.sh --work --claude --codex --tail
    ./setup.sh --full --tail --gcloud
    ./setup.sh --work --azure        # Former --work cloud-tool behavior
    ./setup.sh --dev --rdp           # Dev setup + RDP into this machine's desktop
    ./setup.sh --bash --dry-run      # Preview bash tier installation

TIER SUMMARY:
    config   symlinks only (reconcile to installed tools)      no sudo
    bash     + eget CLI tools in ~/.local/bin                   no sudo
    dev      + APT packages and development tools              sudo
    work     + local development and agent execution           sudo
    --full   = work + ai (no Tailscale, RDP, or cloud CLIs)    sudo
    The tier sudo boundary is at dev. Tailscale, RDP, and APT-backed cloud
    selections require sudo independently of the selected tier.

The script will:
1. Verify system requirements
2. Install packages based on selected tier
3. Create symlinks for all configuration files
4. Setup WSL integration if running on WSL

All configuration files are backed up before being replaced.
EOF
}


phase_verify_system() {
    log "Phase 1: System Verification"

    # Check the distribution identity, not merely whether lsb_release happens
    # to be installed on an unrelated distribution.
    local os_release="${DOTFILES_OS_RELEASE:-/etc/os-release}" os_id="" os_version=""
    if [[ -r "$os_release" ]]; then
        os_id="$(awk -F= '$1 == "ID" { gsub(/^"|"$/, "", $2); print $2; exit }' "$os_release")"
        os_version="$(awk -F= '$1 == "VERSION_ID" { gsub(/^"|"$/, "", $2); print $2; exit }' "$os_release")"
    fi
    if [[ "$os_id" != "ubuntu" ]]; then
        if tier_includes "dev" || selected_capabilities_need ubuntu; then
            error "APT-backed tiers, Tailscale, RDP, and cloud selections require Ubuntu (detected: ${os_id:-unknown})"
            return 1
        fi
        warn "Ubuntu not detected - APT-backed features are unavailable"
    elif [[ "$os_version" != 22.04 && "$os_version" != 24.04 && "$os_version" != 26.04 ]]; then
        if tier_includes "dev" || selected_capabilities_need ubuntu; then
            error "Unsupported Ubuntu release: ${os_version:-unknown} (supported: 22.04, 24.04, 26.04)"
            return 1
        fi
        warn "Ubuntu ${os_version:-unknown} is outside the tested support matrix"
    fi
    get_arch >/dev/null || return 1
    # Every download's pin comes from versions.lock; a malformed lock stops a
    # tier that downloads before anything is fetched.
    local lock_problems
    lock_problems="$(versions_problems)"
    if [[ -n "$lock_problems" ]]; then
        if tier_includes bash; then
            error "versions.lock is invalid:"
            sed 's/^/  /' <<< "$lock_problems" >&2
            return 1
        fi
        warn "versions.lock is invalid (not needed for the config tier): $(head -n1 <<< "$lock_problems")"
    fi
    if is_wsl && [[ "$(wsl_version)" != 2 ]]; then
        error "WSL1 is unsupported; use WSL2"
        return 1
    fi

    # Check basic tools that should exist. The bash tier needs curl (eget
    # bootstrap + downloads) and git; apt is not involved until the dev tier.
    for cmd in curl git; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            if tier_includes "bash" || { [[ "$cmd" == curl ]] && selected_capabilities_need curl; }; then
                error "Required command not found: $cmd"
                return 1
            else
                warn "Command not found: $cmd (not required for config tier)"
            fi
        fi
    done
    local requirement
    for requirement in apt:apt-get sudo:sudo systemd:systemctl; do
        selected_capabilities_need "${requirement%%:*}" || continue
        cmd="${requirement#*:}"
        command -v "$cmd" >/dev/null 2>&1 || { error "Requested APT/service capability requires: $cmd"; return 1; }
    done

    local capability component
    if tier_includes work && ! tool_applicable sbx; then
        warn "Local sandboxes (sbx, KVM access) need native Ubuntu 24.04/26.04; --work installs the other work tools here"
    fi

    for capability in "${CAPABILITY_NAMES[@]}"; do
        capability_selected "$capability" && capability_requires "$capability" applicable || continue
        while IFS= read -r component; do
            tool_applicable "$component" || {
                error "--$capability is unsupported on ${os_id:-unknown} ${os_version:-unknown}/$(tool_arch 2>/dev/null || printf unknown) ($component is not applicable)"
                return 1
            }
        done < <(tools_for_capability "$capability")
    done

    detect_environment

    success "System verification complete"
}

phase_install_packages() {
    log "Phase 2: Package Installation"

    if ! tier_includes "bash" && ! any_capability_selected; then
        log "Config tier: skipping package installation"
        return 0
    fi

    install_selection || INSTALLATION_FAILED=true

    if [[ "$INSTALLATION_FAILED" == "true" ]]; then
        error "One or more requested package operations failed"
        return 1
    fi
    success "Package installation complete"
}

phase_setup_configs() {
    log "Phase 3: Configuration and Validation"
    local failed=false
    if [[ -n "$ONLY_COMPONENTS" ]]; then
        log "Configs left as they are (--only)"
        return 0
    fi
    
    # Backups are created lazily by the first operation that actually displaces
    # user data. Matching symlinks and dry-runs create no backup directories.
    ACTIVE_BACKUP_DIR=""
    
    if [[ "$DRY_RUN" == "true" ]]; then
        readarray -t sorted_configs < <(printf '%s\n' "${!CONFIG_MAP[@]}" | sort)
        for config in "${sorted_configs[@]}"; do
            local mapping="${CONFIG_MAP[$config]}"
            local target type owner
            IFS=: read -r target type owner <<< "$mapping"
            config_owner_present "$owner" || continue
            [[ "$type" != "gitconfig" || "$NO_GIT" != "true" ]] || continue
            if [[ "$type" == gitconfig ]]; then
                local portable
                portable="$(portable_gitconfig_path)"
                if [[ ! -f "$portable" ]] || ! cmp -s <(render_portable_gitconfig "$(config_source_path "$config")") "$portable"; then
                    log "  ✓ $portable (would render the portable Git config)"
                fi
                git config --file "$target" --get-all include.path 2>/dev/null | grep -Fxq "$portable" \
                    || log "  ✓ $target (would add the portable include)"
            elif [[ -L "$target" ]]; then
                [[ "$(readlink -f "$target")" == "$(readlink -f "$(config_source_path "$config")")" ]] \
                    || log "  ↻ $target (links to $(readlink "$target"); would relink)"
            elif [[ -e "$target" ]]; then
                log "  ⚠️  $target (file exists - would backup and link)"
            else
                log "  ✓ $target (would create $type)"
            fi
        done
        retire_deployed_configs || failed=true
        is_wsl && log "[DRY RUN] Would setup WSL clipboard integration"
        is_wsl && [[ -f "$HOME/.ssh/use-windows-agent" ]] && log "[DRY RUN] Would install the WSL ssh-agent bridge service (marker present)"
    else
        readarray -t sorted_configs < <(printf '%s\n' "${!CONFIG_MAP[@]}" | sort)
        for config in "${sorted_configs[@]}"; do
            local mapping="${CONFIG_MAP[$config]}"
            local target type owner
            IFS=: read -r target type owner <<< "$mapping"

            # Never lay down configs for tools that aren't installed.
            if ! config_owner_present "$owner"; then
                log "Skipping $target — $owner not installed"
                continue
            fi

            local source
            source="$(config_source_path "$config")"

            case "$type" in
                symlink)
                    local before_link
                    before_link="$(deployed_line "$target" 2>/dev/null | cut -f3)"
                    if process_symlink "$source" "$target"; then
                        deployed_record "$target" link "$(readlink "$target")" "$config" || failed=true
                        [[ "$before_link" == "$(readlink "$target")" ]] || config_changed "$config"
                    else
                        failed=true
                    fi
                    ;;
                gitconfig)
                    if [[ "$NO_GIT" == "true" ]]; then
                        log "Skipping $target (--no-git)"
                    else
                        if process_git_config "$source" "$target" "$FORCE_OVERWRITE"; then
                            local portable
                            portable="$(portable_gitconfig_path)"
                            deployed_record "$portable" rendered "sha256:$(sha256sum "$portable" | awk '{print $1}')" "$config" \
                                && deployed_record "$target" merged "include:$portable" "$config" || failed=true
                        else
                            failed=true
                        fi
                    fi
                    ;;
                *)
                    error "Unknown config type: $type for $config"
                    failed=true
                    ;;
            esac
        done
        retire_deployed_configs || failed=true
    fi
    
    if is_wsl && [[ "$DRY_RUN" != "true" ]]; then
        setup_wsl_clipboard || failed=true
        setup_wsl_ssh_agent || failed=true
    fi

    if [[ -n "${DOTFILES_REFRESH_FOLLOWS:-}" ]]; then
        log "Running processes (tmux, theme) are refreshed after setup"
    elif feature_enabled theme; then
        if [[ "$DRY_RUN" == "true" ]]; then
            # A server's socket, checked without starting tmux.
            [[ ! -S "${TMUX_TMPDIR:-/tmp}/tmux-$(id -u)/default" ]] || log "[DRY RUN] Would apply the theme to the running tmux server"
        else
            "$DOTFILES_DIR/bin/theme-switcher" tmux-init || failed=true
        fi
    else
        log "Theme feature disabled; tmux uses the terminal's colors"
        [[ "$DRY_RUN" == "true" ]] || "$DOTFILES_DIR/bin/theme-switcher" tmux-off || failed=true
    fi

    if [[ "$NO_HOOKS" == "true" ]]; then
        log "Skipping git hooks install (--no-hooks)"
    elif [[ "$DRY_RUN" == "true" ]]; then
        "$DOTFILES_DIR/bin/install-git-hooks" --check >/dev/null 2>&1 \
            || log "[DRY RUN] Would install git hooks (use --no-hooks to skip)"
    else
        "$DOTFILES_DIR/bin/install-git-hooks" --quiet || { warn "git hooks install failed"; failed=true; }
    fi

    write_dotfiles_env || failed=true
    reconcile_observed_components || failed=true

    if [[ "$DRY_RUN" != "true" && -n "${ACTIVE_BACKUP_DIR:-}" ]]; then
        cleanup_old_backups 10
    fi

    if [[ "$failed" == true ]]; then
        error "Configuration reconciliation failed"
        return 1
    fi
    success "Configuration complete"
}

# A changed config makes the processes that read it at startup stale: shells
# for the shell entry files, Neovim for its init. tmux reloads its config on
# refresh, and other tools read theirs on each run.
config_changed() {
    case "$1" in
        bash.sh|zsh.sh|zshenv|zprofile|profile.sh|bash_profile) change_record shell "$1 linked" ;;
        init.vim) change_record neovim "init.vim linked" ;;
    esac
    return 0
}

process_symlink() {
    local source="$1" target="$2"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would link $source -> $target"
        return 0
    fi
    
    local parent_dir
    parent_dir="$(dirname "$target")"
    if [[ ! -d "$parent_dir" ]]; then
        mkdir -p "$parent_dir" || return 1
    fi

    # SSH directory requires strict permissions
    if [[ "$parent_dir" == *"/.ssh"* || "$parent_dir" == *"/.ssh" ]]; then
        chmod 700 "$parent_dir" || return 1
        mkdir -p "$parent_dir/sockets" || return 1
        chmod 700 "$parent_dir/sockets" || return 1
    fi
    
    safe_symlink "$source" "$target"
}

run_installation() {
    INSTALLATION_FAILED=false
    local journal_blocked=false
    if journal_pending; then
        if [[ "$DRY_RUN" == true ]]; then
            warn "Incomplete component transaction detected; dry-run will not reconcile it."
        else
            warn "Recovering an interrupted component transaction before setup."
            # An unresolved journal blocks only its own component's replacement;
            # the rest of setup proceeds, and the run still reports failure.
            if ! journal_reconcile; then
                journal_blocked=true
                warn "Replacements stay blocked for: $(journal_pending_components | paste -sd ' ')"
            fi
        fi
    fi
    phase_verify_system || INSTALLATION_FAILED=true
    if [[ "$INSTALLATION_FAILED" != "true" ]]; then
        apply_feature_requests || INSTALLATION_FAILED=true
    fi
    if [[ "$INSTALLATION_FAILED" != "true" ]]; then
        setup_save_profile || INSTALLATION_FAILED=true
    fi
    if [[ "$INSTALLATION_FAILED" != "true" ]]; then
        phase_install_packages || INSTALLATION_FAILED=true
        phase_setup_configs || INSTALLATION_FAILED=true
    fi

    print_install_summary

    if [[ "$INSTALLATION_FAILED" == "true" || "$journal_blocked" == true || ${#INSTALL_FAIL[@]} -gt 0 ]]; then
        echo
        error "Dotfiles installation incomplete; see the summary above."
        return 1
    fi

    local summary="tier: $INSTALL_TIER" capability
    for capability in "${CAPABILITY_NAMES[@]}"; do
        if capability_selected "$capability"; then summary+=" +$capability"; fi
    done
    echo
    success "Dotfiles installation complete! ($summary)"
    echo

    local needs_restart=false

    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Next Steps:"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo

    if tier_includes "work" && command -v docker >/dev/null 2>&1; then
        if [[ "$(host_group_state docker)" == pending ]]; then
                echo "* Docker group membership requires restart"
                needs_restart=true
        fi
    fi

    if tier_includes "work" && tool_applicable sbx && [[ "$(host_group_state kvm)" == pending ]]; then
        echo "* KVM group membership requires a new login"
        needs_restart=true
    fi

    local nvm_installed=false
    if tier_includes "work" && [[ -d "$HOME/.nvm" ]]; then
        nvm_installed=true
    fi

    local step=1
    if tier_includes "bash"; then
        echo "$step. Restart your shell session:"
        if is_wsl; then
            echo "   - Type 'exit' then reopen WSL, OR"
            echo "   - From PowerShell/CMD: wsl --terminate Ubuntu"
        else
            echo "   - Type 'exit' then reconnect to your terminal"
        fi
        if [[ "$needs_restart" == "true" ]]; then
            echo "   (Required for Docker group and locale changes)"
        else
            echo "   (Recommended for locale and shell changes)"
        fi
        echo
        ((step++))
    fi

    echo "$step. Verify installation:"
    if tier_includes "work"; then
        if capability_selected tail; then
            echo "   ./bin/verify --tier work --tail"
        else
            echo "   ./bin/verify --tier work"
        fi
    else
        echo "   ./bin/verify"
    fi
    echo
    ((step++))

    if tier_includes "work" && tool_applicable sbx; then
        echo "$step. Authenticate and smoke-test local sandboxes manually:"
        echo "   sbx login"
        echo "   ./bin/verify --tier work --smoke"
        echo
        ((step++))
    fi

    if capability_selected tail; then
        echo "$step. Enroll Tailscale with your intended routing/SSH policy:"
        echo "   sudo tailscale up"
        echo
        ((step++))
    fi

    if capability_selected rdp; then
        echo "$step. Connect to the RDP desktop:"
        if is_wsl; then
            echo "   From this machine's Windows host: mstsc -> localhost:3390"
        else
            echo "   mstsc -> $(hostname):3389  (keep behind VPN/Tailscale — never expose to the internet)"
        fi
        echo
        ((step++))
    fi

    if is_wsl && tier_includes "bash"; then
        echo "$step. (Personal WSL) Use your Windows SSH agent (Bitwarden/1Password):"
        echo "   ./bin/ssh-bridge enable     # bridges vault keys into WSL, then reload"
        echo "   (Work machines using local keys: skip — leave it disabled.)"
        echo
        ((step++))
    fi

    if [[ "$nvm_installed" == "true" ]]; then
        echo "$step. Test Node.js/npm:"
        echo "   node --version && npm --version"
        echo
        ((step++))
    fi

    if feature_enabled theme; then
        echo "$step. Switch theme (default: gruvbox):"
        echo "   ./bin/theme-switcher"
    else
        echo "$step. Theme feature is disabled (enable with: ./bin/dotfiles-feature enable theme)"
    fi

    echo
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

main() {
    # Running as root would target /root and grant root's groups instead of the
    # invoking user's; steps that need root call sudo themselves.
    if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
        echo "Error: do not run setup.sh as root." >&2
        echo "Run it as your normal user; the script invokes sudo only where required." >&2
        exit 1
    fi

    # Installing packages and rewriting $HOME must never happen by accident, so a
    # bare invocation only prints help.
    if [[ $# -eq 0 ]]; then
        show_help
        exit 0
    fi

    if ! parse_arguments "$@"; then
        show_help >&2
        exit 64
    fi

    if [[ "$SHOW_HELP" == "true" ]]; then
        show_help
        exit 0
    fi

    setup_log_start "$@"

    echo "Dotfiles Installation"
    echo "===================================="
    echo "Target: Ubuntu (including WSL)"
    echo "Tier: $INSTALL_TIER"
    case "${SELECTED_CAPABILITIES[ai]:-}" in
        all) echo "${CAPABILITY_LABEL[ai]}: all ($(tools_for_capability ai | paste -sd, - | sed 's/,/, /g'))" ;;
        some) echo "${CAPABILITY_LABEL[ai]}: ${SELECTED_AI_TOOLS[*]}" ;;
        *) echo "${CAPABILITY_LABEL[ai]}: none" ;;
    esac
    local capability
    for capability in "${CAPABILITY_NAMES[@]}"; do
        if [[ "$capability" != ai ]] && capability_selected "$capability"; then
            echo "${CAPABILITY_LABEL[$capability]}: yes (--$capability)"
        fi
    done
    [[ "$DRY_RUN" == "true" ]] && echo "Mode: DRY RUN (no changes will be made)"
    echo
    
    run_installation
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    # A run that changes state holds the operation lock; help and previews,
    # including a bare invocation, do not.
    if (( $# )) && ! operation_read_only_args "$@"; then
        operation_begin "$SCRIPT_DIR/setup.sh" "$@"
    fi
    main "$@"
fi
