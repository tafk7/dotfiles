#!/bin/bash
# Kanagawa Dragon theme for shell (FZF and prompt colors)

export FZF_THEME_COLORS='
    --color=bg+:#282727,bg:#181616,spinner:#c4746e,hl:#393836
    --color=fg:#c5c9c5,header:#393836,info:#8ba4b0,pointer:#c4746e
    --color=marker:#c4746e,fg+:#c5c9c5,prompt:#8ba4b0,hl+:#8ba4b0'

# Per-tool palette selectors (consumed by env.sh / starship / delta)
export BAT_THEME='kanagawa-dragon'
export STARSHIP_PALETTE='kanagawa-dragon'
export DELTA_FEATURE='kanagawa-dragon'
