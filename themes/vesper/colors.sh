#!/bin/bash
# Vesper color palette for preview
# https://github.com/datsfilipe/vesper.nvim
#
# Vesper is deliberately minimal: three real accents (amber, mint, soft red)
# over a neutral gray ramp on a #101010 near-black canvas. Where this system
# expects a role Vesper does not define (blue, purple), we reuse an existing
# Vesper color rather than inventing one — the duplication is intentional and
# is what makes the theme read as Vesper.

# Background colors
export THEME_BG_R=16 THEME_BG_G=16 THEME_BG_B=16        # bg #101010
export THEME_FG_R=255 THEME_FG_G=255 THEME_FG_B=255     # fg #ffffff

# Primary colors
export THEME_PRIMARY_R=255 THEME_PRIMARY_G=199 THEME_PRIMARY_B=153  # amber #ffc799
export THEME_SECONDARY_R=153 THEME_SECONDARY_G=255 THEME_SECONDARY_B=228 # mint #99ffe4

# Accent colors
export THEME_RED_R=255 THEME_RED_G=128 THEME_RED_B=128     # red #ff8080
export THEME_ORANGE_R=255 THEME_ORANGE_G=199 THEME_ORANGE_B=153 # amber #ffc799
export THEME_YELLOW_R=255 THEME_YELLOW_G=207 THEME_YELLOW_B=168 # sand #ffcfa8
export THEME_GREEN_R=153 THEME_GREEN_G=255 THEME_GREEN_B=228   # mint #99ffe4
export THEME_TEAL_R=153 THEME_TEAL_G=255 THEME_TEAL_B=228     # mint #99ffe4
export THEME_BLUE_R=160 THEME_BLUE_G=160 THEME_BLUE_B=160     # gray #a0a0a0 (Vesper has no blue)
export THEME_PURPLE_R=255 THEME_PURPLE_G=199 THEME_PURPLE_B=153 # amber #ffc799 (Vesper has no purple)

# Pane tint backgrounds (near-black progression — stays dark for OLED)
export THEME_TINT_1='#0A0A0A'  # deeper than bg
export THEME_TINT_2='#1C1C1C'  # bg_alt
export THEME_TINT_3='#232323'  # selection
