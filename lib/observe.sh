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
# Other components run their version flag under a timeout, from / with
# RUSTUP_TOOLCHAIN unset and rustup auto-install off, so a project's toolchain
# or Node version cannot answer and nothing is installed. Nothing here launches
# a login shell, writes files, or changes services.

[[ -n "${_DOTFILES_OBSERVE_LOADED:-}" ]] && return 0
_DOTFILES_OBSERVE_LOADED=1

# The first dotted version number on stdin (tmux's 3.7c included).
version_token() {
    grep -oE '[0-9]+(\.[0-9]+)+[a-z]?' | head -n1
}

# What a component should be, as KIND:VALUE, or - when versions are not pinned.
component_want() {
    local name="$1" tag
    if [[ "${TOOL_METHOD[$name]:-}" == eget ]]; then
        tag="$(versions_field "$name" want 2>/dev/null)" && [[ -n "$tag" ]] && { printf 'tag:%s\n' "$tag"; return; }
        printf -- '-\n'; return
    fi
    case "$name" in
        neovim) printf 'version:%s\n' "$NVIM_VERSION" ;;
        tmux) printf 'version:%s\n' "$TMUX_VERSION" ;;
        eget) printf 'version:%s\n' "$EGET_VERSION" ;;
        nvm) printf 'version:%s\n' "$NVM_VERSION" ;;
        node) printf 'version:%s (npm %s)\n' "$(versions_field node want | sed 's/^v//')" "$(versions_field npm want any)" ;;
        rust) printf 'version:%s\n' "$(versions_field rust want any)" ;;
        aws-cli) printf 'version:%s\n' "$(versions_field aws-cli want)" ;;
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
    local line recorded_owner="" recorded_path="" probe_timeout="${DOTFILES_OBSERVE_TIMEOUT:-${TOOL_TIMEOUT[$name]:-10}}"

    want="$(component_want "$name")"
    if ! tool_applicable "$name"; then
        applicable=no
        reason="$(_observe_reason "$name")"
        if [[ -n "${TOOL_UBUNTU_VERSIONS[$name]:-}" && -z "${DOTFILES_TEST_OS_VERSION:-}" \
              && ! -r "${DOTFILES_OS_RELEASE:-/etc/os-release}" ]]; then
            applicable=unknown reason="os-release unreadable"; complete=3
        fi
    fi

    # Where the component is: the managed copy first for eget tools, nvm's
    # default release for Node, then PATH, then a registered path for
    # components with no command (nvm).
    if [[ "$method" == eget && -x "$HOME/.local/bin/$binary" ]]; then
        path="$HOME/.local/bin/$binary"
    elif [[ "$name" == node ]]; then
        path="$(node_default_dir 2>/dev/null)/bin/node" || path=""
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
    [[ -z "$line" ]] || IFS=$'\t' read -r _ _ recorded_owner _ _ recorded_path _ _ <<< "$line"

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
            output="$(_observe_probe "$probe_timeout" "$probe" "${TOOL_VERSION_FLAG[$name]:---version}")" || rc=$?
            if (( rc == 124 )); then
                runnable=unknown; complete=3
            elif (( rc == 0 )); then
                runnable=yes
            fi
            local version
            version="$(printf '%s\n' "$output" | version_line | version_token || true)"
            [[ -z "$version" ]] || identity="version:$version"
        fi
        # Node is its locked release when its binary's digest is the lock's,
        # and carries the npm version it has now (the bundled one, or drift).
        if [[ "$name" == node ]]; then
            local npm_version
            npm_version="$(sed -n 's/^[[:space:]]*"version":[[:space:]]*"\([^"]*\)".*/\1/p' \
                "${path%/bin/node}/lib/node_modules/npm/package.json" 2>/dev/null | head -n1)"
            # Another release is its version; the pinned version in another
            # build is its digest.
            local release="${path%/bin/node}" node_want
            release="${release##*/v}"
            node_want="$(versions_field node want | sed 's/^v//')"
            identity="sha256:$(sha256sum "$path" | awk '{print $1}')"
            if [[ "$(versions_field node identity 2>/dev/null)" == "$identity" ]]; then
                identity="version:$node_want (npm ${npm_version:-missing})"
            elif [[ "$release" != "$node_want" ]]; then
                identity="version:$release (npm ${npm_version:-missing})"
            fi
        fi
        # The Rust toolchain is rustup's default, never a directory override.
        if [[ "$name" == rust && -x "$(dirname "$path")/rustup" ]]; then
            local toolchain
            toolchain="$(_observe_probe "$probe_timeout" "$(dirname "$path")/rustup" default | awk 'NR == 1 { print $1 }')"
            toolchain="$(sed -E 's/-(x86_64|aarch64)-unknown-linux-(gnu|musl)$//' <<< "$toolchain")"
            if [[ "$toolchain" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]]; then identity="version:$toolchain"
            elif [[ -n "$toolchain" && "$toolchain" != no ]]; then identity="toolchain:$toolchain"
            else identity="-"
            fi
        fi
        # An eget tool is its locked release when its digest is the lock's.
        if [[ "$method" == eget && -f "$path" ]]; then
            local digest
            digest="$(sha256sum "$path" | awk '{print $1}')"
            identity="sha256:$digest"
            [[ "$want" == - || "$(versions_field "$name" identity 2>/dev/null)" != "sha256:$digest" ]] \
                || identity="$want"
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

# _observe_probe TIMEOUT COMMAND ARGS...: run a version probe from a neutral
# directory, so no project override answers and nothing is installed.
_observe_probe() {
    local seconds="$1"; shift
    (cd / && env -u RUSTUP_TOOLCHAIN RUSTUP_AUTO_INSTALL=0 timeout "$seconds" "$@" 2>/dev/null </dev/null)
}

# observation_field KEY < OBSERVATION
observation_field() {
    awk -v key="$1" 'index($0, key "=") == 1 { print substr($0, length(key) + 2); exit }'
}
