#!/bin/bash
# Everforest theme for shell (FZF and prompt colors)

export FZF_THEME_COLORS='
    --color=bg+:#343f44,bg:#2d353b,spinner:#e67e80,hl:#475258
    --color=fg:#d3c6aa,header:#475258,info:#a7c080,pointer:#dbbc7f
    --color=marker:#e67e80,fg+:#d3c6aa,prompt:#a7c080,hl+:#dbbc7f'

# Per-tool palette selectors (consumed by env.sh / starship / delta)
export BAT_THEME='everforest'
export STARSHIP_PALETTE='everforest'
export DELTA_FEATURE='everforest'
