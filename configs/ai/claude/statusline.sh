#!/bin/bash
# Claude Code statusline — context bar with an autocompact marker + model + dir
# Not executable; configs/claude-settings.json runs it as
# `bash ~/.claude/statusline.sh`.

input=$(cat)

if ! command -v jq >/dev/null 2>&1; then
    printf 'statusline: jq not found'
    exit 0
fi

used=$(echo "$input"    | jq -r '.context_window.used_percentage     // 0')
out_tok=$(echo "$input" | jq -r '.context_window.total_output_tokens // 0')
win=$(echo "$input"     | jq -r '.context_window.context_window_size  // 0')
model=$(echo "$input"   | jq -r '.model.display_name                 // "unknown"')
cur=$(echo "$input"     | jq -r '.workspace.current_dir // .cwd       // ""')
proj=$(echo "$input"    | jq -r '.workspace.project_dir               // ""')

# Debug: STATUSLINE_DUMP=/path keeps the latest stdin JSON, to see what Claude
# Code sends while a subagent transcript is open.
[[ -n "$STATUSLINE_DUMP" ]] && printf '%s\n' "$input" > "$STATUSLINE_DUMP"

# Viewing a subagent: if transcript_path is a subagent transcript, take model and
# context fill from its last assistant message instead of the main session's.
# Best effort: window size is assumed to match the main session's.
tp=$(echo "$input" | jq -r '.transcript_path // ""')
if [[ "$tp" == */subagents/* && -r "$tp" ]]; then
    sub=$(tail -n 200 "$tp" | jq -rs '[.[] | select(.message.usage and .message.model)] | last
        | if . then [.message.model,
            ((.message.usage.input_tokens // 0) + (.message.usage.cache_creation_input_tokens // 0)
             + (.message.usage.cache_read_input_tokens // 0))] | @tsv else empty end' 2>/dev/null)
    if [[ -n "$sub" ]]; then
        sub_id=${sub%%$'\t'*}; sub_tok=${sub##*$'\t'}
        # claude-opus-5-5 -> Opus 5.5
        model=$(sed -E 's/^claude-//; s/-[0-9]{8}$//; s/-([0-9]+)-([0-9]+)$/ \1.\2/; s/^./\U&/' <<<"$sub_id")
        model="$model (subagent)"
        if (( win > 0 )) && [[ "$sub_tok" =~ ^[0-9]+$ ]]; then
            used=$(awk -v t="$sub_tok" -v w="$win" 'BEGIN{printf "%.2f", t*100/w}')
        fi
    fi
fi

[[ "$used"    =~ ^[0-9.]+$ ]] || used=0
[[ "$out_tok" =~ ^[0-9]+$  ]] || out_tok=0
[[ "$win"     =~ ^[0-9]+$  ]] || win=0

used_int=$(printf "%.0f" "$used")

# Palette
SAGE='\033[38;5;108m'; AMBER='\033[38;5;179m'; TERRA='\033[38;5;173m'
WARM_RED='\033[38;5;131m'; MARK='\033[1;97m'
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

# Autocompact marker: a bright thin line where compaction starts. Window comes
# from, highest first: CLAUDE_CODE_AUTO_COMPACT_WINDOW, modelSettings.<model>.
# autoCompactWindow, autoCompactWindow (settings: user < project < local), capped
# at the model's window. The --autocompact flag is invisible to us. With none
# set, 1M models compact at ~967k; the 200k default (window - 33k) is a guess.
# CLAUDE_AUTOCOMPACT_PCT_OVERRIDE lowers it by percent.
mid=$(echo "$input" | jq -r '.model.id // ""')
[[ -n "$sub_id" ]] && mid=$sub_id
auto=1
[[ "$DISABLE_AUTO_COMPACT" == 1 || "$DISABLE_AUTO_COMPACT" == true || "$DISABLE_COMPACT" == 1 ]] && auto=0
[[ "$(jq -r '.autoCompactEnabled' "$HOME/.claude/settings.json" 2>/dev/null)" == false ]] && auto=0
if (( win > 0 && auto )); then
    cfg=''
    for f in "$HOME/.claude/settings.json" "$proj/.claude/settings.json" "$proj/.claude/settings.local.json"; do
        [[ -r "$f" ]] || continue
        # Gateway IDs come as "Claude-Fable-5.2": compare lowercased, dots as dashes.
        v=$(jq -r --arg m "$mid" '
            def norm: ascii_downcase | gsub("\\."; "-");
            ((.modelSettings // {}) | to_entries | map(select(.key as $k | ($m | norm) | startswith($k | norm)))
              | sort_by(.key | length) | last | .value.autoCompactWindow) // .autoCompactWindow // empty' "$f" 2>/dev/null)
        [[ "$v" =~ ^[0-9]+$ ]] && cfg=$v
    done
    # --autocompact on the launching claude process (flag beats settings, loses to env)
    pid=$PPID
    for _ in 1 2 3 4; do
        [[ -r /proc/$pid/cmdline ]] || break
        mapfile -d '' -t argv < "/proc/$pid/cmdline"
        for i in "${!argv[@]}"; do
            case "${argv[i]}" in
                --autocompact=*) fl=${argv[i]#*=} ;;
                --autocompact)   fl=${argv[i+1]:-} ;;
                *) continue ;;
            esac
            fl=${fl//[kK]/000}; fl=${fl//[mM]/000000}
            if [[ "$fl" =~ ^[0-9]+$ ]]; then
                (( fl >= 100 && fl <= 1000 )) && fl=$(( fl * 1000 ))
                cfg=$fl
            fi
            break 2
        done
        pid=$(awk '{print $4}' "/proc/$pid/stat" 2>/dev/null); [[ "$pid" =~ ^[0-9]+$ ]] && (( pid > 1 )) || break
    done
    ew=${CLAUDE_CODE_AUTO_COMPACT_WINDOW:-}
    ew=${ew//[kK]/000}; ew=${ew//[mM]/000000}
    [[ "$ew" =~ ^[0-9]+$ ]] && cfg=$ew
    if [[ -n "$cfg" ]]; then
        thr=$cfg
        (( thr < 100000 )) && thr=100000
        (( thr > win )) && thr=$win
    elif (( win >= 1000000 )); then thr=967000
    else thr=$(( win - 33000 ))
    fi
    thr_pct=$(( thr * 100 / win ))
    ov=${CLAUDE_AUTOCOMPACT_PCT_OVERRIDE:-}
    [[ "$ov" =~ ^[0-9]+$ ]] && (( ov > 0 && ov < 100 )) && thr_pct=$(( thr_pct * ov / 100 ))
    m=$(( thr_pct * bar_width / 100 )); (( m > bar_width - 1 )) && m=$(( bar_width - 1 ))
    if (( m < in_cells )); then
        bar_in="$(repeat "$m" '█')${MARK}│${COLOR}$(repeat $(( in_cells - m - 1 )) '█')"
    else
        bar_empty="$(repeat $(( m - in_cells )) '░')${MARK}│${GREY}$(repeat $(( bar_width - m - 1 )) '░')"
    fi
fi

# Agent's live shell cwd: project-relative when inside the project,
# ~-abbreviated and amber when it has wandered outside.
dir_lbl=''; DIR_COLOR=$SAGE
if [[ -n "$cur" ]]; then
    if [[ -n "$proj" && ( "$cur" == "$proj" || "$cur" == "$proj"/* ) ]]; then
        dir_lbl="${proj##*/}${cur#"$proj"}"
    else
        dir_lbl="$cur"
        [[ "$dir_lbl" == "$HOME" || "$dir_lbl" == "$HOME"/* ]] && dir_lbl="~${dir_lbl#"$HOME"}"
        [[ -n "$proj" ]] && DIR_COLOR=$AMBER
    fi
fi

printf '%b%b%b%b%b %b%d%%%b %b· %s%b' \
    "$COLOR" "$bar_in" "$GREY" "$bar_empty" "$RESET" \
    "$COLOR" "$used_int" "$RESET" \
    "$DIM" "$model" "$RESET"
[[ -n "$dir_lbl" ]] && printf ' %b·%b %b%s%b' "$DIM" "$RESET" "$DIR_COLOR" "$dir_lbl" "$RESET"
