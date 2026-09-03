#!/bin/bash
# Git — aliases and functions

# Status and inspection
alias gs='git status'
alias gl='git log --oneline --decorate --graph'

# Clone operations
alias gcl='git clone'

# Clone a GitHub Enterprise Cloud repository through the machine-local AMD SSH
# alias, then teach gh that the synthetic host maps to the real github.com API.
# Set GH_AMD_USER in ~/.shell.local after authenticating that account with gh.
gcl-amd() {
    if (( $# < 1 || $# > 2 )); then
        echo "usage: gcl-amd OWNER/REPO [DIRECTORY]" >&2
        return 2
    fi

    if ! command -v gh >/dev/null 2>&1; then
        echo "gcl-amd: gh is required; run ./setup.sh --bash" >&2
        return 1
    fi

    if [[ -z "${GH_AMD_USER:-}" ]]; then
        echo "gcl-amd: set GH_AMD_USER in ~/.shell.local" >&2
        return 1
    fi

    local repo="$1"
    local destination="${2:-}"
    local token

    repo="${repo#https://github.com/}"
    repo="${repo#git@github.com:}"
    repo="${repo#git@github.com-amd:}"
    repo="${repo%.git}"

    case "$repo" in
        */*) ;;
        *)
            echo "gcl-amd: repository must be OWNER/REPO or a GitHub URL" >&2
            return 2
            ;;
    esac

    token="$(command gh auth token --hostname github.com --user "$GH_AMD_USER")" || {
        echo "gcl-amd: gh account '$GH_AMD_USER' is not authenticated" >&2
        return 1
    }

    if [[ -n "$destination" ]]; then
        git clone "git@github.com-amd:${repo}.git" "$destination" || return
    else
        git clone "git@github.com-amd:${repo}.git" || return
        destination="${repo##*/}"
    fi

    (
        cd "$destination" || exit 1
        GH_TOKEN="$token" command gh repo set-default "github.com/$repo"
    ) || {
        echo "gcl-amd: cloned successfully, but gh default setup failed" >&2
        return 1
    }

    echo "AMD repository ready: $destination"
}

# Staging and changes
alias ga='git add'
alias gaa='git add .'
alias gau='git add -u'
alias gd='git diff'
alias gds='git diff --staged'

# Commits
alias gc='git commit'
alias gcm='git commit -m'

# Branches (modern switch commands, Git 2.23+)
alias gsw='git switch'
alias gswc='git switch -c'
alias gb='git branch'

# Fetch operations
alias gf='git fetch'
alias gfo='git fetch origin'
alias gfu='git fetch upstream'
alias gfa='git fetch --all'

# Push/pull
alias gp='git push'
alias gpl='git pull'

# Stash
alias gst='git stash'
alias gstp='git stash pop'

# Lazygit TUI
alias lg='lazygit'

# Undo last commit but keep changes
gundo() {
    git reset HEAD~1 --soft
}
