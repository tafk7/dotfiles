#!/bin/bash
# The environment dotfiles manages, for processes that do not start a shell:
# the tmux server's global environment and what it hands to new windows.
#
# Variables come in three kinds:
#   owned       set from the layers (repo defaults, then ~/.shell.env), never
#               from an inherited value; a refresh sets or unsets them
#   respected   inherited values win (XDG roots, TERM); dotfiles never changes
#               their defaults, so they cannot go stale
#   PATH        the segments dotfiles added last time are replaced with the
#               new set; other segments stay where they are
# The load guards (_DOTFILES_*) are never published: tmux.conf and refresh
# unset them, so every new shell recomputes its environment.

[[ -n "${_DOTFILES_ENVIRONMENT_LOADED:-}" ]] && return 0
_DOTFILES_ENVIRONMENT_LOADED=1

ENV_OWNED=(LANG LANGUAGE PAGER LESS EDITOR VISUAL PROJECTS_DIRS RIPGREP_CONFIG_PATH
    PYTHONDONTWRITEBYTECODE PIP_REQUIRE_VIRTUALENV DOCKER_BUILDKIT COMPOSE_DOCKER_CLI_BUILD
    NVM_DIR GOPATH CARGO_HOME DOTFILES_DIR)
ENV_RESPECTED=(XDG_CONFIG_HOME XDG_DATA_HOME XDG_STATE_HOME XDG_CACHE_HOME TERM)
ENV_GUARDS=(_DOTFILES_BASE_ENV _DOTFILES_ENV_LOADED _PROFILE_LOADED)
# The PATH the producer starts from; what env.sh puts in front is dotfiles'.
ENV_BASE_PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
# The segments the last refresh published, so the next can remove them.
ENV_SEGMENTS_FILE="${DOTFILES_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles}/path-segments"

# env_produce [CHECKOUT]: the managed environment as the producer prints it
# (lib/env-producer.sh). The checkout defaults to the recorded install path.
# Only HOME, the user, the respected variables, and WSL's markers reach it.
env_produce() {
    local checkout="${1:-}" name state_dir
    state_dir="${DOTFILES_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles}"
    [[ -n "$checkout" || ! -r "$state_dir/install-path" ]] || checkout="$(<"$state_dir/install-path")"
    checkout="${checkout:-$DOTFILES_DIR}"
    local -a pass=(HOME="$HOME" USER="${USER:-}" LOGNAME="${LOGNAME:-${USER:-}}" PATH="$ENV_BASE_PATH" DOTFILES_DIR="$checkout")
    for name in "${ENV_RESPECTED[@]}" WSL_DISTRO_NAME WSL_INTEROP DOTFILES_WSL; do
        [[ -z "${!name+x}" ]] || pass+=("$name=${!name}")
    done
    (cd "$HOME" && env -i "${pass[@]}" bash --noprofile --norc "$checkout/lib/env-producer.sh" "${ENV_OWNED[@]}")
}

# env_path_replace OLD NEW PATH: PATH with the OLD segments removed and NEW put
# in front, every other entry kept in its place and duplicates dropped.
env_path_replace() {
    local old=":$1:" new="$2" path="$3" entry out="" seen=":"
    local IFS=:
    for entry in $new $path; do
        [[ -n "$entry" && "$seen" != *":$entry:"* ]] || continue
        if [[ ":$new:" != *":$entry:"* && "$old" == *":$entry:"* ]]; then
            continue
        fi
        out+="${out:+:}$entry"
        seen+="$entry:"
    done
    printf '%s\n' "$out"
}
