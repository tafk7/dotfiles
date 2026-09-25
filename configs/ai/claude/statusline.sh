#!/bin/bash
# Claude Code statusline — stacked context bar (input + last-response output) + model
# Install: chmod +x ~/.claude/statusline.sh
# Config in ~/.claude/settings.json:
#   { "statusLine": { "type": "command", "command": "~/.claude/statusline.sh", "padding": 0 } }

input=$(cat)

if ! command -v jq >/dev/null 2>&1; then
    printf 'statusline: jq not found'
    exit 0
fi

used=$(echo "$input"    | jq -r '.context_window.used_percentage     // 0')
out_tok=$(echo "$input" | jq -r '.context_window.total_output_tokens // 0')
win=$(echo "$input"     | jq -r '.context_window.context_window_size  // 0')
model=$(echo "$input"   | jq -r '.model.display_name                 // "unknown"')

[[ "$used"    =~ ^[0-9.]+$ ]] || used=0
[[ "$out_tok" =~ ^[0-9]+$  ]] || out_tok=0
[[ "$win"     =~ ^[0-9]+$  ]] || win=0

used_int=$(printf "%.0f" "$used")

# Last-response output as a raw count (window %% is meaningless on a 1M
# window — a single response is a sub-cell fraction). Render as k-tokens.
if   (( out_tok >= 1000 )); then out_lbl=$(printf '%d.%dk' $(( out_tok / 1000 )) $(( (out_tok % 1000) / 100 )))
else                             out_lbl="${out_tok}"
fi

# Palette
SAGE='\033[38;5;108m'; AMBER='\033[38;5;179m'; TERRA='\033[38;5;173m'
WARM_RED='\033[38;5;131m'; CYAN='\033[38;5;109m'   # CYAN = output count
GREY='\033[38;5;240m'; DIM='\033[2m'; RESET='\033[0m'

# Color by input fill — on a 1M window this is effectively the total
if   (( used_int >= 80 )); then COLOR=$WARM_RED
elif (( used_int >= 75 )); then COLOR=$TERRA
elif (( used_int >= 50 )); then COLOR=$AMBER
else                             COLOR=$SAGE
fi

bar_width=20
in_cells=$(( used_int * bar_width / 100 ))
(( in_cells > bar_width )) && in_cells=$bar_width
empty=$(( bar_width - in_cells ))

# Build bars by string repetition — NOT `tr`, which byte-splits the
# 3-byte block glyphs in a non-UTF-8 locale and yields � replacement chars.
repeat() { local n=$1 s=$2 out=''; while (( n-- > 0 )); do out+=$s; done; printf '%s' "$out"; }
bar_in=$(repeat    "$in_cells" '█')
bar_empty=$(repeat "$empty"    '░')

printf '%b%s%b%s%b %b%d%%%b %b(+%s out)%b %b· %s%b' \
    "$COLOR" "$bar_in" "$GREY" "$bar_empty" "$RESET" \
    "$COLOR" "$used_int" "$RESET" \
    "$CYAN" "$out_lbl" "$RESET" \
    "$DIM" "$model" "$RESET"
