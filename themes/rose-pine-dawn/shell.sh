#!/bin/bash
# Rosé Pine Dawn theme for shell (FZF and prompt colors)

export FZF_THEME_COLORS='
    --color=bg+:#f2e9e1,bg:#faf4ed,spinner:#d7827e,hl:#b4637a
    --color=fg:#575279,header:#b4637a,info:#907aa9,pointer:#d7827e
    --color=marker:#286983,fg+:#575279,prompt:#907aa9,hl+:#b4637a'

# Per-tool palette selectors (consumed by env.sh / starship / delta)
export BAT_THEME='rose-pine-dawn'
export STARSHIP_PALETTE='rose-pine-dawn'
export DELTA_FEATURE='rose-pine-dawn'
