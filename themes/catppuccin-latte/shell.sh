#!/bin/bash
# Catppuccin Latte theme for shell (FZF and prompt colors)

export FZF_THEME_COLORS='
    --color=bg+:#ccd0da,bg:#eff1f5,spinner:#dc8a78,hl:#d20f39
    --color=fg:#4c4f69,header:#d20f39,info:#8839ef,pointer:#dc8a78
    --color=marker:#7287fd,fg+:#4c4f69,prompt:#8839ef,hl+:#d20f39'

# Per-tool palette selectors (consumed by env.sh / starship / delta)
# bat 0.25+ ships Catppuccin Latte as a built-in — no vendored .tmTheme needed.
export BAT_THEME='Catppuccin Latte'
export STARSHIP_PALETTE='catppuccin-latte'
export DELTA_FEATURE='catppuccin-latte'
