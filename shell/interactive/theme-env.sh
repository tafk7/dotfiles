#!/bin/bash
# Optional interactive theme environment. Layer 0 never sources this file.

_DOTFILES_THEME_ACTIVE=1
_dotfiles_theme_preferences="${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles/preferences.tsv"
if [[ -r "$_dotfiles_theme_preferences" ]]; then
    while IFS=$'\t' read -r _dotfiles_theme_key _dotfiles_theme_value; do
        if [[ "$_dotfiles_theme_key" == feature.theme ]]; then
            [[ "$_dotfiles_theme_value" == disabled ]] && _DOTFILES_THEME_ACTIVE=0
            break
        fi
    done < "$_dotfiles_theme_preferences"
fi
unset _dotfiles_theme_preferences _dotfiles_theme_key _dotfiles_theme_value

if [[ "$_DOTFILES_THEME_ACTIVE" == 1 && -n "${DOTFILES_DIR:-}" \
   && -x "$DOTFILES_DIR/bin/theme-switcher" ]]; then
    export DOTFILES_THEME_ENABLED=1
    eval "$("$DOTFILES_DIR/bin/theme-switcher" env "${DOTFILES_THEME_CONTEXT_SIGNATURE:-}" 2>/dev/null)"
else
    export DOTFILES_THEME_ENABLED=0
    unset DOTFILES_THEME DOTFILES_THEME_CONTEXT_SIGNATURE \
        DOTFILES_THEME_SESSION_ID DOTFILES_THEME_WINDOW_ID \
        DOTFILES_THEME_VIM_RESOLVED DOTFILES_THEME_BAT_RESOLVED \
        DOTFILES_THEME_DELTA_RESOLVED DOTFILES_THEME_TMUX_RESOLVED \
        DOTFILES_THEME_STARSHIP_RESOLVED DOTFILES_THEME_FZF_RESOLVED \
        DOTFILES_THEME_BTOP_RESOLVED DOTFILES_THEME_LAZYGIT_RESOLVED \
        BAT_THEME BAT_CACHE_PATH STARSHIP_CONFIG STARSHIP_PALETTE \
        DELTA_FEATURE DELTA_FEATURES BTOP_THEME_CONFIG BTOP_THEME_DIR \
        LAZYGIT_THEME_CONFIG FZF_THEME_COLORS THEME_TINT_1 THEME_TINT_2 THEME_TINT_3
fi
