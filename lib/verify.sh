#!/bin/bash
# Checks behind `dotfiles verify`. Each prints outcome records
# (lib/outcomes.sh) and changes nothing; the command renders them and exits on
# their classes. Sections: checkout, state, profile, components, configs,
# editor plugins, AI, Docker, local sandboxes, Tailscale, Git, WSL,
# environment, agent shell, the WezTerm copy on Windows, running
# (lib/staleness.sh), and upstream (--latest).

[[ -n "${_DOTFILES_VERIFY_LOADED:-}" ]] && return 0
_DOTFILES_VERIFY_LOADED=1

# What verify checks against, from the command's options. By default, the
# profile's selection (the ledger's components without a profile). --tier
# checks that tier's components instead; each capability option adds its
# components, which must then apply here; --all also looks at every other
# component that applies here. --smoke checks Docker's and the sandboxes'
# readiness wherever they apply, since the smoke test needs both.
VERIFY_TIER=""
VERIFY_CAPABILITIES=""
VERIFY_ALL=false
VERIFY_SMOKE=false

# The components the capability options ask for, one per line.
verify_requested_components() {
    local capability
    for capability in ${VERIFY_CAPABILITIES//,/ }; do
        tools_for_capability "$capability"
    done
}

verify_requested() {
    local requested
    requested="$(verify_requested_components)"
    grep -Fxq -- "$1" <<< "$requested"
}

# The components this machine should have: the profile's selection when there
# is one, else what the ledger records as installed; or --tier's components;
# plus what the capability options ask for.
verify_expected_components() {
    {
        _verify_selected_components
        verify_requested_components
    } | LC_ALL=C sort -u
}

_verify_selected_components() {
    local name capability status selected
    if [[ -n "$VERIFY_TIER" ]]; then
        for name in "${!TOOL_BINARY[@]}"; do
            tool_in_cumulative_tier "$name" "$VERIFY_TIER" && printf '%s\n' "$name"
        done
    elif profile_exists && profile_load 2>/dev/null; then
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
        done < <(tail -n +2 "$DOTFILES_LEDGER_FILE")
    fi
    return 0
}

# verify_expects NAME: whether NAME is among the expected components. Reads
# the whole list first: piped into grep -q, the writer can be cut off early,
# and under pipefail its SIGPIPE reads as "not expected".
verify_expects() {
    local expected
    expected="$(verify_expected_components)"
    grep -Fxq -- "$1" <<< "$expected"
}

# verify_component NAME [optional]: one component's records. An optional one
# (--all, outside the selection) that is not installed is only a note.
verify_component() {
    local name="$1" optional="${2:-}" section=Components obs rc=0
    local applicable path owner identity want runnable companions ready ready_reason
    local recorded_owner="" recorded_status=""
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
        if verify_requested "$name"; then
            outcome health "$section" "$name" "requested, but it cannot apply here ($(observation_field reason <<< "$obs"))"
        else
            outcome ok "$section" "$name" "not applicable here ($(observation_field reason <<< "$obs"))"
        fi
        return
    fi
    if [[ -z "$path" ]]; then
        if [[ -n "$optional" ]]; then
            outcome advisory "$section" "$name" "not installed (not selected here)"
        else
            outcome convergence "$section" "$name" "missing"
        fi
        return
    fi
    IFS=$'\t' read -r _ _ recorded_owner recorded_status _ < <(ledger_line "$name" 2>/dev/null || true) || true
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
            elif [[ "$recorded_owner" == unknown ]]; then
                # Present before the ledger: kept as found, and not pinned.
                outcome advisory "$section" "$name" "at $path from before the ledger; not pinned until adopted (dotfiles apply --only $name --reinstall=$name)"
            else
                outcome advisory "$section" "$name" "satisfied by an external install at $path"
            fi
            ;;
    esac
    if [[ "$recorded_status" == update-failed ]]; then
        outcome advisory "$section" "$name" "its last update failed; the earlier install is still in place"
    fi
    if [[ "$ready" == no && "$runnable" == yes ]]; then
        outcome health "$section" "$name" "not ready: $ready_reason"
    fi
}

verify_components() {
    local name expected
    expected="$(verify_expected_components)"
    while IFS= read -r name; do
        [[ -z "$name" ]] || verify_component "$name"
    done <<< "$expected"
    if [[ "$VERIFY_ALL" == true ]]; then
        while IFS= read -r name; do
            grep -Fxq -- "$name" <<< "$expected" || verify_component "$name" optional
        done < <(printf '%s\n' "${!TOOL_BINARY[@]}" | LC_ALL=C sort)
    fi
    # sbx is the one pinned APT package: setup holds it, and moves only the
    # holds it placed or was told to adopt.
    local package="${TOOL_APT_PACKAGE[sbx]}"
    if verify_expects sbx && tool_applicable sbx && apt_package_installed "$package"; then
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
    if feature_enabled agent-badge && { verify_expects claude || verify_expects codex; }; then
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
                local portable
                portable="$(portable_gitconfig_path)"
                if profile_exists && profile_load 2>/dev/null && _profile_in_list "${PROFILE[opt-outs]}" no-git; then
                    outcome ok "$section" "$target" "skipped (no-git)"
                elif [[ ! -f "$portable" ]] || ! git config --file "$target" --get-all include.path 2>/dev/null | grep -Fxq "$portable"; then
                    outcome convergence "$section" "$target" "lacks the portable include ($portable)"
                elif ! cmp -s <(render_portable_gitconfig "$source_path") "$portable"; then
                    outcome convergence "$section" "$portable" "differs from what setup renders (bin/diff-config gitconfig shows how)"
                else
                    outcome ok "$section" "$target" "includes $portable, as setup renders it"
                fi
                ;;
        esac
    done < <(printf '%s\n' "${!CONFIG_MAP[@]}" | LC_ALL=C sort)
    # What setup deployed from a source that has since left the manifest.
    local kind identity source run
    while IFS=$'\t' read -r target kind identity source run; do
        [[ -n "$target" && -z "${CONFIG_MAP[$source]+x}" ]] || continue
        outcome convergence "$section" "$target" "its source $source left the manifest; setup retires it if unchanged"
    done < <(deployed_entries 2>/dev/null)
}

verify_ai() {
    local section=AI component
    for component in codex claude; do
        verify_expects "$component" || continue
        if "$DOTFILES_DIR/bin/ai-config" "$component" --check --plugins >/dev/null 2>&1; then
            outcome ok "$section" "$component settings" "portable settings applied"
        else
            outcome convergence "$section" "$component settings" "portable settings need reconciliation (bin/ai-config $component)"
        fi
    done
}

# Neovim's plugins, where Neovim is expected (the dev tier): vim-plug and
# each plugin at its pin. A missing Neovim is reported under Components.
verify_editor_plugins() {
    local section="Editor plugins" out rc=0 line
    verify_expects neovim && command -v nvim >/dev/null 2>&1 || return 0
    out="$(NO_COLOR=1 "$DOTFILES_DIR/bin/install-editor-plugins" --check 2>&1)" || rc=$?
    case "$rc" in
        0) outcome ok "$section" plugins "vim-plug and every plugin at its pin" ;;
        1)
            while IFS= read -r line; do
                [[ "$line" != *"Would "* ]] || outcome convergence "$section" plugins "${line#*Would }"
            done <<< "$out"
            ;;
        *) outcome incomplete "$section" plugins "the check failed: $(tail -n1 <<< "$out")" ;;
    esac
    # What the check leaves alone: a foreign vim-plug, a changed checkout.
    while IFS= read -r line; do
        [[ "$line" != *"left alone"* && "$line" != *"stays at"* ]] || outcome advisory "$section" plugins "${line#\[WARN\] }"
    done <<< "$out"
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
    if { grep -Fxq docker <<< "$expected" || [[ "$VERIFY_SMOKE" == true ]]; } && tool_applicable docker; then
        _verify_host_section=Docker docker_verify_checks true
    fi
    if { grep -Fxq sbx <<< "$expected" || [[ "$VERIFY_SMOKE" == true ]]; } && tool_applicable sbx; then
        _verify_host_section="Local sandboxes" work_verify_checks true
    fi
    if grep -Fxq tailscale <<< "$expected"; then
        _verify_host_section=Tailscale tail_verify_checks true
    fi
}

# WezTerm runs on Windows from a copy of configs/wezterm.lua, which sends its
# revision stamp over SSH (lib/wezterm.sh). Inside tmux the session's value,
# updated at each attach, is the current one; a pane keeps what it started
# with. Nothing to compare without a stamp or an SSH session.
verify_wezterm() {
    local section=Terminal want have="${LC_TAFK_WEZTERM:-}" line
    want="$(wezterm_revision_in "$DOTFILES_DIR/configs/wezterm.lua")" || return 0
    if [[ -n "${TMUX:-}" ]] && line="$(tmux show-environment LC_TAFK_WEZTERM 2>/dev/null)"; then
        have=""
        [[ "$line" != LC_TAFK_WEZTERM=* ]] || have="${line#*=}"
    fi
    if [[ -z "$have" ]]; then
        [[ -n "${SSH_CONNECTION:-}" ]] || return 0
        outcome advisory "$section" "WezTerm config" "not reported over SSH; the Windows ssh config's Host block needs SendEnv LC_TAFK_WEZTERM"
    elif [[ "$have" == "$want" ]]; then
        outcome ok "$section" "WezTerm config" "the copy on Windows matches configs/wezterm.lua ($want)"
    else
        outcome advisory "$section" "WezTerm config" "the copy on Windows ($have) is not configs/wezterm.lua ($want); copy it to %USERPROFILE%\\.wezterm.lua"
    fi
}

# The machine's default Git identity and this checkout's pre-commit hook.
# Identity is not setup's (git profile sets it), and the hook is a convenience
# for working on the checkout, so neither fails verify.
verify_git() {
    local section=Git name email common hook resolved
    name="$(git config --global --includes --get user.name 2>/dev/null || true)"
    email="$(git config --global --includes --get user.email 2>/dev/null || true)"
    if [[ -n "$name" && -n "$email" ]]; then
        outcome ok "$section" user "$name <$email>"
    else
        # With user.useConfigOnly, commits are refused until it is set.
        outcome advisory "$section" user "not configured; commits are refused (run: git profile add NAME --default)"
    fi
    if profile_exists && profile_load 2>/dev/null && _profile_in_list "${PROFILE[opt-outs]}" no-hooks; then
        outcome ok "$section" "pre-commit hook" "skipped (no-hooks)"
        return
    fi
    common="$(git -C "$DOTFILES_DIR" rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)"
    hook="${common:-$DOTFILES_DIR/.git}/hooks/pre-commit"
    if [[ -L "$hook" ]]; then
        resolved="$(readlink -f "$hook" 2>/dev/null || true)"
        if [[ "$resolved" == "$DOTFILES_DIR/hooks/"* ]]; then
            outcome ok "$section" "pre-commit hook" "installed (links to hooks/pre-commit)"
        else
            outcome advisory "$section" "pre-commit hook" "present, but not this checkout's"
        fi
    elif [[ -f "$hook" ]] && head -n4 "$hook" 2>/dev/null | grep -q "Installed by bin/install-git-hooks"; then
        outcome ok "$section" "pre-commit hook" "installed (a copy)"
    elif [[ -f "$hook" ]]; then
        outcome advisory "$section" "pre-commit hook" "present, but not this checkout's"
    else
        outcome advisory "$section" "pre-commit hook" "not installed (run: bin/install-git-hooks)"
    fi
}

# WSL's clipboard commands, which setup installs on WSL.
verify_wsl() {
    is_wsl || return 0
    if [[ -x "$HOME/.local/bin/pbcopy" ]]; then
        outcome ok WSL clipboard "pbcopy and pbpaste"
    else
        outcome convergence WSL clipboard "pbcopy and pbpaste are not installed; setup installs them"
    fi
}

verify_environment() {
    local section=Environment theme tmux_version file editor_files=""
    if [[ -f "$HOME/.gitconfig" ]]; then
        if [[ "$(git config --global --includes --get delta.syntax-theme 2>/dev/null || true)" == ansi ]]; then
            outcome ok "$section" delta "palette-based colors"
        else
            outcome convergence "$section" delta "the Git config lacks the palette-based delta settings"
        fi
    fi
    # The Python keys runs on (lib/python.sh), where uv is installed to provide one.
    if verify_expects uv; then
        local python
        if python="$(dotfiles_python_find)"; then
            outcome ok "$section" "Python $DOTFILES_PYTHON_MIN+" "$python, for keys"
        else
            outcome convergence "$section" "Python $DOTFILES_PYTHON_MIN+" "none; setup installs one with uv (dotfiles apply)"
        fi
    fi
    # An invalid theme state is reported with the rest of the state files.
    if feature_enabled theme; then
        theme="$("$DOTFILES_DIR/bin/theme-switcher" --current 2>/dev/null | sed -n 's/^global: //p' || true)"
        outcome ok "$section" theme "${theme:-unknown}"
        tmux_version="$(tmux -V 2>/dev/null | awk '{print $2}' | sed 's/[^0-9.].*$//' || true)"
        if [[ -n "$tmux_version" ]] && ! version_gte "$tmux_version" 3.3; then
            outcome advisory "$section" theme "tmux $tmux_version: themes color tmux itself, but programs keep the terminal palette (needs 3.3+)"
        fi
    else
        outcome ok "$section" theme "feature disabled"
    fi
    # EDITOR has one source, shell/env.sh; a tool file that sets it competes.
    for file in "$DOTFILES_DIR"/shell/tools/*.sh; do
        [[ -f "$file" ]] || continue
        grep -v '^[[:space:]]*#' "$file" 2>/dev/null | grep -q '^[[:space:]]*export EDITOR' \
            && editor_files+=" ${file##*/}"
    done
    if [[ -z "$editor_files" ]]; then
        outcome ok "$section" EDITOR "set only in shell/env.sh"
    else
        outcome advisory "$section" EDITOR "also set in${editor_files}; only shell/env.sh should set it"
    fi
}

# What an agent's non-interactive login shell carries: no dotfiles
# interactive or private functions, no aliases, no BASH_ENV, and a PATH
# without duplicates. This checks our boundary, not any harness's snapshot:
# functions from other profiles are left alone, since their presence alone
# costs nothing measurable per command. One login shell answers all four.
verify_agent_shell() {
    local section="Agent shell" report bash_env agent_path aliases leaked count total unique
    report="$(bash -lc 'printf "%s\n%s\n" "${BASH_ENV:-}" "$PATH"; alias | wc -l; compgen -A function' \
        2>/dev/null </dev/null || true)"
    bash_env="$(sed -n 1p <<< "$report")"
    agent_path="$(sed -n 2p <<< "$report")"
    aliases="$(sed -n '3s/[^0-9]//gp' <<< "$report")"
    leaked="$(tail -n +4 <<< "$report" | grep -E '^(_dotfiles_|reload$|proj$|theme$|fmt$|lint$|lintf$)' || true)"
    if [[ -z "$leaked" ]]; then
        outcome ok "$section" functions "no dotfiles interactive or private functions"
    else
        count="$(wc -l <<< "$leaked")"
        outcome advisory "$section" functions "$count dotfiles interactive or private function(s): $(paste -sd' ' - <<< "$leaked")"
    fi
    if (( ${aliases:-0} == 0 )); then
        outcome ok "$section" aliases "none"
    else
        outcome advisory "$section" aliases "$aliases alias(es)"
    fi
    if [[ -z "$bash_env" ]]; then
        outcome ok "$section" BASH_ENV "unset (a bare bash -c stays free)"
    else
        outcome advisory "$section" BASH_ENV "set to $bash_env: every bash -c sources it, taxing every harness"
    fi
    total="$(tr ':' '\n' <<< "$agent_path" | grep -c . || true)"
    unique="$(tr ':' '\n' <<< "$agent_path" | grep . | sort -u | wc -l)"
    if (( total == unique )); then
        outcome ok "$section" PATH "$total entries, no duplicates"
    else
        outcome advisory "$section" PATH "$total entries, $unique unique"
    fi
}

# Newer upstream releases for pinned tools (network), from check-updates'
# records.
verify_upstream() {
    "$DOTFILES_DIR/bin/check-updates" --records 2>/dev/null \
        || outcome incomplete Upstream "release check" "check-updates failed"
}
