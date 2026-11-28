#!/bin/bash
# The machine profile: what this machine should have, as opposed to the
# component ledger, which records what happened. Data and pure helpers; the
# caller holds the operation lock (lib/operation.sh) around profile_save.
#
# ~/.local/state/dotfiles/profile is schema-versioned TSV with these keys:
#   tier            config | bash | dev | work
#   capabilities    comma-separated orthogonal selections (rdp, tail, azure, ...)
#   ai              comma-separated AI tools, where all stands for the core
#                   ones (--ai; optional ones are named: all,pi) | - (none)
#   ai.exclude      core AI tools left out of all (dotfiles profile --remove)
#   opt-outs        no-git, no-hooks
# Feature toggles (theme, agent-badge) stay in preferences.tsv.
#
# Changing the profile changes what is managed, never what is removed.

[[ -n "${_DOTFILES_PROFILE_LOADED:-}" ]] && return 0
_DOTFILES_PROFILE_LOADED=1

DOTFILES_PROFILE_FILE="$DOTFILES_STATE_DIR/profile"
DOTFILES_PROFILE_SCHEMA=1
PROFILE_KEYS=(tier capabilities ai ai.exclude opt-outs)
# Keys an earlier profile may hold, ignored on load and dropped on the next
# save: editor-plugins (the dev tier includes the plugins now).
PROFILE_RETIRED_KEYS=(editor-plugins)
PROFILE_OPT_OUTS=(no-git no-hooks)
declare -A PROFILE=()

profile_exists() { [[ -f "$DOTFILES_PROFILE_FILE" ]]; }

profile_reset() {
    PROFILE=([tier]=config [capabilities]="" [ai]="" [ai.exclude]="" [opt-outs]="")
}

_profile_tier_rank() {
    case "$1" in config) echo 0 ;; bash) echo 1 ;; dev) echo 2 ;; work) echo 3 ;; *) return 1 ;; esac
}

# Orthogonal capabilities that can be selected, from the registry: every
# capability except ai (its tools are listed by name) and agent-badge (a
# feature preference).
profile_known_capabilities() {
    local name capability
    for name in "${!TOOL_CAPABILITIES[@]}"; do
        for capability in ${TOOL_CAPABILITIES[$name]//,/ }; do
            [[ "$capability" == ai || "$capability" == agent-badge ]] || printf '%s\n' "$capability"
        done
    done | LC_ALL=C sort -u
}

profile_ai_tool_names() { tools_for_capability ai; }

_profile_in_list() { [[ ",$1," == *",$2,"* ]]; }

# Whether the profile selects the core AI tools as all.
profile_ai_all() { _profile_in_list "${PROFILE[ai]}" all; }

# The core AI tools as all; the optional ones named stay.
profile_ai_set_all() {
    local item list=all
    for item in ${PROFILE[ai]//,/ }; do
        [[ -z "${TOOL_OPTIONAL[$item]:-}" ]] || list+=",$item"
    done
    PROFILE[ai]="$list" PROFILE[ai.exclude]=""
}

# profile_ai_add TOOL / profile_ai_remove TOOL: manage one AI tool or stop,
# under all through ai.exclude for a core one.
profile_ai_add() {
    if profile_ai_all && [[ -z "${TOOL_OPTIONAL[$1]:-}" ]]; then
        PROFILE[ai.exclude]="$(_profile_list_remove "${PROFILE[ai.exclude]}" "$1")"
    else
        PROFILE[ai]="$(_profile_list_add "${PROFILE[ai]}" "$1")"
    fi
}

profile_ai_remove() {
    if profile_ai_all && [[ -z "${TOOL_OPTIONAL[$1]:-}" ]]; then
        PROFILE[ai.exclude]="$(_profile_list_add "${PROFILE[ai.exclude]}" "$1")"
    else
        PROFILE[ai]="$(_profile_list_remove "${PROFILE[ai]}" "$1")"
    fi
}

# The optional AI tools named beside all, comma-separated.
_profile_ai_extras() {
    local item out=""
    for item in ${PROFILE[ai]//,/ }; do
        [[ "$item" == all || -z "${TOOL_OPTIONAL[$item]:-}" ]] || out+="${out:+,}$item"
    done
    printf '%s' "$out"
}

_profile_list_add() {
    local list="$1" item="$2"
    _profile_in_list "$list" "$item" && { printf '%s' "$list"; return; }
    printf '%s' "${list:+$list,}$item"
}

_profile_list_remove() {
    local list=",$1," item="$2"
    list="${list//,$item,/,}"
    list="${list#,}"; list="${list%,}"
    printf '%s' "$list"
}

# Sorted in a stable order, so saving the same intent writes the same file.
_profile_list_sorted() {
    [[ -n "$1" ]] || return 0
    printf '%s\n' "${1//,/$'\n'}" | LC_ALL=C sort -u | paste -sd, -
}

# Validate PROFILE's values; prints the first problem.
profile_check() {
    local item known
    _profile_tier_rank "${PROFILE[tier]}" >/dev/null || { printf 'unknown tier: %s\n' "${PROFILE[tier]}"; return 1; }
    known=",$(profile_known_capabilities | paste -sd, -),"
    for item in ${PROFILE[capabilities]//,/ }; do
        [[ "$known" == *",$item,"* ]] || { printf 'unknown capability: %s\n' "$item"; return 1; }
    done
    known=",$(profile_ai_tool_names | paste -sd, -),all,"
    for item in ${PROFILE[ai]//,/ }; do
        [[ "$known" == *",$item,"* ]] || { printf 'unknown AI tool: %s\n' "$item"; return 1; }
    done
    known="${known%all,}"
    for item in ${PROFILE[ai.exclude]//,/ }; do
        [[ "$known" == *",$item,"* ]] || { printf 'unknown AI tool: %s\n' "$item"; return 1; }
    done
    for item in ${PROFILE[opt-outs]//,/ }; do
        [[ " ${PROFILE_OPT_OUTS[*]} " == *" $item "* ]] || { printf 'unknown opt-out: %s\n' "$item"; return 1; }
    done
}

# Load the profile into PROFILE; defaults when there is none.
profile_load() {
    profile_reset
    profile_exists || return 0
    local key value problem
    { IFS=$'\t' read -r key value && [[ "$key" == schema && "$value" == "$DOTFILES_PROFILE_SCHEMA" ]]; } \
        < "$DOTFILES_PROFILE_FILE" || { printf 'Error: unsupported profile schema: %s\n' "$DOTFILES_PROFILE_FILE" >&2; return 1; }
    while IFS=$'\t' read -r key value; do
        [[ "$key" == schema || -z "$key" || " ${PROFILE_RETIRED_KEYS[*]} " == *" $key "* ]] && continue
        [[ " ${PROFILE_KEYS[*]} " == *" $key "* ]] || { printf 'Error: unknown profile key: %s\n' "$key" >&2; return 1; }
        [[ "$value" != - ]] || value=""
        PROFILE[$key]="$value"
    done < "$DOTFILES_PROFILE_FILE"
    problem="$(profile_check)" || { printf 'Error: invalid profile: %s\n' "$problem" >&2; return 1; }
}

# Write PROFILE atomically.
profile_save() {
    local problem key
    problem="$(profile_check)" || { printf 'Error: refusing to save an invalid profile: %s\n' "$problem" >&2; return 1; }
    for key in capabilities ai ai.exclude opt-outs; do PROFILE[$key]="$(_profile_list_sorted "${PROFILE[$key]}")"; done
    local content
    content="$(
        printf 'schema\t%s\n' "$DOTFILES_PROFILE_SCHEMA"
        for key in "${PROFILE_KEYS[@]}"; do printf '%s\t%s\n' "$key" "${PROFILE[$key]:--}"; done
    )"
    # Unchanged intent touches nothing, not even a temporary file.
    [[ -f "$DOTFILES_PROFILE_FILE" && "$(<"$DOTFILES_PROFILE_FILE")" == "$content" ]] && return 0
    (
        _state_lock_acquire || exit 1
        trap _state_lock_release EXIT INT TERM
        local staged
        staged="$(mktemp "$DOTFILES_STATE_DIR/profile.tmp.XXXXXX")" || exit 1
        printf '%s\n' "$content" > "$staged" || exit 1
        _state_commit_file "$staged" "$DOTFILES_PROFILE_FILE"
    )
}

# The AI tools the profile selects, one per line.
profile_ai_tools() {
    local tool
    if profile_ai_all; then
        while IFS= read -r tool; do
            _profile_in_list "${PROFILE[ai.exclude]}" "$tool" || printf '%s\n' "$tool"
        done < <(ai_core_tools)
        tool="$(_profile_ai_extras)"
        [[ -z "$tool" ]] || printf '%s\n' "${tool//,/$'\n'}"
    elif [[ -n "${PROFILE[ai]}" ]]; then
        printf '%s\n' "${PROFILE[ai]//,/$'\n'}"
    fi
}

# The setup.sh arguments that apply the whole profile, one per line.
profile_setup_args() {
    local item
    printf -- '--%s\n' "${PROFILE[tier]}"
    for item in ${PROFILE[capabilities]//,/ }; do printf -- '--%s\n' "$item"; done
    if profile_ai_all && [[ -z "${PROFILE[ai.exclude]}" ]]; then
        printf -- '--ai\n'
        item="$(_profile_ai_extras)"
        [[ -z "$item" ]] || printf -- '--%s\n' "${item//,/$'\n--'}"
    else
        while IFS= read -r item; do printf -- '--%s\n' "$item"; done < <(profile_ai_tools)
    fi
    for item in ${PROFILE[opt-outs]//,/ }; do printf -- '--%s\n' "$item"; done
}

profile_describe() {
    local ai="${PROFILE[ai]:-none}" extras
    if profile_ai_all; then
        ai=all extras="$(_profile_ai_extras)"
        [[ -z "${PROFILE[ai.exclude]}" ]] || ai="all except ${PROFILE[ai.exclude]//,/, }"
        [[ -z "$extras" ]] || ai+=" plus ${extras//,/, }"
    fi
    printf 'tier            %s\n' "${PROFILE[tier]}"
    printf 'capabilities    %s\n' "$(printf '%s' "${PROFILE[capabilities]:-none}" | sed 's/,/, /g')"
    printf 'ai              %s\n' "$(printf '%s' "$ai" | sed 's/,/, /g')"
    printf 'opt-outs        %s\n' "$(printf '%s' "${PROFILE[opt-outs]:-none}" | sed 's/,/, /g')"
}

# profile_merge TIER CAPABILITIES AI_MODE AI_TOOLS OPT_OUTS: fold one setup
# run's flags into PROFILE. Flags only add: a higher tier raises it,
# capabilities and AI tools join (and leave ai.exclude), opt-outs set.
# Nothing is lowered or removed. AI_MODE is all (--ai, with any per-tool
# flags in AI_TOOLS), some, or empty. Each addition
# is appended to PROFILE_CHANGES as "+ X".
PROFILE_CHANGES=()
profile_merge() {
    local tier="$1" capabilities="$2" ai_mode="$3" ai_tools="$4" opt_outs="$5" item
    PROFILE_CHANGES=()
    if (( $(_profile_tier_rank "$tier") > $(_profile_tier_rank "${PROFILE[tier]}") )); then
        PROFILE_CHANGES+=("+ tier $tier")
        PROFILE[tier]="$tier"
    fi
    for item in ${capabilities//,/ }; do
        _profile_in_list "${PROFILE[capabilities]}" "$item" && continue
        PROFILE_CHANGES+=("+ $item")
        PROFILE[capabilities]="$(_profile_list_add "${PROFILE[capabilities]}" "$item")"
    done
    if [[ "$ai_mode" == all ]]; then
        if ! profile_ai_all || [[ -n "${PROFILE[ai.exclude]}" ]]; then PROFILE_CHANGES+=("+ ai (all)"); fi
        profile_ai_set_all
    fi
    if [[ -n "$ai_mode" ]]; then
        local selected
        selected=",$(profile_ai_tools | paste -sd, -),"
        for item in ${ai_tools//,/ }; do
            [[ "$selected" != *",$item,"* ]] || continue
            profile_ai_add "$item"
            selected+="$item,"
            PROFILE_CHANGES+=("+ $item")
        done
    fi
    for item in ${opt_outs//,/ }; do
        _profile_in_list "${PROFILE[opt-outs]}" "$item" && continue
        PROFILE_CHANGES+=("+ $item")
        PROFILE[opt-outs]="$(_profile_list_add "${PROFILE[opt-outs]}" "$item")"
    done
}

# A profile derived from what is installed: only components dotfiles or the
# package manager installed count, never external tools. Ownership is
# observed (lib/observe.sh), not read from the ledger, whose rows an older
# checkout may have written wrong. Fills PROFILE.
profile_propose() {
    local name obs rc tier=config tool capability
    local -a ai_present=()
    profile_reset
    while IFS= read -r name; do
        rc=0
        obs="$(observe_component "$name" 2>/dev/null)" || rc=$?
        (( rc == 0 || rc == 3 )) || continue
        [[ "$(observation_field applicable <<< "$obs")" == yes && -n "$(observation_field path <<< "$obs")" ]] || continue
        case "$(observation_field owner <<< "$obs")" in dotfiles|package-manager) ;; *) continue ;; esac
        if [[ -n "${TOOL_TIER[$name]:-}" ]] \
           && (( $(_profile_tier_rank "${TOOL_TIER[$name]}") > $(_profile_tier_rank "$tier") )); then
            tier="${TOOL_TIER[$name]}"
        fi
        for capability in ${TOOL_CAPABILITIES[$name]:+${TOOL_CAPABILITIES[$name]//,/ }}; do
            case "$capability" in
                ai) ai_present+=("$name") ;;
                agent-badge) ;;
                *) PROFILE[capabilities]="$(_profile_list_add "${PROFILE[capabilities]}" "$capability")" ;;
            esac
        done
    done < <(printf '%s\n' "${!TOOL_BINARY[@]}" | LC_ALL=C sort)
    PROFILE[tier]="$tier"
    local core=0
    for tool in "${ai_present[@]}"; do [[ -n "${TOOL_OPTIONAL[$tool]:-}" ]] || core=$((core + 1)); done
    (( core == 0 || core != $(ai_core_tools | wc -l) )) || PROFILE[ai]=all
    for tool in "${ai_present[@]}"; do profile_ai_add "$tool"; done
}
