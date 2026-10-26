#!/bin/bash
# Checks behind `dotfiles verify`. Each prints outcome records
# (lib/outcomes.sh) and changes nothing; the command renders them and exits on
# their classes. Sections: checkout, state, profile, components, configs, AI,
# Docker, local sandboxes, Tailscale, environment, and upstream (--latest).

[[ -n "${_DOTFILES_VERIFY_LOADED:-}" ]] && return 0
_DOTFILES_VERIFY_LOADED=1

# The components this machine should have: the profile's selection when there
# is one, else what the ledger records as installed.
verify_expected_components() {
    local name capability status selected
    if profile_exists && profile_load 2>/dev/null; then
        local ai_tools
        ai_tools=",$(profile_ai_tools | paste -sd, -),"
        for name in $(printf '%s\n' "${!TOOL_BINARY[@]}" | LC_ALL=C sort); do
            selected=false
            tool_in_cumulative_tier "$name" "${PROFILE[tier]}" && selected=true
            for capability in ${TOOL_CAPABILITIES[$name]:+${TOOL_CAPABILITIES[$name]//,/ }}; do
                [[ "$capability" != ai ]] || continue
                _profile_in_list "${PROFILE[capabilities]}" "$capability" && selected=true
            done
            [[ "$ai_tools" != *",$name,"* ]] || selected=true
            [[ "$selected" == true ]] && printf '%s\n' "$name"
        done
    elif [[ -f "$DOTFILES_LEDGER_FILE" ]]; then
        while IFS=$'\t' read -r name _ _ status _; do
            [[ -n "${TOOL_BINARY[$name]:-}" && "$status" != removed && "$status" != not-applicable ]] || continue
            printf '%s\n' "$name"
        done < <(tail -n +2 "$DOTFILES_LEDGER_FILE") | LC_ALL=C sort
    fi
}

# Whether an observed identity is the wanted one: same kind, same value; an APT
# version matches its upstream version with any Debian revision.
identity_matches() {
    local want="$1" have="$2"
    [[ "$want" == - ]] && return 0
    [[ "${want%%:*}" == "${have%%:*}" ]] || return 1
    case "${want%%:*}" in
        apt) [[ "${have#apt:}" == "${want#apt:}" || "${have#apt:}" == "${want#apt:}"-* ]] ;;
        *) [[ "$have" == "$want" ]] ;;
    esac
}

verify_component() {
    local name="$1" section=Components obs rc=0
    local applicable path owner identity want runnable companions ready ready_reason
    obs="$(observe_component "$name" 2>/dev/null)" || rc=$?
    if (( rc != 0 && rc != 3 )); then
        outcome incomplete "$section" "$name" "observation failed"; return
    fi
    applicable="$(observation_field applicable <<< "$obs")"
    path="$(observation_field path <<< "$obs")"
    owner="$(observation_field owner <<< "$obs")"
    identity="$(observation_field identity <<< "$obs")"
    want="$(observation_field want <<< "$obs")"
    runnable="$(observation_field runnable <<< "$obs")"
    companions="$(observation_field companions <<< "$obs")"
    ready="$(observation_field ready <<< "$obs")"
    ready_reason="$(observation_field ready-reason <<< "$obs")"
    if (( rc == 3 )); then
        outcome incomplete "$section" "$name" "could not be observed (${ready_reason:-$(observation_field reason <<< "$obs")})"
        return
    fi
    if [[ "$applicable" == no ]]; then
        outcome ok "$section" "$name" "not applicable here ($(observation_field reason <<< "$obs"))"
        return
    fi
    if [[ -z "$path" ]]; then
        outcome convergence "$section" "$name" "missing"
        return
    fi
    case "$owner" in
        dotfiles)
            if [[ "$runnable" != yes ]]; then
                outcome convergence "$section" "$name" "installed at $path but does not run"
            elif [[ "$companions" != ok ]]; then
                outcome convergence "$section" "$name" "companions ${companions#missing:} missing"
            elif ! identity_matches "$want" "$identity"; then
                outcome convergence "$section" "$name" "off its pin: have ${identity#*:}, want ${want#*:}"
            else
                outcome ok "$section" "$name" "${identity#*:}"
            fi
            ;;
        package-manager)
            if ! identity_matches "$want" "$identity"; then
                outcome convergence "$section" "$name" "off its pin: have ${identity#apt:}, want ${want#apt:} (setup.sh --force installs the pin)"
            else
                outcome ok "$section" "$name" "${identity#*:} (package manager)"
            fi
            ;;
        *)
            if [[ "$runnable" == no ]]; then
                outcome health "$section" "$name" "an external install at $path does not run"
            else
                outcome advisory "$section" "$name" "satisfied by an external install at $path"
            fi
            ;;
    esac
    if [[ "$ready" == no && "$runnable" == yes ]]; then
        outcome health "$section" "$name" "not ready: $ready_reason"
    fi
}

verify_components() {
    local name
    while IFS= read -r name; do
        verify_component "$name"
    done < <(verify_expected_components)
    # sbx is the one pinned APT package: setup holds it, and moves only the
    # holds it placed or was told to adopt.
    local package="${TOOL_APT_PACKAGE[sbx]}"
    if verify_expected_components | grep -Fxq sbx && tool_applicable sbx && apt_package_installed "$package"; then
        if ! apt_package_held "$package"; then
            outcome convergence Components "sbx hold" "$package is not held; setup holds it at the pin"
        elif hold_owned "$package"; then
            outcome ok Components "sbx hold" "held by dotfiles"
        elif [[ "$(hold_status "$package")" == declined ]]; then
            outcome health Components "sbx hold" "$package is held by someone other than dotfiles, who moves it"
        else
            outcome health Components "sbx hold" "$package is held by someone other than dotfiles; run setup in a terminal to decide whether dotfiles adopts the hold"
        fi
    fi
    if feature_enabled agent-badge && verify_expected_components | grep -Eqx 'claude|codex'; then
        if command -v jq >/dev/null 2>&1; then
            outcome ok Components jq "agent-badge JSON dependency"
        else
            outcome convergence Components jq "agent-badge needs jq on PATH (setup installs it)"
        fi
    fi
}

verify_checkout() {
    local section=Checkout install_path="" branch upstream behind dirty
    [[ ! -f "$DOTFILES_STATE_DIR/install-path" ]] || install_path="$(<"$DOTFILES_STATE_DIR/install-path")"
    if [[ -z "$install_path" ]]; then
        outcome convergence "$section" "install path" "not recorded (setup.sh records it)"
    elif [[ "$install_path" != "$DOTFILES_DIR" ]]; then
        outcome advisory "$section" "install path" "this checkout is not the install path ($install_path)"
    else
        outcome ok "$section" "install path" "$install_path"
    fi
    git -C "$DOTFILES_DIR" rev-parse --git-dir >/dev/null 2>&1 || { outcome advisory "$section" git "not a Git checkout"; return; }
    branch="$(git -C "$DOTFILES_DIR" symbolic-ref --quiet --short HEAD 2>/dev/null || true)"
    dirty="$(git -C "$DOTFILES_DIR" status --porcelain 2>/dev/null | wc -l)"
    (( dirty == 0 )) && outcome ok "$section" "working tree" "clean" \
        || outcome advisory "$section" "working tree" "$dirty uncommitted change(s)"
    if [[ -z "$branch" ]]; then
        outcome advisory "$section" branch "detached HEAD"
        return
    fi
    upstream="$(git -C "$DOTFILES_DIR" rev-parse --abbrev-ref '@{upstream}' 2>/dev/null || true)"
    if [[ -z "$upstream" ]]; then
        outcome advisory "$section" branch "$branch has no upstream"
        return
    fi
    behind="$(git -C "$DOTFILES_DIR" rev-list --count "HEAD..$upstream" 2>/dev/null || echo 0)"
    if (( behind > 0 )); then
        outcome advisory "$section" branch "$branch is $behind commit(s) behind $upstream as of the last fetch (dotfiles update)"
    else
        outcome ok "$section" branch "$branch, up to date with $upstream as of the last fetch"
    fi
}

verify_state() {
    local section=State
    if state_validate 2>/dev/null; then outcome ok "$section" "machine state" "valid"
    else outcome incomplete "$section" "machine state" "invalid state files; checks that read them are unreliable"; fi
    if journal_pending; then
        outcome convergence "$section" "artifact journal" "pending for $(journal_pending_components | paste -sd ' '); setup reconciles it"
    else
        outcome ok "$section" "artifact journal" "none pending"
    fi
    if profile_exists; then
        if profile_load 2>/dev/null; then
            outcome ok "$section" profile "tier ${PROFILE[tier]}"
        else
            outcome incomplete "$section" profile "unreadable: $DOTFILES_PROFILE_FILE"
        fi
    else
        outcome advisory "$section" profile "none yet; checking the ledger's components (dotfiles profile --propose)"
    fi
}

verify_configs() {
    local section=Configs config target type owner source_path link_dest
    while IFS= read -r config; do
        IFS=: read -r target type owner <<< "${CONFIG_MAP[$config]}"
        [[ -z "$owner" ]] || config_owner_present "$owner" || continue
        source_path="$(config_source_path "$config")"
        case "$type" in
            symlink)
                if [[ -L "$target" ]]; then
                    link_dest="$(readlink -f "$target" 2>/dev/null || true)"
                    if [[ "$link_dest" == "$(readlink -f "$source_path")" ]]; then
                        outcome ok "$section" "$target"
                    else
                        outcome convergence "$section" "$target" "links elsewhere ($link_dest); setup replaces it, keeping a backup"
                    fi
                elif [[ -e "$target" ]]; then
                    outcome convergence "$section" "$target" "not a link; setup replaces it, keeping a backup"
                else
                    outcome convergence "$section" "$target" "missing"
                fi
                ;;
            gitconfig)
                local portable="${XDG_CONFIG_HOME:-$HOME/.config}/dotfiles/gitconfig"
                if profile_exists && profile_load 2>/dev/null && _profile_in_list "${PROFILE[opt-outs]}" no-git; then
                    outcome ok "$section" "$target" "skipped (no-git)"
                elif [[ -f "$portable" ]] && git config --file "$target" --get-all include.path 2>/dev/null | grep -Fxq "$portable"; then
                    outcome ok "$section" "$target" "includes $portable"
                else
                    outcome convergence "$section" "$target" "lacks the portable include ($portable)"
                fi
                ;;
        esac
    done < <(printf '%s\n' "${!CONFIG_MAP[@]}" | LC_ALL=C sort)
}

verify_ai() {
    local section=AI component
    for component in codex claude; do
        verify_expected_components | grep -Fxq "$component" || continue
        if "$DOTFILES_DIR/bin/ai-config" "$component" --check --plugins >/dev/null 2>&1; then
            outcome ok "$section" "$component settings" "portable settings applied"
        else
            outcome convergence "$section" "$component settings" "portable settings need reconciliation (bin/ai-config $component)"
        fi
    done
}

# Host readiness from lib/work-host.sh, whose checks report through
# check_pass/check_warn/check_fail: none of it can be fixed by apply.
_verify_host_section=""
check_pass() { outcome ok "$_verify_host_section" "$1"; }
check_warn() { outcome advisory "$_verify_host_section" "$1"; }
check_fail() { outcome health "$_verify_host_section" "$1"; }

verify_host() {
    local expected
    expected="$(verify_expected_components)"
    if grep -Fxq docker <<< "$expected" && tool_applicable docker; then
        _verify_host_section=Docker docker_verify_checks true
    fi
    if grep -Fxq sbx <<< "$expected" && tool_applicable sbx; then
        _verify_host_section="Local sandboxes" work_verify_checks true
    fi
    if grep -Fxq tailscale <<< "$expected"; then
        _verify_host_section=Tailscale tail_verify_checks true
    fi
}

verify_environment() {
    local section=Environment
    if [[ -f "$HOME/.gitconfig" ]]; then
        if [[ "$(git config --global --includes --get delta.syntax-theme 2>/dev/null || true)" == ansi ]]; then
            outcome ok "$section" delta "palette-based colors"
        else
            outcome convergence "$section" delta "the Git config lacks the palette-based delta settings"
        fi
    fi
    local agent_path total unique
    agent_path="$(bash -lc 'printf %s "$PATH"' 2>/dev/null </dev/null || true)"
    total="$(tr ':' '\n' <<< "$agent_path" | grep -c . || true)"
    unique="$(tr ':' '\n' <<< "$agent_path" | grep . | sort -u | wc -l)"
    if (( total == unique )); then
        outcome ok "$section" "agent PATH" "$total entries, no duplicates"
    else
        outcome advisory "$section" "agent PATH" "$total entries, $unique unique"
    fi
}

# Newer upstream releases for pinned tools (network), from check-updates'
# records.
verify_upstream() {
    "$DOTFILES_DIR/bin/check-updates" --records 2>/dev/null \
        || outcome incomplete Upstream "release check" "check-updates failed"
}
