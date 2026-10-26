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
declare -A TOOL_NEEDS=() TOOL_POLICY=() TOOL_INSTALL=() TOOL_CONFIGURE=()
# The install order (components and package sets), package sets' tiers, and
# the orthogonal capabilities.
declare -a REGISTRY_ORDER=() CAPABILITY_NAMES=()
declare -A PACKAGE_SET_TIER=() CAPABILITY_REQUIRES=() CAPABILITY_LABEL=() CAPABILITY_HELP=()
# Problems found while parsing; tests/registry.sh requires this to stay empty.
declare -a REGISTRY_ERRORS=()

# Core table: one row per tool. "-" takes the default.
#   binary        command on PATH (default: the tool name)
#   method        eget | apt | installer | external
#   tier          minimum cumulative tier: bash | dev | work. Bash-tier tools
#                 must install without root. Capability-only tools have none.
#   capabilities  comma-separated orthogonal selections (the capability
#                 table below)
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
harper-ls       -               eget       dev   -             -              -       -                  -                 -
wsl2-ssh-agent  -               eget       bash  -             wsl            -       -                  -                 -
neovim          nvim            installer  dev   -             -              -       -                  -                 -
tmux            -               installer  dev   -             -              -       -                  -                 -
nvm             -               installer  work  -             -              -       -                  -                 file-nonempty $HOME/.nvm/nvm.sh
node            -               installer  work  -             -              -       -                  -                 function _registry_node_present
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
#   needs                  comma-separated components or package sets
#                          (packages:SET) that must come first in the install
#                          order (default: eget for eget tools)
#   policy                 converge: an owned install moves to its pin
#                          (default for eget and installer tools); present:
#                          installed, versions are the package manager's
#                          (default for apt); vendor: installed, the vendor's
#                          updater owns versions
#   install                how setup installs it: eget (default for eget
#                          tools, all in one batch), installer
#                          (installers/install-NAME.sh; default otherwise),
#                          packages:SET (by that package set; recorded only),
#                          bootstrap (by the eget batch), or function:NAME
#   configure              space-separated functions (lib/configure.sh) setup
#                          runs after the install step when the component
#                          applies, whether or not the install changed
#                          anything; each gets the component name
_REGISTRY_OVERRIDES="
eget       install                bootstrap
zsh        install                packages:dev
zsh        needs                  packages:dev
tmux       needs                  packages:dev
docker     install                function:install_docker_engine
docker     configure              configure_docker_host_access
sbx        needs                  docker
sbx        policy                 converge
sbx        configure              configure_work_host ensure_sbx_kits_builder
neovim     configure              configure_editor_plugins
node       needs                  nvm
node       configure              use_default_node
claude     policy                 vendor
claude     configure              configure_ai_settings configure_agent_badge update_agent_badge
codex      policy                 vendor
codex      configure              configure_ai_settings configure_agent_badge update_agent_badge
opencode   policy                 vendor
opencode   configure              configure_opencode_settings
pi         policy                 vendor
pi         needs                  node
pi         configure              configure_pi_settings
xrdp       install                function:install_rdp_packages
tailscale  configure              configure_tailscaled
gh         eget-repo              cli/cli
harper-ls  eget-repo              Automattic/harper
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
# Node is the release versions.lock pins, installed through nvm into a
# versioned directory and made nvm's default.
node       ownership-roots        $HOME/.nvm
node       update-contract        versioned-nvm-install
node       removal-instructions   Run 'nvm uninstall <version>' for one release; uninstalling nvm removes them all.
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

# The install order. Setup installs the selected entries in this order: the
# eget tools in one batch at the first one's place, package sets (apt packages
# for a tier, before the components that need them), then components.
_REGISTRY_ORDER="
eget
starship eza fzf zoxide delta btop gdu glow lazygit gh uv bat fd ripgrep direnv sd
shellcheck harper-ls wsl2-ssh-agent
packages:dev zsh tmux neovim
packages:work docker sbx nvm node rust
jq claude codex opencode pi
xrdp tailscale azure-cli gcloud aws-cli
"

# Package sets: apt packages a tier installs beyond its components
# (install_package_set in lib/install.sh).
#   set   tier
_REGISTRY_PACKAGE_SETS="
dev   dev
work  work
"

# Orthogonal capabilities, in banner, install, and summary order:
#   name|requirements|label|help
# Requirements: ubuntu (a supported Ubuntu release), curl, apt (apt-get), sudo,
# systemd (systemctl), and applicable (every registry component of the
# capability must apply to this platform). A flag --NAME selects the
# capability; ai also has per-tool flags. agent-badge is a capability of jq
# only: a feature preference (--agent-badge / --no-agent-badge), not a
# selection.
_REGISTRY_CAPABILITIES="
ai|curl|AI CLIs|Every AI CLI, into ~/.local/bin. Leave it off where an organization manages them; the shell shortcuts load either way.
rdp|ubuntu apt sudo systemd|RDP server (xrdp)|The xrdp RDP server with an XFCE session. Never implied by --full, since it opens a listener: localhost:3390 on WSL, port 3389 elsewhere (keep it behind a VPN or firewall). See docs/history/xrdp-remote-desktop.md.
tail|ubuntu curl apt sudo applicable|Tailscale|Tailscale and its systemd service. No enrollment, routes, SSH, or firewall changes.
azure|ubuntu curl apt sudo applicable|Azure CLI|Azure CLI from Microsoft's signed APT repository. The Azure DevOps Git credential helper is parked; see bin/git-credential-azdo.
gcloud|ubuntu curl apt sudo applicable|Google Cloud CLI|Google Cloud CLI from Google's signed APT repository.
aws|ubuntu curl apt sudo applicable|AWS CLI v2|AWS CLI v2, the release versions.lock pins, signature-verified.
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
                TOOL_NEEDS[$name]=eget TOOL_POLICY[$name]=converge TOOL_INSTALL[$name]=eget
                ;;
            apt)
                TOOL_UPDATE_CONTRACT[$name]="apt-in-place"
                TOOL_POLICY[$name]=present TOOL_INSTALL[$name]=installer
                ;;
            *) TOOL_POLICY[$name]=converge TOOL_INSTALL[$name]=installer ;;
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
            needs) TOOL_NEEDS[$name]="$value" ;;
            policy) TOOL_POLICY[$name]="$value" ;;
            install) TOOL_INSTALL[$name]="$value" ;;
            configure) TOOL_CONFIGURE[$name]="$value" ;;
            *) REGISTRY_ERRORS+=("$name: unknown field $field") ;;
        esac
    done

    IFS=$'\n'; lines=($_REGISTRY_PACKAGE_SETS); IFS=$' \t\n'
    for line in "${lines[@]}"; do
        [[ "$line" == \#* ]] && continue
        set -- $line
        (( $# == 2 )) || { REGISTRY_ERRORS+=("incomplete package set: $line"); continue; }
        PACKAGE_SET_TIER[$1]="$2"
    done

    IFS=$'\n'; lines=($_REGISTRY_CAPABILITIES); IFS=$' \t\n'
    local capability requires label help
    for line in "${lines[@]}"; do
        [[ "$line" == \#* ]] && continue
        IFS='|' read -r capability requires label help <<< "$line"
        [[ -n "$label" ]] || { REGISTRY_ERRORS+=("incomplete capability: $line"); continue; }
        CAPABILITY_NAMES+=("$capability")
        CAPABILITY_REQUIRES[$capability]="$requires"
        CAPABILITY_LABEL[$capability]="$label"
        CAPABILITY_HELP[$capability]="$help"
    done

    # The order names every component and package set once, each after what it
    # needs.
    local -A position=()
    local entry need index=0
    for entry in $_REGISTRY_ORDER; do
        [[ -z "${position[$entry]:-}" ]] || REGISTRY_ERRORS+=("$entry: listed twice in the install order")
        if [[ "$entry" == packages:* ]]; then
            [[ -n "${PACKAGE_SET_TIER[${entry#packages:}]:-}" ]] || REGISTRY_ERRORS+=("$entry: unknown package set")
        else
            [[ -n "${TOOL_BINARY[$entry]:-}" ]] || REGISTRY_ERRORS+=("$entry: unknown component in the install order")
        fi
        REGISTRY_ORDER+=("$entry")
        position[$entry]=$(( ++index ))
    done
    for name in "${!TOOL_BINARY[@]}"; do
        [[ -n "${position[$name]:-}" ]] || { REGISTRY_ERRORS+=("$name: missing from the install order"); continue; }
        local needs="${TOOL_NEEDS[$name]:-}"
        for need in ${needs//,/ }; do
            [[ -n "${position[$need]:-}" ]] || { REGISTRY_ERRORS+=("$name: needs unknown $need"); continue; }
            (( position[$need] < position[$name] )) || REGISTRY_ERRORS+=("$name: needs $need, which comes later")
        done
        case "${TOOL_POLICY[$name]}" in converge|present|vendor) ;; *) REGISTRY_ERRORS+=("$name: unknown policy ${TOOL_POLICY[$name]}") ;; esac
        case "${TOOL_INSTALL[$name]}" in
            eget|installer|bootstrap|function:?*) ;;
            packages:?*) [[ -n "${PACKAGE_SET_TIER[${TOOL_INSTALL[$name]#packages:}]:-}" ]] \
                || REGISTRY_ERRORS+=("$name: installed by unknown ${TOOL_INSTALL[$name]}") ;;
            *) REGISTRY_ERRORS+=("$name: unknown install ${TOOL_INSTALL[$name]}") ;;
        esac
    done
}
_registry_load
unset -f _registry_load
unset _REGISTRY_TOOLS _REGISTRY_OVERRIDES _REGISTRY_ORDER _REGISTRY_PACKAGE_SETS _REGISTRY_CAPABILITIES

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

# The components with a capability, in install order.
tools_for_capability() {
    local capability="$1" name
    for name in "${REGISTRY_ORDER[@]}"; do
        [[ "$name" != packages:* ]] || continue
        tool_has_capability "$name" "$capability" && printf '%s\n' "$name"
    done
    return 0
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

# The Node release directory nvm's default alias names: an exact version in
# the alias, else the $NVM_DIR/default link setup maintains. Nothing is run.
node_default_dir() {
    local nvm_dir="${NVM_DIR:-$HOME/.nvm}" alias="" dir=""
    [[ ! -r "$nvm_dir/alias/default" ]] || alias="$(head -n1 "$nvm_dir/alias/default")"
    if [[ "$alias" =~ ^v?([0-9]+\.[0-9]+\.[0-9]+)$ ]]; then
        dir="$nvm_dir/versions/node/v${BASH_REMATCH[1]}"
    elif [[ -L "$nvm_dir/default" ]]; then
        dir="$(readlink -f "$nvm_dir/default" 2>/dev/null || true)"
    fi
    [[ -n "$dir" && -x "$dir/bin/node" ]] || return 1
    printf '%s\n' "$dir"
}

_registry_node_present() {
    local dir
    dir="$(node_default_dir)" && "$dir/bin/node" --version >/dev/null 2>&1
}

# Whether the tool moves into a new versioned path when it updates (a vendor
# updater, or a pin move into nvm's next version directory), so a recorded path
# inside its ownership roots goes stale by design.
tool_moves_itself() {
    [[ "${TOOL_UPDATE_CONTRACT[$1]:-}" == moving-vendor-installer* || "${TOOL_UPDATE_CONTRACT[$1]:-}" == versioned-* ]]
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
# names carry no OS and so defeat eget's native detection. They replace the
# tool's eget.toml asset_filters when tests/eget-selection.py chooses the asset
# versions.lock records. Prints nothing for other tools.
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
