# ~/.profile: login shell PATH baseline, locale, XDG.
# Does NOT source bashrc/zshrc — that's the terminal's job.
# Login bash gets bashrc via ~/.bash_profile; login zsh gets zshrc via ~/.zprofile.

# Double-source guard
[[ -n "$_PROFILE_LOADED" ]] && return
_PROFILE_LOADED=1

# PATH baseline — user and system bin directories
[ -d "$HOME/bin" ] && PATH="$HOME/bin:$PATH"
[ -d "$HOME/.local/bin" ] && PATH="$HOME/.local/bin:$PATH"
[ -d "/usr/local/bin" ] && PATH="/usr/local/bin:$PATH"

# Version managers — lightweight PATH-only, no eval/sourcing
# Full init (completions, switching) lives in shell/tool-init.sh via entry/*.sh
export NVM_DIR="$HOME/.nvm"
[ -d "$NVM_DIR/default/bin" ] && PATH="$NVM_DIR/default/bin:$PATH"
[ -d "$HOME/.pyenv/bin" ] && PATH="$HOME/.pyenv/shims:$HOME/.pyenv/bin:$PATH"

# Locale
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8
export LANGUAGE=en_US.UTF-8
[ -z "$TZ" ] && export TZ="UTC"

# XDG directories
export XDG_CONFIG_HOME="$HOME/.config"
export XDG_DATA_HOME="$HOME/.local/share"
export XDG_CACHE_HOME="$HOME/.cache"

# Terminal (don't override TERM if already set — tmux sets tmux-256color)
export TERM="${TERM:-xterm-256color}"
export PAGER=less
export LESS='-F -g -i -M -R -S -w -X -z-4'
