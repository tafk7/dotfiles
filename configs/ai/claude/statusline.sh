#!/bin/bash
# Claude Code statusline — context bar with an autocompact marker + model + dir
# Not executable; configs/claude-settings.json runs it as
# `bash ~/.claude/statusline.sh`.

input=$(cat)

if ! command -v jq >/dev/null 2>&1; then
    printf 'statusline: jq not found'
    exit 0
fi

# One parse per refresh; invalid fields and malformed JSON keep the line usable.
mapfile -t fields < <(jq -r '
    def text: if type == "string" and (test("[\\r\\n\\t]") | not) then . else "" end;
    def number: if type == "number" then . else 0 end;
    def model_key: ascii_downcase | sub("^claude-"; "") | sub("-[0-9]{8}$"; "") |
        gsub("[^a-z0-9]+"; "-") | gsub("^-|-$"; "");
    if type == "object" then . else {} end |
    (.context_window.used_percentage | number),
    (.context_window.total_output_tokens | number),
    (.context_window.context_window_size | number),
    (.model.display_name | text),
    ((.workspace.current_dir // .cwd) | text),
    (.workspace.project_dir | text), (.transcript_path | text),
    (.session_id | text), (.model.id | text),
    ((.model.display_name | text) as $name |
        (if $name != "" then $name else (.model.id | text) end) | model_key)' <<< "$input" 2>/dev/null)
used=${fields[0]:-0}; out_tok=${fields[1]:-0}; win=${fields[2]:-0}
model=${fields[3]:-unknown}; cur=${fields[4]:-}; proj=${fields[5]:-}
tp=${fields[6]:-}; sid=${fields[7]:-}; mid=${fields[8]:-}
main_model=${fields[9]:-}; subagent_view=0
[[ "$tp" == */subagents/* ]] && subagent_view=1
[[ "$out_tok" =~ ^[0-9]{1,12}$ ]] || out_tok=0
[[ "$win" =~ ^[0-9]{1,9}$ ]] && win=$((10#$win)) || win=0

# Debug: STATUSLINE_DUMP=/path keeps the latest stdin JSON, to see what Claude
# Code sends while a subagent transcript is open.
[[ -n "$STATUSLINE_DUMP" ]] && printf '%s\n' "$input" > "$STATUSLINE_DUMP"

# Viewing a subagent: if transcript_path is a subagent transcript, take model and
# context fill from its last assistant message instead of the main session's.
# Best effort: window size is assumed to match the main session's.
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

[[ "$used" =~ ^[0-9]+([.][0-9]+)?$ && ${#used} -le 16 ]] || used=0
used_int=$(printf "%.0f" "$used")
(( used_int > 100 )) && used_int=100

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

# Autocompact marker: applied live command > session runtime trigger > the
# existing env/flag/settings/default lookup. Runtime triggers already include
# the reserve; compact_pending and applied_to describe other launches.
[[ -n "$sub_id" ]] && mid=$sub_id
auto=1
[[ "$DISABLE_AUTO_COMPACT" == 1 || "$DISABLE_AUTO_COMPACT" == true || "$DISABLE_COMPACT" == 1 ]] && auto=0
config_dir=${CLAUDE_CONFIG_DIR:-$HOME/.claude}
[[ "$(jq -r '.autoCompactEnabled' "$config_dir/settings.json" 2>/dev/null)" == false ]] && auto=0
if (( win > 0 && auto )); then
    # Accept token counts and the CLI's k/M and bare-thousands shorthand.
    # Limit digit length before bash arithmetic (including leading zeroes).
    window_tokens() {
        local v=${1,,} n suffix
        [[ "$v" =~ ^([0-9]{1,9})([km]?)$ ]] || return 1
        n=$((10#${BASH_REMATCH[1]})); suffix=${BASH_REMATCH[2]}
        case "$suffix" in k) n=$((n * 1000));; m) n=$((n * 1000000));;
            '') (( n >= 100 && n <= 1000 )) && n=$((n * 1000));; esac
        (( n > 0 )) || return 1
        printf '%s' "$n"
    }

    reserve=33000; recorded=''; live=''
    if [[ -n "$sid" ]]; then
        key=$(printf '%s' "$sid" | sha256sum 2>/dev/null); key=${key%% *}
        desk=${SCRIV_DESK:-}
        # Sessions normally carry SCRIV_DESK, including background launches.
        # Legacy sessions may still start inside a project desk directory.
        if [[ -z "$desk" && "$proj" == /* ]]; then
            dir=$proj
            while [[ -n "$dir" ]]; do
                if [[ -r "$dir/project.toml" ]] && \
                    desk_table=$(sed -n '/^[[:space:]]*\[desk\][[:space:]]*\(#.*\)\?$/p' "$dir/project.toml" 2>/dev/null) && [[ -n "$desk_table" ]]; then
                    desk=$dir; break
                fi
                [[ "$dir" == / ]] && break
                dir=${dir%/*}; [[ -n "$dir" ]] || dir=/
            done
        fi
        if [[ "$key" =~ ^[0-9a-f]{64}$ && -n "$desk" ]]; then
            mapfile -t compact < <(jq -r --arg sid "$sid" '
                select(.session == $sid and (.harness == "claude" or .harness == "claude-sdk")) |
                .compaction | (.trigger // ""), (.reservation // "")' \
                "$desk/.runtime/compact/$key.json" 2>/dev/null)
            [[ "${compact[0]:-}" =~ ^[0-9]{1,7}$ ]] && \
                (( 10#${compact[0]} > 0 )) && recorded=$((10#${compact[0]}))
            [[ "${compact[1]:-}" =~ ^[0-9]{1,5}$ ]] && \
                (( 10#${compact[1]} >= 13000 && 10#${compact[1]} <= 33000 )) && reserve=$((10#${compact[1]}))
        fi

        if [[ "$key" =~ ^[0-9a-f]{64}$ ]]; then
            # A byte bound matters: one tool-result line can be megabytes. Parse
            # JSONL independently so partial edge lines cannot poison the tail.
            # Cache an observed command so it survives leaving the 64 KiB tail;
            # path/inode changes or truncation invalidate it. A command can be
            # missed if more than 64 KiB arrives before the next refresh.
            cache_dir=${XDG_CACHE_HOME:-$HOME/.cache}/claude-statusline
            cache=$cache_dir/$key.json
            if (( subagent_view )); then
                # The input still names the main session/model. A subagent view
                # reads its cached value without scanning or rewriting the cache.
                live=$(jq -r --arg sid "$sid" --arg model "$main_model" '
                    select(.session == $sid) | .models[$model] // empty' "$cache" 2>/dev/null)
            elif [[ -f "$tp" && -r "$tp" ]]; then
                stamp=$(stat -c '%d:%i %s %y %z' -- "$tp" 2>/dev/null)
                file_id=${stamp%% *}; rest=${stamp#* }; size=${rest%% *}
                cached_stamp=''
                if [[ "$size" =~ ^[0-9]+$ ]]; then
                    models='{}'
                    mapfile -t cached < <(jq -r --arg sid "$sid" --arg tp "$tp" --arg model "$main_model" \
                        --arg id "$file_id" --argjson size "$size" '
                        select(.session == $sid and .transcript == $tp and
                            .file_id == $id and (.size | type) == "number" and .size >= 0 and .size <= $size) |
                        . as $cache | (.models | if type == "object" then . else {} end |
                            with_entries(select(.value == "auto" or (.value | type == "string" and
                                test("^([1-9][0-9]{5}|1000000)$"))))) |
                        tojson, (.[$model] // ""), ($cache.stamp // "")' "$cache" 2>/dev/null)
                    [[ "${cached[0]:-}" == \{* ]] && models=${cached[0]}
                    live=${cached[1]:-}; cached_stamp=${cached[2]:-}
                    if [[ "$stamp" != "$cached_stamp" ]]; then
                        mapfile -t updated < <(tail -c 65536 -- "$tp" 2>/dev/null |
                            jq -Rrn --arg sid "$sid" --arg model "$main_model" --argjson models "$models" '
                            def model_key: ascii_downcase | sub("^claude-"; "") | sub("-[0-9]{8}$"; "") |
                                gsub("[^a-z0-9]+"; "-") | gsub("^-|-$"; "");
                            def window:
                                ascii_downcase | gsub("^\\s+|\\s+$"; "") |
                                if . == "auto" or . == "reset" or . == "unset" or . == "default" then "auto"
                                else try (capture("^(?<n>[0-9]+(?:\\.[0-9]+)?)(?<u>[km]?)$") |
                                    (.n | tonumber) as $n |
                                    (if .u == "m" then $n * 1000000 elif .u == "k" then $n * 1000
                                     elif $n >= 100 and $n <= 1000 then $n * 1000 else $n end) |
                                    select(. >= 100000 and . <= 1000000) | floor | tostring) catch empty end;
                            def applied:
                                capture("^<local-command-stdout>Auto-compact window(?: for (?<model>.+?))? set to (?<n>\\S+)(?: tokens(?: \\(capped to model limit of [^)]*\\))?)?</local-command-stdout>$") |
                                (.n | window) as $value |
                                {key: ((.model // $model) | model_key), value: $value};
                            def stdout:
                                # Interactive results are user messages; print mode
                                # uses system/local_command with the same stdout.
                                if .type == "user" and (.message.content | type) == "string" then .message.content
                                elif .type == "system" and .subtype == "local_command" and
                                    (.content | type) == "string" then .content else empty end;
                            reduce inputs as $line ($models;
                                (try ($line | fromjson) catch null) as $e |
                                . as $state | try (
                                if ($e | type) != "object" or ($e.sessionId // $sid) != $sid or $e.isSidechain == true then .
                                else ([$e | stdout | applied][0] // null) as $result |
                                    if $result then .[$result.key] = $result.value else . end
                                end) catch $state) | tojson, (.[$model] // "")' 2>/dev/null)
                        if [[ "${updated[0]:-}" == \{* ]]; then
                            models=${updated[0]}; live=${updated[1]:-}
                        fi
                        # Atomic and best effort: a read-only cache never breaks the line.
                        if mkdir -p -- "$cache_dir" 2>/dev/null && tmp=$(mktemp "$cache_dir/.compact.XXXXXX" 2>/dev/null); then
                            trap 'rm -f -- "$tmp" 2>/dev/null' EXIT
                            jq -n --arg sid "$sid" --arg tp "$tp" --arg id "$file_id" \
                                --arg stamp "$stamp" --argjson size "$size" --argjson models "$models" \
                                '{session:$sid, transcript:$tp, file_id:$id, size:$size, stamp:$stamp, models:$models}' \
                                > "$tmp" 2>/dev/null && mv -f -- "$tmp" "$cache" 2>/dev/null
                            rm -f -- "$tmp" 2>/dev/null
                            trap - EXIT
                            # At most daily, only on a changed main transcript. The
                            # marker check is constant work; pruning visits owned files.
                            printf -v now '%(%s)T' -1
                            pruned=$(stat -c '%Y' -- "$cache_dir/.pruned" 2>/dev/null)
                            [[ "$pruned" =~ ^[0-9]+$ ]] || pruned=0
                            if (( now - pruned >= 86400 )); then
                                find "$cache_dir" -maxdepth 1 -type f -mtime +30 \
                                    \( -name '*.json' -o -name '.compact.*' \) -delete 2>/dev/null &&
                                    touch -- "$cache_dir/.pruned" 2>/dev/null
                            fi
                        fi
                    fi
                fi
            fi
            [[ "$live" == auto || "$live" =~ ^([1-9][0-9]{5}|1000000)$ ]] || live=''
        fi
    fi
    cfg=''
    # The runtime/live sources are sufficient on most managed refreshes.
    if [[ ( -z "$recorded" && -z "$live" ) || "$live" == auto ]]; then
        for f in "$config_dir/settings.json" "$proj/.claude/settings.json" "$proj/.claude/settings.local.json"; do
            [[ -r "$f" ]] || continue
            # Gateway IDs come as "Claude-Fable-5.2": compare lowercased, dots as dashes.
            v=$(jq -r --arg m "$mid" '
                def norm: ascii_downcase | gsub("\\."; "-");
                ((.modelSettings // {}) | to_entries | map(select(.key as $k | ($m | norm) | startswith($k | norm)))
                  | sort_by(.key | length) | last | .value.autoCompactWindow) // .autoCompactWindow // empty' "$f" 2>/dev/null)
            [[ "$v" =~ ^[0-9]{1,9}$ ]] && cfg=$((10#$v))
        done
        # --autocompact on the launching claude process (flag beats settings, loses to env)
        pid=$PPID
        for _ in 1 2 3 4; do
            [[ -n "$live" ]] && break # native /autocompact clears the launch flag
            [[ -r /proc/$pid/cmdline ]] || break
            mapfile -d '' -t argv < "/proc/$pid/cmdline"
            for i in "${!argv[@]}"; do
                case "${argv[i]}" in
                    --autocompact=*) fl=${argv[i]#*=} ;;
                    --autocompact)   fl=${argv[i+1]:-} ;;
                    *) continue ;;
                esac
                fl=$(window_tokens "$fl") && cfg=$fl
                break 2
            done
            pid=$(awk '{print $4}' "/proc/$pid/stat" 2>/dev/null); [[ "$pid" =~ ^[0-9]+$ ]] && (( pid > 1 )) || break
        done
        ew=${CLAUDE_CODE_AUTO_COMPACT_WINDOW:-}
        ew=$(window_tokens "$ew") && cfg=$ew
    fi
    if [[ -n "$cfg" ]]; then
        compact_window=$cfg
        (( compact_window < 100000 )) && compact_window=100000
        (( compact_window > win )) && compact_window=$win
    elif (( win >= 1000000 )); then compact_window=1000000
    else compact_window=$win
    fi
    if [[ -n "$live" && "$live" != auto ]]; then
        compact_window=$((10#$live))
        (( compact_window > win )) && compact_window=$win
    fi
    # Claude Code 2.1.321 transcript compactMetadata.preTokens: windows of
    # 300k/350k/500k compact at about 269k/317-320k/468k; a recorded 150k trigger
    # compacts at about 150.5k. Reserve = capped output plus 13000 summary tokens.
    thr=$(( compact_window - reserve ))
    ov=${CLAUDE_AUTOCOMPACT_PCT_OVERRIDE:-}
    if [[ "$ov" =~ ^[0-9]{1,3}$ ]] && (( 10#$ov > 0 && 10#$ov <= 100 )); then
        pct_thr=$(( (compact_window - reserve + 13000) * 10#$ov / 100 ))
        (( pct_thr < thr )) && thr=$pct_thr
    fi
    # A native reset returns to settings/defaults. The recorded trigger is
    # authoritative only while no live command has replaced its launch setting.
    [[ -n "$recorded" && -z "$live" ]] && thr=$recorded
    (( thr > win )) && thr=$win
    (( thr < 0 )) && thr=0
    thr_pct=$(( thr * 100 / win ))
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
