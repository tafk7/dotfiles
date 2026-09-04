#!/bin/bash
# Vesper theme for shell (FZF and prompt colors)

export FZF_THEME_COLORS='
    --color=bg+:#1c1c1c,bg:#101010,spinner:#ffc799,hl:#8b8b8b
    --color=fg:#a0a0a0,header:#8b8b8b,info:#99ffe4,pointer:#ffc799
    --color=marker:#99ffe4,fg+:#ffffff,prompt:#ffc799,hl+:#ffc799'

# Per-tool palette selectors (consumed by env.sh / starship / delta)
export BAT_THEME='vesper'
export STARSHIP_PALETTE='vesper'
export DELTA_FEATURE='vesper'
