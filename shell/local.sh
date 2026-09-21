#!/bin/bash
# Interactive machine-local configuration. Load the main file first so it can
# supply values used by numbered fragments. Each reload deliberately rereads both.
[[ ! -r "$HOME/.shell.local" ]] || source "$HOME/.shell.local"
# Keep sourcing at the caller's scope so declarations in local files retain
# their usual meaning. Temporarily allow an unmatched glob in Zsh.
_dotfiles_local_nomatch=0
if [[ -n "${ZSH_VERSION:-}" ]] && [[ -o nomatch ]]; then
    _dotfiles_local_nomatch=1
    unsetopt nomatch
fi
_dotfiles_local_fragments=("$HOME"/.shell.local.d/*.sh)
if (( _dotfiles_local_nomatch )); then setopt nomatch; fi
for _dotfiles_local_fragment in "${_dotfiles_local_fragments[@]}"; do
    [[ ! -f "$_dotfiles_local_fragment" || ! -r "$_dotfiles_local_fragment" ]] \
        || source "$_dotfiles_local_fragment"
done
unset _dotfiles_local_fragment _dotfiles_local_fragments _dotfiles_local_nomatch
