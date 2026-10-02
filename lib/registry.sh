#!/bin/bash
# Tool registry — single source of truth for all managed tools.
# Sourced by setup.sh (via config.sh), bin/verify, bin/uninstall-tool, and
# bin/cheatsheet. Data and lookup helpers only; no side effects.

[[ -n "${_DOTFILES_REGISTRY_LOADED:-}" ]] && return 0
_DOTFILES_REGISTRY_LOADED=1

# Tools are declared in two tables below and parsed once into the TOOL_*
# associative arrays, which callers read directly (accessor functions would
# fork a subshell per lookup). Treat the arrays as read-only outside tests.
declare -A TOOL_BINARY=() TOOL_METHOD=() TOOL_TIER=() TOOL_CAPABILITIES=()
declare -A TOOL_PLATFORM=() TOOL_ARCHES=() TOOL_UBUNTU_VERSIONS=()
declare -A TOOL_APT_PACKAGE=() TOOL_VERIFY=()
declare -A TOOL_EGET_REPO=() TOOL_UPDATE_SOURCE=() TOOL_RELATIVE_BINARY=()
declare -A TOOL_VERSION_FLAG=() TOOL_TIMEOUT=() TOOL_COMPANIONS=()
declare -A TOOL_OWNERSHIP_ROOTS=() TOOL_UPDATE_CONTRACT=() TOOL_PATHS=()
declare -A TOOL_REMOVAL_MODE=() TOOL_REMOVAL_REQUIRES_SUDO=() TOOL_REMOVAL_INSTRUCTIONS=()
# Problems found while parsing; tests/registry.sh requires this to stay empty.
declare -a REGISTRY_ERRORS=()

# Core table: one row per tool. "-" takes the default.
#   binary        command on PATH (default: the tool name)
#   method        eget | apt | installer | external
#   tier          minimum cumulative tier: bash | dev | work. Bash-tier tools
#                 must install without root. Capability-only tools have none.
#   capabilities  comma-separated orthogonal selections (see setup.sh)
#   platform      ubuntu (default; native Ubuntu and WSL) | native-ubuntu | wsl
#   arches        comma-separated (default: x86_64,aarch64). Explicit so
#                 selection-only CI can validate ARM without executing it.
#   ubuntu        comma-separated supported releases (default: any)
#   apt           APT package name
#   verify        how presence is checked (tool_is_present):
#                   command [EXTRA...]  binary, companions, and EXTRA on PATH
#                                       (default)
#                   runs                also exits 0 with its version flag
#                                       (and timeout); for launchers that can
#                                       be present but broken
#                   service-active UNIT the systemd unit is running
#                   file-nonempty FILE  FILE exists and is not empty
#                   function NAME       a predicate defined in this file
_REGISTRY_TOOLS="
# name          binary          method     tier  capabilities  platform       arches  ubuntu             apt               verify
starship        -               eget       bash  -             -              -       -                  -                 -
eza             -               eget       bash  -             -              -       -                  -                 -
fzf             -               eget       bash  -             -              -       -                  -                 -
zoxide          -               eget       bash  -             -              -       -                  -                 -
delta           -               eget       bash  -             -              -       -                  -                 -
btop            -               eget       bash  -             -              -       -                  -                 -
gdu             -               eget       bash  -             -              -       -                  -                 -
glow            -               eget       bash  -             -              -       -                  -                 -
lazygit         -               eget       bash  -             -              -       -                  -                 -
gh              -               eget       bash  -             -              -       -                  -                 -
uv              -               eget       bash  -             -              -       -                  -                 -
bat             -               eget       bash  -             -              -       -                  -                 -
fd              -               eget       bash  -             -              -       -                  -                 -
ripgrep         rg              eget       bash  -             -              -       -                  -                 function _registry_ripgrep_present
direnv          -               eget       bash  -             -              -       -                  -                 -
jq              -               eget       -     agent-badge   -              -       -                  -                 -
eget            -               installer  bash  -             -              -       -                  -                 -
sd              -               eget       bash  -             -              -       -                  -                 -
shellcheck      -               eget       dev   -             -              -       -                  -                 -
wsl2-ssh-agent  -               eget       bash  -             wsl            -       -                  -                 -
neovim          nvim            installer  dev   -             -              -       -                  -                 -
tmux            -               installer  dev   -             -              -       -                  -                 -
nvm             -               installer  work  -             -              -       -                  -                 file-nonempty $HOME/.nvm/nvm.sh
rust            rustc           installer  work  -             -              -       -                  -                 command cargo
claude          -               installer  -     ai            -              -       -                  -                 -
codex           -               installer  -     ai            -              -       -                  -                 runs
opencode        -               installer  -     ai            -              -       -                  -                 -
pi              -               installer  -     ai            -              -       -                  -                 runs
xrdp            -               apt        -     rdp           -              -       -                  xrdp              service-active xrdp
zsh             -               apt        dev   -             -              -       -                  zsh               -
docker          -               apt        work  -             -              -       22.04,24.04,26.04  docker-ce         -
azure-cli       az              apt        -     azure         -              -       22.04,24.04        azure-cli         -
sbx             -               apt        work  -             native-ubuntu  -       24.04,26.04        docker-sbx        runs
tailscale       -               apt        -     tail          -              -       22.04,24.04,26.04  tailscale         -
gcloud          -               apt        -     gcloud        -              -       22.04,24.04,26.04  google-cloud-cli  -
aws-cli         aws             installer  -     aws           -              -       22.04,24.04,26.04  -                 runs
"

# Overrides: "name field value" for fields most tools leave at their default.
# $HOME expands where the table is defined. Method defaults: eget tools are owned under
# ~/.local/bin with the staged-release update contract and uninstall to
# ~/.local/bin/BINARY plus companions; apt tools update apt-in-place.
#   eget-repo              eget.toml slug when its basename is not the tool name
#   update-source          GitHub repo check-updates compares a non-eget tool to
#   relative-binary        binary path inside the installed tree
#   version-flag           version argument (default: --version)
#   timeout                seconds allowed for the `runs` check
#   companions             extra executables installed, verified, and removed
#   ownership-roots        |-separated paths dotfiles may own
#   update-contract        how an update replaces the tool
#   paths                  |-separated paths uninstall removes
#   removal-mode           manual: show instructions instead of apt removal
#   removal-requires-sudo  yes: uninstall elevates for the paths
#   removal-instructions   human-readable removal steps or retained state
_REGISTRY_OVERRIDES="
gh         eget-repo              cli/cli
uv         companions             uvx
neovim     update-source          neovim/neovim
neovim     relative-binary        bin/nvim
neovim     ownership-roots        $HOME/.local/bin|$HOME/.local/nvim|$HOME/.local/.dotfiles-neovim-rollback
neovim     update-contract        staged-release
neovim     paths                  $HOME/.local/bin/nvim|$HOME/.local/nvim
tmux       update-source          tmux/tmux
tmux       version-flag           -V
tmux       ownership-roots        $HOME/.local/bin
tmux       update-contract        staged-build
tmux       paths                  $HOME/.local/bin/tmux
# eget installs through its own installer, not method eget, so it needs an
# explicit path: a fresh machine's PATH lacks ~/.local/bin.
eget       ownership-roots        $HOME/.local/bin
eget       update-contract        staged-release
eget       paths                  $HOME/.local/bin/eget
nvm        update-source          nvm-sh/nvm
nvm        ownership-roots        $HOME/.nvm
nvm        update-contract        vendor-installer-preserve-existing
nvm        paths                  $HOME/.nvm
rust       ownership-roots        $HOME/.cargo|$HOME/.rustup
rust       update-contract        vendor-installer-in-place
rust       removal-instructions   Run 'rustup self uninstall' after separately backing up any Cargo credentials/configuration.
claude     ownership-roots        $HOME/.local/bin|$HOME/.local/share/claude
claude     update-contract        moving-vendor-installer
claude     paths                  $HOME/.local/bin/claude|$HOME/.local/share/claude
claude     removal-instructions   $HOME/.claude configuration and sessions are preserved
codex      ownership-roots        $HOME/.local/bin|$HOME/.codex/packages/standalone
codex      update-contract        moving-vendor-installer-preserve-launcher
codex      paths                  $HOME/.local/bin/codex|$HOME/.codex/packages/standalone
codex      removal-instructions   $HOME/.codex configuration and sessions outside packages/standalone are preserved
opencode   ownership-roots        $HOME/.local/bin|$HOME/.opencode
opencode   update-contract        moving-vendor-installer
opencode   paths                  $HOME/.local/bin/opencode|$HOME/.opencode
opencode   removal-instructions   $HOME/.config/opencode configuration is preserved
# pi is a node script: a broken node or a dangling symlink into
# ~/.pi/agent/install still passes command -v, hence verify runs. Uninstall
# removes only install/; ~/.pi/agent also holds settings.json, sessions/,
# trust.json and models.json, which are user data.
pi         ownership-roots        $HOME/.local/bin|$HOME/.pi/agent/install
pi         update-contract        npm-prefix-in-place
pi         paths                  $HOME/.local/bin/pi|$HOME/.pi/agent/install
pi         removal-instructions   $HOME/.pi/agent settings, trust data, and sessions outside install/ are preserved
# A service is present only while it runs, not merely when its binary exists.
xrdp       update-contract        apt-and-service-in-place
xrdp       removal-mode           manual
xrdp       removal-instructions   sudo systemctl disable --now xrdp && sudo apt remove xrdp xorgxrdp  # config backups: /etc/xrdp/xrdp.ini.dotfiles-bak*, ~/.xsession.dotfiles-bak*
azure-cli  removal-instructions   $HOME/.azure credentials and configuration are preserved
sbx        version-flag           version
sbx        timeout                10
sbx        update-contract        apt-in-place-preserve-user-state
sbx        removal-instructions   Sandbox state, settings, credentials, and sessions under XDG directories are preserved
tailscale  update-contract        apt-and-service-in-place-preserve-enrollment
tailscale  removal-instructions   Tailscale identity and enrollment state under /var/lib/tailscale are preserved
gcloud     removal-instructions   $HOME/.config/gcloud credentials and configuration are preserved
aws-cli    ownership-roots        /usr/local/aws-cli|/usr/local/bin/aws|/usr/local/bin/aws_completer
aws-cli    update-contract        signed-vendor-installer-in-place
aws-cli    paths                  /usr/local/bin/aws|/usr/local/bin/aws_completer|/usr/local/aws-cli
aws-cli    removal-requires-sudo  yes
aws-cli    removal-instructions   $HOME/.aws credentials and configuration are preserved
"

# Parsed in memory: `read` from a here-string or heredoc costs a syscall per
# byte, which tripled the registry's load time. Splitting is deliberate, with
# globbing off.
# shellcheck disable=SC2206
_registry_load() {
    local - IFS line name binary method tier capabilities platform arches ubuntu apt verify field value
    local -a lines
    set -f
    IFS=$'\n'; lines=($_REGISTRY_TOOLS); IFS=$' \t\n'
    for line in "${lines[@]}"; do
        [[ "$line" == \#* ]] && continue
        set -- $line
        (( $# >= 10 )) || { REGISTRY_ERRORS+=("$1: incomplete row"); continue; }
        name="$1" binary="$2" method="$3" tier="$4" capabilities="$5" platform="$6"
        arches="$7" ubuntu="$8" apt="$9"
        shift 9; verify="$*"
        [[ -z "${TOOL_BINARY[$name]:-}" ]] || REGISTRY_ERRORS+=("$name: duplicate row")
        [[ "$binary" != - ]] || binary="$name"
        [[ "$platform" != - ]] || platform="ubuntu"
        [[ "$arches" != - ]] || arches="x86_64,aarch64"
        [[ "$verify" != - ]] || verify="command"
        TOOL_BINARY[$name]="$binary"
        TOOL_METHOD[$name]="$method"
        TOOL_PLATFORM[$name]="$platform"
        TOOL_ARCHES[$name]="$arches"
        TOOL_VERIFY[$name]="$verify"
        [[ "$tier" == - ]] || TOOL_TIER[$name]="$tier"
        [[ "$capabilities" == - ]] || TOOL_CAPABILITIES[$name]="$capabilities"
        [[ "$ubuntu" == - ]] || TOOL_UBUNTU_VERSIONS[$name]="$ubuntu"
        [[ "$apt" == - ]] || TOOL_APT_PACKAGE[$name]="$apt"
        case "$method" in
            eget)
                TOOL_OWNERSHIP_ROOTS[$name]="$HOME/.local/bin"
                TOOL_UPDATE_CONTRACT[$name]="staged-release"
                ;;
            apt) TOOL_UPDATE_CONTRACT[$name]="apt-in-place" ;;
        esac
    done

    IFS=$'\n'; lines=($_REGISTRY_OVERRIDES); IFS=$' \t\n'
    for line in "${lines[@]}"; do
        [[ "$line" == \#* ]] && continue
        set -- $line
        (( $# >= 3 )) || { REGISTRY_ERRORS+=("incomplete override: $line"); continue; }
        name="$1" field="$2"
        # The value is the rest of the line, internal spacing preserved.
        value="${line#*" $field "}"; value="$3${value#*"$3"}"
        [[ -n "${TOOL_BINARY[$name]:-}" ]] || { REGISTRY_ERRORS+=("override for unknown tool: $name"); continue; }
        case "$field" in
            eget-repo) TOOL_EGET_REPO[$name]="$value" ;;
            update-source) TOOL_UPDATE_SOURCE[$name]="$value" ;;
            relative-binary) TOOL_RELATIVE_BINARY[$name]="$value" ;;
            version-flag) TOOL_VERSION_FLAG[$name]="$value" ;;
            timeout) TOOL_TIMEOUT[$name]="$value" ;;
            companions) TOOL_COMPANIONS[$name]="$value" ;;
            ownership-roots) TOOL_OWNERSHIP_ROOTS[$name]="$value" ;;
            update-contract) TOOL_UPDATE_CONTRACT[$name]="$value" ;;
            paths) TOOL_PATHS[$name]="$value" ;;
            removal-mode) TOOL_REMOVAL_MODE[$name]="$value" ;;
            removal-requires-sudo) TOOL_REMOVAL_REQUIRES_SUDO[$name]="$value" ;;
            removal-instructions) TOOL_REMOVAL_INSTRUCTIONS[$name]="$value" ;;
            *) REGISTRY_ERRORS+=("$name: unknown field $field") ;;
        esac
    done
}
_registry_load
unset -f _registry_load
unset _REGISTRY_TOOLS _REGISTRY_OVERRIDES

# ==============================================================================
# Helper Functions
# ==============================================================================

# List tool names for a given tier, sorted.
# Usage: tools_for_tier "bash"  →  prints one tool name per line
tools_for_tier() {
    local tier="$1"
    local name
    for name in "${!TOOL_TIER[@]}"; do
        [[ "${TOOL_TIER[$name]}" == "$tier" ]] && printf '%s\n' "$name"
    done | sort
}

tool_has_capability() {
    local name="$1" capability="$2"
    case ",${TOOL_CAPABILITIES[$name]:-}," in
        *",$capability,"*) return 0 ;;
        *) return 1 ;;
    esac
}

tools_for_capability() {
    local capability="$1" name
    for name in "${!TOOL_BINARY[@]}"; do
        tool_has_capability "$name" "$capability" && printf '%s\n' "$name"
    done | sort
}

tool_in_cumulative_tier() {
    local name="$1" selected="$2"
    local required="${TOOL_TIER[$name]:-}"
    [[ -n "$required" ]] || return 1
    case "$selected:$required" in
        work:config|work:bash|work:dev|work:work|dev:config|dev:bash|dev:dev|bash:config|bash:bash|config:config) return 0 ;;
        *) return 1 ;;
    esac
}

# Whether a tool is present and working, per its verify type (see the core
# table). Prints nothing.
tool_is_present() {
    local name="$1" binary="${TOOL_BINARY[$1]:-}" type arg companion
    [[ -n "$binary" ]] || return 1
    read -r type arg <<< "${TOOL_VERIFY[$name]:-command}"
    case "$type" in
        command|runs)
            command -v "$binary" >/dev/null 2>&1 || return 1
            for companion in ${TOOL_COMPANIONS[$name]:-} $arg; do
                command -v "$companion" >/dev/null 2>&1 || return 1
            done
            [[ "$type" == runs ]] || return 0
            if [[ -n "${TOOL_TIMEOUT[$name]:-}" ]]; then
                timeout --foreground "${TOOL_TIMEOUT[$name]}" "$binary" "${TOOL_VERSION_FLAG[$name]:---version}" >/dev/null 2>&1
            else
                "$binary" "${TOOL_VERSION_FLAG[$name]:---version}" >/dev/null 2>&1
            fi
            ;;
        service-active) systemctl is-active --quiet "$arg" 2>/dev/null ;;
        file-nonempty) [[ -s "$arg" ]] ;;
        function) "$arg" ;;
        *) return 1 ;;
    esac
}

# The managed ~/.local/bin/rg wins. Otherwise accept rg on PATH, except copies
# private to Codex or VS Code extensions, which are not installations.
_registry_ripgrep_present() {
    local path
    if [[ -x "$HOME/.local/bin/rg" ]]; then
        "$HOME/.local/bin/rg" --version >/dev/null 2>&1
    else
        path="$(command -v rg 2>/dev/null || true)"
        [[ -n "$path" && "$path" != */.codex/* && "$path" != */.vscode*/extensions/* ]]
    fi
}

# Return the uninstall paths for a tool (expanded).
# Falls back to ~/.local/bin/<binary> for eget tools.
tool_uninstall_paths() {
    local name="$1"
    if [[ -n "${TOOL_PATHS[$name]:-}" ]]; then
        printf '%s\n' "${TOOL_PATHS[$name]}" | tr '|' '\n'
    elif [[ "${TOOL_METHOD[$name]}" == "eget" ]]; then
        echo "$HOME/.local/bin/${TOOL_BINARY[$name]}"
        local companion
        for companion in ${TOOL_COMPANIONS[$name]:-}; do
            printf '%s/.local/bin/%s\n' "$HOME" "$companion"
        done
    fi
}

tool_platform() {
    if [[ -n "${DOTFILES_TEST_PLATFORM:-}" ]]; then
        printf '%s\n' "$DOTFILES_TEST_PLATFORM"
    elif is_wsl; then
        printf 'wsl\n'
    else
        printf 'ubuntu\n'
    fi
}

tool_arch() {
    [[ -n "${DOTFILES_TEST_ARCH:-}" ]] && printf '%s\n' "$DOTFILES_TEST_ARCH" || get_arch
}

# Per-arch eget --asset flags, one argument per line, for releases whose asset
# names carry no OS and so defeat eget's native detection. Command-line --asset
# replaces the tool's eget.toml asset_filters. Prints nothing for other tools.
tool_eget_asset_args() {
    local name="$1" arch
    arch="$(tool_arch)" || return 1
    case "$name:$arch" in
        wsl2-ssh-agent:x86_64)  printf '%s\n' --asset wsl2-ssh-agent --asset '^arm64' ;;
        wsl2-ssh-agent:aarch64) printf '%s\n' --asset wsl2-ssh-agent-arm64 ;;
    esac
}

tool_applicable() {
    local name="$1" platform arch version=""
    platform="$(tool_platform)"; arch="$(tool_arch)" || return 1
    case ",${TOOL_ARCHES[$name]:-}," in *",$arch,"*) ;; *) return 1 ;; esac
    case "${TOOL_PLATFORM[$name]:-ubuntu}" in
        ubuntu) [[ "$platform" == ubuntu || "$platform" == wsl ]] ;;
        native-ubuntu) [[ "$platform" == ubuntu ]] ;;
        wsl) [[ "$platform" == wsl ]] ;;
        *) return 1 ;;
    esac || return 1
    if [[ -n "${TOOL_UBUNTU_VERSIONS[$name]:-}" ]]; then
        version="${DOTFILES_TEST_OS_VERSION:-}"
        if [[ -z "$version" ]]; then
            version="$(awk -F= '$1 == "VERSION_ID" { gsub(/^"|"$/, "", $2); print $2; exit }' "${DOTFILES_OS_RELEASE:-/etc/os-release}" 2>/dev/null || true)"
        fi
        case ",${TOOL_UBUNTU_VERSIONS[$name]}," in *",$version,"*) ;; *) return 1 ;; esac
    fi
}

tool_owned_path() {
    local name="$1" path="$2" roots root path_canon root_canon
    path_canon="$(realpath -m -- "$path" 2>/dev/null || true)"
    [[ -n "$path_canon" ]] || return 1
    roots="${TOOL_OWNERSHIP_ROOTS[$name]:-}"
    while [[ -n "$roots" ]]; do
        case "$roots" in *'|'*) root="${roots%%|*}"; roots="${roots#*|}" ;; *) root="$roots"; roots="" ;; esac
        root_canon="$(realpath -m -- "$root" 2>/dev/null || true)"
        [[ "$path_canon" == "$root_canon" || "$path_canon" == "$root_canon/"* ]] && return 0
    done
    return 1
}
