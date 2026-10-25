#!/bin/bash
# Component observation: what is installed, read without side effects.
#
# observe_component NAME prints one key=value per line on stdout:
#   applicable=yes|no|unknown  reason=...
#   path=...                   owner=dotfiles|package-manager|external|none
#   identity=KIND:VALUE        want=KIND:VALUE (or -)
#   runnable=yes|no|unknown    companions=ok|missing:LIST
#   ready=yes|no|unknown       ready-reason=...
# and exits 0 when the observation is complete, 3 when it could not be made
# (unreadable state, a probe that timed out, unknown applicability). The engine,
# not the installer, turns an observation into a decision.
#
# Probe rules: an APT component is never executed; its identity is the
# package version (running `az --version` or `gcloud --version` writes state).
# Other components run their version flag under a timeout. Nothing here launches
# a login shell, writes files, or changes services.

[[ -n "${_DOTFILES_OBSERVE_LOADED:-}" ]] && return 0
_DOTFILES_OBSERVE_LOADED=1

# The first dotted version number on stdin (tmux's 3.7c included).
version_token() {
    grep -oE '[0-9]+(\.[0-9]+)+[a-z]?' | head -n1
}

# The eget.toml tag pinned for an eget tool.
eget_pinned_tag() {
    local name="$1" config="$DOTFILES_DIR/eget.toml" slug
    slug="${TOOL_EGET_REPO[$name]:-}"
    if [[ -z "$slug" ]]; then
        slug="$(grep -Po '^\["\K[^"]+' "$config" 2>/dev/null | awk -F/ -v name="$name" '$2 == name { print; exit }')"
    fi
    [[ -n "$slug" ]] || return 1
    awk -v section="[\"$slug\"]" '
        $0 == section { active=1; next }
        active && /^\[/ { exit }
        active && /^[[:space:]]*tag[[:space:]]*=/ {
            line=$0; sub(/^[^"]*"/, "", line); sub(/".*$/, "", line); print line; exit
        }
    ' "$config"
}

# What a component should be, as KIND:VALUE, or - when versions are not pinned.
component_want() {
    local name="$1" tag
    if [[ "${TOOL_METHOD[$name]:-}" == eget ]]; then
        tag="$(eget_pinned_tag "$name")" && [[ -n "$tag" ]] && { printf 'tag:%s\n' "$tag"; return; }
        printf -- '-\n'; return
    fi
    case "$name" in
        neovim) printf 'version:%s\n' "$NVIM_VERSION" ;;
        tmux) printf 'version:%s\n' "$TMUX_VERSION" ;;
        eget) printf 'version:%s\n' "$EGET_VERSION" ;;
        nvm) printf 'version:%s\n' "$NVM_VERSION" ;;
        sbx) printf 'apt:%s\n' "$SBX_VERSION" ;;
        *) printf -- '-\n' ;;
    esac
}

_observe_reason() {
    local name="$1" arch platform
    arch="$(tool_arch 2>/dev/null || true)"
    platform="$(tool_platform)"
    case ",${TOOL_ARCHES[$name]:-}," in *",$arch,"*) ;; *) printf 'architecture %s\n' "${arch:-unknown}"; return ;; esac
    case "${TOOL_PLATFORM[$name]:-ubuntu}:$platform" in
        native-ubuntu:wsl) printf 'needs native Ubuntu\n'; return ;;
        wsl:*) [[ "$platform" == wsl ]] || { printf 'WSL only\n'; return; } ;;
    esac
    printf 'Ubuntu release (supported: %s)\n' "${TOOL_UBUNTU_VERSIONS[$name]:-any}"
}

observe_component() {
    local name="$1" complete=0
    [[ -n "${TOOL_BINARY[$name]:-}" ]] || { printf 'observe: unknown component: %s\n' "$name" >&2; return 2; }
    local binary="${TOOL_BINARY[$name]}" method="${TOOL_METHOD[$name]}"
    local applicable=yes reason="" path="" owner=none identity="-" want runnable=no companions=ok ready=no ready_reason=""
    local line recorded_owner="" recorded_path="" recorded_note="" probe_timeout="${DOTFILES_OBSERVE_TIMEOUT:-${TOOL_TIMEOUT[$name]:-10}}"

    want="$(component_want "$name")"
    if ! tool_applicable "$name"; then
        applicable=no
        reason="$(_observe_reason "$name")"
        if [[ -n "${TOOL_UBUNTU_VERSIONS[$name]:-}" && -z "${DOTFILES_TEST_OS_VERSION:-}" \
              && ! -r "${DOTFILES_OS_RELEASE:-/etc/os-release}" ]]; then
            applicable=unknown reason="os-release unreadable"; complete=3
        fi
    fi

    # Where the component is: the managed copy first for eget tools, then PATH,
    # then a registered path for components with no command (nvm).
    if [[ "$method" == eget && -x "$HOME/.local/bin/$binary" ]]; then
        path="$HOME/.local/bin/$binary"
    else
        path="$(command -v "$binary" 2>/dev/null || true)"
    fi
    if [[ -z "$path" && "${TOOL_VERIFY[$name]:-}" == file-nonempty* ]]; then
        line="${TOOL_VERIFY[$name]#file-nonempty }"
        [[ ! -s "$line" ]] || path="$(dirname "$line")"
    fi
    [[ -z "$path" ]] || path="$(component_path "$path")"

    if ! line="$(ledger_line "$name" 2>/dev/null)"; then
        if [[ -f "$DOTFILES_LEDGER_FILE" ]] && ! _state_validate_file "$DOTFILES_LEDGER_FILE" ledger 8 2>/dev/null; then
            complete=3
        fi
        line=""
    fi
    [[ -z "$line" ]] || IFS=$'\t' read -r _ _ recorded_owner _ _ recorded_path recorded_note _ <<< "$line"

    if [[ -n "$path" ]]; then
        if [[ "$method" == apt ]] && apt_package_installed "${TOOL_APT_PACKAGE[$name]:-$name}"; then
            owner=package-manager
        elif [[ "$recorded_owner" == dotfiles ]] && tool_owned_path "$name" "$path" \
             && { [[ "$(realpath -m -- "$recorded_path" 2>/dev/null)" == "$path" ]] || tool_moves_itself "$name"; }; then
            owner=dotfiles
        else
            owner=external
        fi

        # Identity and runnability, by probe rule.
        if [[ "$method" == apt ]]; then
            [[ -x "$path" || -d "$path" ]] && runnable=yes
            if [[ "$owner" == package-manager ]]; then
                identity="apt:$(dpkg-query -W -f='${Version}' "${TOOL_APT_PACKAGE[$name]:-$name}" 2>/dev/null)"
            fi
        elif [[ "$name" == nvm ]]; then
            [[ -s "$path/nvm.sh" ]] && runnable=yes
            identity="$(sed -n 's/^[[:space:]]*"version":[[:space:]]*"\([^"]*\)".*/\1/p' "$path/package.json" 2>/dev/null | head -n1)"
            identity="${identity:+version:$identity}"; identity="${identity:--}"
        else
            local output rc=0 probe="$path"
            [[ ! -d "$path" || -z "${TOOL_RELATIVE_BINARY[$name]:-}" ]] || probe="$path/${TOOL_RELATIVE_BINARY[$name]}"
            output="$(timeout "$probe_timeout" "$probe" "${TOOL_VERSION_FLAG[$name]:---version}" 2>/dev/null </dev/null)" || rc=$?
            if (( rc == 124 )); then
                runnable=unknown; complete=3
            elif (( rc == 0 )); then
                runnable=yes
            fi
            local version
            version="$(printf '%s\n' "$output" | version_line | version_token || true)"
            [[ -z "$version" ]] || identity="version:$version"
        fi
        if [[ "$method" == eget && -f "$path" ]]; then
            local digest pinned_hash=""
            digest="$(sha256sum "$path" | awk '{print $1}')"
            identity="sha256:$digest"
            if [[ "$recorded_note" =~ pin=([^[:space:]]+)\ sha256=([0-9a-f]{64}) ]]; then
                pinned_hash="${BASH_REMATCH[2]}"
                [[ "$pinned_hash" != "$digest" ]] || identity="tag:${BASH_REMATCH[1]}"
            fi
        fi

        local companion missing=""
        for companion in ${TOOL_COMPANIONS[$name]:-}; do
            [[ -x "$(dirname "$path")/$companion" ]] || command -v "$companion" >/dev/null 2>&1 || missing+="${missing:+,}$companion"
        done
        [[ -z "$missing" ]] || companions="missing:$missing"
    fi

    # Readiness: a service component is ready while its unit runs; others when
    # they run.
    local verify_type verify_arg
    read -r verify_type verify_arg <<< "${TOOL_VERIFY[$name]:-command}"
    if [[ "$verify_type" == service-active ]]; then
        if systemctl is-active --quiet "$verify_arg" 2>/dev/null; then ready=yes; else ready=no ready_reason="$verify_arg inactive"; fi
    elif [[ "$runnable" == yes && "$companions" == ok ]]; then
        ready=yes
    elif [[ "$runnable" == unknown ]]; then
        ready=unknown ready_reason="version probe timed out"
    else
        ready=no
        if [[ -z "$path" ]]; then ready_reason="not installed"
        elif [[ "$companions" != ok ]]; then ready_reason="companions ${companions#missing:} missing"
        else ready_reason="does not run"
        fi
    fi

    printf 'applicable=%s\nreason=%s\npath=%s\nowner=%s\nidentity=%s\nwant=%s\nrunnable=%s\ncompanions=%s\nready=%s\nready-reason=%s\n' \
        "$applicable" "$reason" "$path" "$owner" "$identity" "$want" "$runnable" "$companions" "$ready" "$ready_reason"
    return "$complete"
}

# observation_field KEY < OBSERVATION
observation_field() {
    awk -v key="$1" 'index($0, key "=") == 1 { print substr($0, length(key) + 2); exit }'
}
