#!/usr/bin/env bash
set -euo pipefail

# Bulk git gc across all repos found under a directory tree
# Usage: git-bulk-gc.sh [-j N] [-n|--dry-run] [-a|--aggressive] [--no-resume] [-h|--help] [root_dir]

usage() {
    cat <<'EOF'
Bulk git gc across all repos found under a directory tree
Usage: git-bulk-gc.sh [-j N] [-n|--dry-run] [-a|--aggressive] [--no-resume] [-h|--help] [root_dir]
  -j N              parallelism (default: nproc/2, min 1)
  -n|--dry-run      scan and report sizes, don't modify anything
  -a|--aggressive   use git gc --aggressive
  --no-resume       start fresh, ignore previous CSV progress (default: resume)
  -h|--help         show this help and exit
  root_dir          directory to scan (default: current directory)

Output files (written to current working directory):
  git-bulk-gc-success.csv / git-bulk-gc-aggressive-success.csv
  git-bulk-gc-failures.csv / git-bulk-gc-aggressive-failures.csv
  git-bulk-gc-logs/ / git-bulk-gc-aggressive-logs/
EOF
    exit 0
}

# --- Detect defaults ---

default_jobs() {
    local cpus
    cpus=$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 2)
    local j=$(( cpus / 2 ))
    [ "$j" -lt 1 ] && j=1
    echo "$j"
}

PARALLEL=""
ROOT=""
DRY_RUN=0
AGGRESSIVE=0
NO_RESUME=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            usage
            ;;
        -j)
            PARALLEL="${2:?'-j requires a number'}"
            shift 2
            ;;
        -j*)
            PARALLEL="${1#-j}"
            shift
            ;;
        -n|--dry-run)
            DRY_RUN=1
            shift
            ;;
        -a|--aggressive)
            AGGRESSIVE=1
            shift
            ;;
        --no-resume)
            NO_RESUME=1
            shift
            ;;
        *)
            ROOT="$1"
            shift
            ;;
    esac
done

[ -z "$PARALLEL" ] && PARALLEL=$(default_jobs)
[ -z "$ROOT" ] && ROOT="$(pwd)"

if ! [[ "$PARALLEL" =~ ^[1-9][0-9]*$ ]]; then
    echo "Error: -j requires a positive integer, got '$PARALLEL'" >&2
    exit 1
fi

if [ ! -d "$ROOT" ]; then
    echo "Error: root directory '$ROOT' does not exist" >&2
    exit 1
fi

# --- Output naming ---

PREFIX="git-bulk-gc"
[ "$AGGRESSIVE" -eq 1 ] && PREFIX="git-bulk-gc-aggressive"

OUTDIR="$(pwd)"
if [ "$DRY_RUN" -eq 1 ]; then
    REPORT_SUCCESS="$OUTDIR/${PREFIX}-dryrun.csv"
    REPORT_FAILURE="$OUTDIR/${PREFIX}-dryrun-errors.csv"
else
    REPORT_SUCCESS="$OUTDIR/${PREFIX}-success.csv"
    REPORT_FAILURE="$OUTDIR/${PREFIX}-failures.csv"
fi
LOGDIR="$OUTDIR/${PREFIX}-logs"
STATUSDIR=$(mktemp -d)
START_TIME=$(date +%s)
RESUMING=0
SKIPPED_DONE=0

mkdir -p "$LOGDIR"

# --- EPOCHREALTIME fallback ---

now_ms() {
    if [ -n "${EPOCHREALTIME:-}" ]; then
        local t="${EPOCHREALTIME}"
        t="${t/./}"
        echo "${t:0:13}"
    else
        local ns
        ns=$(date +%s%N 2>/dev/null || echo "$(date +%s)000000000")
        echo "${ns:0:13}"
    fi
}

# --- Resume logic: collect already-processed repos from existing CSVs ---

DONE_LIST="$STATUSDIR/done_repos.txt"
touch "$DONE_LIST"

write_csv_headers() {
    if [ "$DRY_RUN" -eq 1 ]; then
        [ -f "$REPORT_SUCCESS" ] || echo "ts,repo,tree,git_dir_mb,loose_objects,in_pack_objects,total_objects,num_packs,loose_size_kb,size_pack_kb,log_file" > "$REPORT_SUCCESS"
        [ -f "$REPORT_FAILURE" ] || echo "ts,repo,tree,error_summary,log_file" > "$REPORT_FAILURE"
    else
        [ -f "$REPORT_SUCCESS" ] || echo "ts,repo,tree,size_before_mb,size_after_mb,saved_mb,saved_pct,num_objects,num_packs,gc_duration_secs,log_file" > "$REPORT_SUCCESS"
        [ -f "$REPORT_FAILURE" ] || echo "ts,repo,tree,size_before_mb,size_after_mb,gc_exit_code,error_summary,log_file" > "$REPORT_FAILURE"
    fi
}

if [ "$NO_RESUME" -eq 0 ] && { [ -f "$REPORT_SUCCESS" ] || [ -f "$REPORT_FAILURE" ]; }; then
    if [ -f "$REPORT_SUCCESS" ]; then
        awk -F, 'NR>1 && $2 ~ /./{print $2}' "$REPORT_SUCCESS" >> "$DONE_LIST"
    fi
    if [ -f "$REPORT_FAILURE" ]; then
        awk -F, 'NR>1 && $2 ~ /./{print $2}' "$REPORT_FAILURE" >> "$DONE_LIST"
    fi
    SKIPPED_DONE=$(wc -l < "$DONE_LIST")
    if [ "$SKIPPED_DONE" -gt 0 ]; then
        RESUMING=1
    fi
    write_csv_headers
else
    rm -f "$REPORT_SUCCESS" "$REPORT_FAILURE"
    write_csv_headers
fi

# --- Pre-scan: find repos and build tree map ---

find_repos() {
    find "$ROOT" -name .git -type d -prune 2>/dev/null | while read -r gitdir; do
        dirname "$gitdir"
    done
}

echo -n "Scanning repositories..."
REPO_LIST_ALL="$STATUSDIR/repos_all.txt"
REPO_LIST="$STATUSDIR/repos.txt"
find_repos > "$REPO_LIST_ALL"
TOTAL_ALL=$(wc -l < "$REPO_LIST_ALL")
echo -e "\r\033[KScanning repositories... found $TOTAL_ALL"

# --- Resume filtering ---

if [ "$RESUMING" -eq 1 ]; then
    echo -n "Filtering completed repos for resume..."
    DONE_ABS="$STATUSDIR/done_abs.txt"
    while IFS= read -r relpath; do
        echo "$ROOT/$relpath"
    done < "$DONE_LIST" > "$DONE_ABS"
    grep -vxFf "$DONE_ABS" "$REPO_LIST_ALL" > "$REPO_LIST" || true
    TOTAL=$(wc -l < "$REPO_LIST")
    echo -e "\r\033[KResuming: $SKIPPED_DONE already done, $TOTAL remaining"
else
    cp "$REPO_LIST_ALL" "$REPO_LIST"
    TOTAL=$TOTAL_ALL
fi

declare -A TREE_TOTALS=()
declare -A TREE_SEEN=()
TREE_ORDER=()

echo -n "Building tree map..."
SCAN_COUNT=0
while IFS= read -r repo; do
    SCAN_COUNT=$((SCAN_COUNT + 1))
    if ((SCAN_COUNT % 100 == 0)); then
        echo -ne "\r\033[KBuilding tree map... $SCAN_COUNT / $TOTAL repos classified"
    fi
    relpath="${repo#"$ROOT"/}"
    slashes="${relpath//[^\/]/}"
    if [ "${#slashes}" -ge 2 ]; then
        key=$(echo "$relpath" | cut -d/ -f1-2)
    else
        key="(top-level)"
    fi
    TREE_TOTALS[$key]=$(( ${TREE_TOTALS[$key]:-0} + 1 ))
    if [ -z "${TREE_SEEN[$key]:-}" ]; then
        TREE_ORDER+=("$key")
        TREE_SEEN[$key]=1
    fi
done < "$REPO_LIST"

NUM_TREES=${#TREE_ORDER[@]}
echo -e "\r\033[KFound $TOTAL repositories across $NUM_TREES trees"

# --- Initialize status files ---

echo 0 > "$STATUSDIR/completed"
echo 0 > "$STATUSDIR/succeeded"
echo 0 > "$STATUSDIR/failed"
echo 0 > "$STATUSDIR/saved_total"
for tree in "${TREE_ORDER[@]}"; do
    stree="${tree//\//__}"
    echo "${TREE_TOTALS[$tree]}" > "$STATUSDIR/tree_${stree}_total"
    echo 0 > "$STATUSDIR/tree_${stree}_count"
done
printf '%s\n' "${TREE_ORDER[@]}" > "$STATUSDIR/trees.txt"
touch "$STATUSDIR/running"

echo ""
if [ "$DRY_RUN" -eq 1 ]; then
    if [ "$AGGRESSIVE" -eq 1 ]; then
        echo "=== DRY RUN (read-only audit, aggressive) ==="
    else
        echo "=== DRY RUN (read-only audit) ==="
    fi
else
    if [ "$AGGRESSIVE" -eq 1 ]; then
        echo "=== Aggressive gc ==="
    else
        echo "=== git gc ==="
    fi
fi
echo "Root:        $ROOT"
echo "Parallelism: $PARALLEL"
echo "Dry run:     $([ "$DRY_RUN" -eq 1 ] && echo 'YES — no changes will be made' || echo 'no')"
if [ "$RESUMING" -eq 1 ]; then
    echo "Resume:      YES — skipping $SKIPPED_DONE already-processed repos ($TOTAL remaining)"
else
    echo "Resume:      no (fresh run)"
fi
echo "Success CSV: $REPORT_SUCCESS"
echo "Failure CSV: $REPORT_FAILURE"
echo "Logs:        $LOGDIR/"
echo ""

# --- Progress bar ---

progress_bar() {
    local pct=$1 width=$2
    local filled=$((pct * width / 100))
    local empty=$((width - filled))
    local bar=""
    local i
    for ((i=0; i<filled; i++)); do bar+="█"; done
    for ((i=0; i<empty; i++)); do bar+="░"; done
    echo "$bar"
}

# --- Display renderer ---

DISPLAY_LINES=$((5 + NUM_TREES + PARALLEL))

render_display() {
    local now elapsed mins secs completed saved_mb succeeded failed opct obar
    now=$(date +%s)
    elapsed=$((now - START_TIME))
    mins=$((elapsed / 60))
    secs=$((elapsed % 60))

    completed=$(cat "$STATUSDIR/completed" 2>/dev/null)
    completed=${completed:-0}
    saved_mb=$(cat "$STATUSDIR/saved_total" 2>/dev/null)
    saved_mb=${saved_mb:-0}
    succeeded=$(cat "$STATUSDIR/succeeded" 2>/dev/null)
    succeeded=${succeeded:-0}
    failed=$(cat "$STATUSDIR/failed" 2>/dev/null)
    failed=${failed:-0}

    opct=0
    [ "$TOTAL" -gt 0 ] && opct=$((completed * 100 / TOTAL))
    obar=$(progress_bar "$opct" 30)
    printf "\033[K  Overall: [%4d/%4d]  %s  %3d%%  (elapsed %dm %02ds)\n" \
        "$completed" "$TOTAL" "$obar" "$opct" "$mins" "$secs"
    printf "\033[K  Saved: %dMB  |  OK: %d  |  Failed: %d\n" \
        "$saved_mb" "$succeeded" "$failed"
    printf "\033[K\n"

    while IFS= read -r tree; do
        local stree="${tree//\//__}"
        local tc tt tpct tbar
        tc=$(cat "$STATUSDIR/tree_${stree}_count" 2>/dev/null)
        tc=${tc:-0}
        tt=$(cat "$STATUSDIR/tree_${stree}_total" 2>/dev/null)
        tt=${tt:-0}
        tpct=0
        [ "$tt" -gt 0 ] && tpct=$((tc * 100 / tt))
        tbar=$(progress_bar "$tpct" 20)
        printf "\033[K  %-42s [%4d/%4d]  %s  %3d%%\n" "$tree" "$tc" "$tt" "$tbar" "$tpct"
    done < "$STATUSDIR/trees.txt"

    printf "\033[K\n"
    printf "\033[K  Active:\n"

    local shown=0
    for f in "$STATUSDIR"/active_*; do
        [ -f "$f" ] 2>/dev/null || continue
        local line
        line=$(cat "$f" 2>/dev/null || echo "")
        [ -z "$line" ] && continue
        printf "\033[K    %s\n" "$line"
        shown=$((shown + 1))
    done
    local i
    for ((i=shown; i<PARALLEL; i++)); do
        printf "\033[K    (idle)\n"
    done
}

# --- Monitor (foreground, reads keyboard for ESC cancel) ---

monitor() {
    local last_esc=0
    local esc_pending=0
    local has_tty=0
    if [ -t 0 ]; then
        has_tty=1
    elif [ -c /dev/tty ] 2>/dev/null; then
        local _probe_exit=0
        IFS= read -rsn1 -t 0.01 _ </dev/tty 2>/dev/null || _probe_exit=$?
        if [ "$_probe_exit" -gt 128 ]; then
            has_tty=1
        fi
    fi

    if [ "$has_tty" -eq 1 ]; then
        local total_lines=$((DISPLAY_LINES + 1))
        render_display
        printf "\033[K  Press ESC twice to cancel\n"
    else
        local total_lines=$DISPLAY_LINES
        render_display
    fi

    while [ -f "$STATUSDIR/running" ]; do
        local key=""
        if [ "$has_tty" -eq 1 ]; then
            IFS= read -rsn1 -t 0.5 key </dev/tty 2>/dev/null || true
        else
            sleep 0.5
        fi

        if [ "$key" = $'\x1b' ]; then
            local ts
            ts=$(now_ms)
            if [ "$esc_pending" -eq 1 ] && [ $((ts - last_esc)) -le 2000 ]; then
                printf "\033[${total_lines}A"
                render_display
                if [ "$has_tty" -eq 1 ]; then
                    printf "\033[K  Cancelling...\n"
                fi
                kill -INT $$ 2>/dev/null || true
                return
            else
                esc_pending=1
                last_esc=$ts
            fi
        fi

        printf "\033[${total_lines}A"
        render_display
        if [ "$has_tty" -eq 1 ]; then
            if [ "$esc_pending" -eq 1 ]; then
                local ts
                ts=$(now_ms)
                if [ $((ts - last_esc)) -le 2000 ]; then
                    printf "\033[K  >> Press ESC again within 2s to cancel <<\n"
                else
                    esc_pending=0
                    printf "\033[K  Press ESC twice to cancel\n"
                fi
            else
                printf "\033[K  Press ESC twice to cancel\n"
            fi
        fi
    done
    printf "\033[${total_lines}A"
    render_display
    if [ "$has_tty" -eq 1 ]; then
        printf "\033[K\n"
    fi
}

# --- Worker ---

process_repo() {
    set -euo pipefail
    local repo="$1"
    local relpath="${repo#"$ROOT"/}"
    local gitdir="$repo/.git"
    local safename="${relpath//\//__}"
    local logfile="$LOGDIR/${safename}.log"

    trap 'rm -f "$STATUSDIR/active_$$"' EXIT

    local tree slashes
    slashes="${relpath//[^\/]/}"
    if [ "${#slashes}" -ge 2 ]; then
        tree=$(echo "$relpath" | cut -d/ -f1-2)
    else
        tree="(top-level)"
    fi

    echo "$relpath — measuring size..." > "$STATUSDIR/active_$$"

    exec > "$logfile" 2>&1

    echo "=== Processing: $relpath ==="
    echo "Timestamp: $(date -Iseconds)"
    echo "Tree: $tree"
    echo "Mode: $([ "$DRY_RUN" -eq 1 ] && echo 'DRY RUN' || echo 'LIVE')"

    local git_dir_mb
    git_dir_mb=$(du -sm "$gitdir" | cut -f1)
    echo "Git dir size: ${git_dir_mb}MB"

    echo "$relpath — ${git_dir_mb}MB — counting objects..." > "$STATUSDIR/active_$$"

    local count_output loose_objects in_pack_objects total_objects num_packs loose_size_kb size_pack_kb
    count_output=$(git -C "$repo" count-objects -v 2>&1 || echo "")
    echo "$count_output"
    loose_objects=$(echo "$count_output" | awk '/^count:/{print $2}')
    loose_objects=${loose_objects:-0}
    in_pack_objects=$(echo "$count_output" | awk '/^in-pack:/{print $2}')
    in_pack_objects=${in_pack_objects:-0}
    total_objects=$((loose_objects + in_pack_objects))
    num_packs=$(echo "$count_output" | awk '/^packs:/{print $2}')
    num_packs=${num_packs:-0}
    loose_size_kb=$(echo "$count_output" | awk '/^size:/{print $2}')
    loose_size_kb=${loose_size_kb:-0}
    size_pack_kb=$(echo "$count_output" | awk '/^size-pack:/{print $2}')
    size_pack_kb=${size_pack_kb:-0}

    # ================================================================
    # DRY RUN: report only, no modifications
    # ================================================================
    if [ "$DRY_RUN" -eq 1 ]; then
        echo "$relpath — ${git_dir_mb}MB — writing results..." > "$STATUSDIR/active_$$"

        local scan_ok=1
        local error_summary=""
        if [ -z "$count_output" ] || echo "$count_output" | grep -qi 'fatal\|error'; then
            scan_ok=0
            error_summary=$(echo "$count_output" | tr '\n' '|' | sed 's/,/;/g')
        fi

        echo "=== Dry run complete: $relpath ==="

        (
            flock 9

            local count
            count=$(cat "$STATUSDIR/completed")
            echo $((count + 1)) > "$STATUSDIR/completed"

            local stree="${tree//\//__}"
            local tcount
            tcount=$(cat "$STATUSDIR/tree_${stree}_count")
            echo $((tcount + 1)) > "$STATUSDIR/tree_${stree}_count"

            if [ "$scan_ok" -eq 1 ]; then
                local sc
                sc=$(cat "$STATUSDIR/succeeded")
                echo $((sc + 1)) > "$STATUSDIR/succeeded"

                echo "$(date -Iseconds),$relpath,$tree,$git_dir_mb,$loose_objects,$in_pack_objects,$total_objects,$num_packs,$loose_size_kb,$size_pack_kb,$logfile" >> "$REPORT_SUCCESS"
            else
                local fc
                fc=$(cat "$STATUSDIR/failed")
                echo $((fc + 1)) > "$STATUSDIR/failed"

                echo "$(date -Iseconds),$relpath,$tree,$error_summary,$logfile" >> "$REPORT_FAILURE"
            fi
        ) 9>"$STATUSDIR/lock"

        return 0
    fi

    # ================================================================
    # LIVE RUN: git gc
    # ================================================================
    local gc_exit=0
    local size_before="$git_dir_mb"

    local gc_label="gc"
    [ "$AGGRESSIVE" -eq 1 ] && gc_label="aggressive gc"
    echo "$relpath — ${size_before}MB — $gc_label running" > "$STATUSDIR/active_$$"

    local -a gc_args=(gc --prune=now)
    [ "$AGGRESSIVE" -eq 1 ] && gc_args=(gc --aggressive --prune=now)
    echo "Running git ${gc_args[*]} ..."
    local gc_start gc_end gc_duration
    gc_start=$(date +%s)
    gc_exit=0
    git -C "$repo" "${gc_args[@]}" 2>&1 || gc_exit=$?
    gc_end=$(date +%s)
    gc_duration=$((gc_end - gc_start))

    if [ "$gc_exit" -eq 0 ]; then
        echo "gc completed successfully"
    else
        echo "WARN: gc exited with code $gc_exit"
    fi
    echo "gc duration: ${gc_duration}s"

    local size_after
    size_after=$(du -sm "$gitdir" | cut -f1)
    echo "Size after: ${size_after}MB"

    local saved=$((size_before - size_after))
    local pct=0
    if [ "$size_before" -gt 0 ]; then
        pct=$((saved * 100 / size_before))
    fi

    echo "Saved: ${saved}MB (${pct}%)"
    echo "=== Done: $relpath ==="

    (
        flock 9

        local count
        count=$(cat "$STATUSDIR/completed")
        echo $((count + 1)) > "$STATUSDIR/completed"

        local stree="${tree//\//__}"
        local tcount
        tcount=$(cat "$STATUSDIR/tree_${stree}_count")
        echo $((tcount + 1)) > "$STATUSDIR/tree_${stree}_count"

        local stotal
        stotal=$(cat "$STATUSDIR/saved_total")
        echo $((stotal + saved)) > "$STATUSDIR/saved_total"

        if [ "$gc_exit" -eq 0 ]; then
            local sc
            sc=$(cat "$STATUSDIR/succeeded")
            echo $((sc + 1)) > "$STATUSDIR/succeeded"

            echo "$(date -Iseconds),$relpath,$tree,$size_before,$size_after,$saved,$pct,$total_objects,$num_packs,$gc_duration,$logfile" >> "$REPORT_SUCCESS"
        else
            local fc
            fc=$(cat "$STATUSDIR/failed")
            echo $((fc + 1)) > "$STATUSDIR/failed"

            local error_summary
            error_summary=$(tail -5 "$logfile" 2>/dev/null | tr '\n' '|' | sed 's/,/;/g')
            echo "$(date -Iseconds),$relpath,$tree,$size_before,$size_after,$gc_exit,$error_summary,$logfile" >> "$REPORT_FAILURE"
        fi
    ) 9>"$STATUSDIR/lock"
}

export -f process_repo now_ms
export ROOT REPORT_SUCCESS REPORT_FAILURE LOGDIR STATUSDIR DRY_RUN AGGRESSIVE

# --- Cleanup trap ---

XARGS_PID=""
WATCHER_PID=""

CLEANED_UP=0
cleanup() {
    [ "$CLEANED_UP" -eq 1 ] && return
    CLEANED_UP=1
    rm -f "$STATUSDIR/running"
    [ -n "$XARGS_PID" ] && kill "$XARGS_PID" 2>/dev/null || true
    [ -n "$WATCHER_PID" ] && kill "$WATCHER_PID" 2>/dev/null || true
    wait "$XARGS_PID" 2>/dev/null || true
    wait "$WATCHER_PID" 2>/dev/null || true
    rm -rf "$STATUSDIR"
}
trap 'cleanup; echo ""; echo "Interrupted. Partial reports saved to:"; echo "  Success: $REPORT_SUCCESS"; echo "  Failure: $REPORT_FAILURE"; exit 1' INT TERM
trap cleanup EXIT

# --- Run ---

if [ "$TOTAL" -eq 0 ]; then
    echo "Nothing to do — all $TOTAL_ALL repos already processed."
    rm -f "$STATUSDIR/running"
else
    xargs -d '\n' -P "$PARALLEL" -I {} bash -c 'process_repo "$@"' _ {} < "$REPO_LIST" &
    XARGS_PID=$!

    (while kill -0 "$XARGS_PID" 2>/dev/null; do sleep 0.5; done; rm -f "$STATUSDIR/running") &
    WATCHER_PID=$!

    monitor

    wait "$XARGS_PID" 2>/dev/null || true
    wait "$WATCHER_PID" 2>/dev/null || true
fi

echo ""
echo ""
if [ "$DRY_RUN" -eq 1 ]; then
    echo "=== Dry Run Complete ==="
elif [ "$AGGRESSIVE" -eq 1 ]; then
    echo "=== Aggressive gc Complete ==="
else
    echo "=== gc Complete ==="
fi

# --- Summary ---

success_count=$(awk -F, 'NR>1{c++}END{print c+0}' "$REPORT_SUCCESS")
fail_count=$(awk -F, 'NR>1{c++}END{print c+0}' "$REPORT_FAILURE")

if [ "$DRY_RUN" -eq 1 ]; then
    total_size=$(awk -F, 'NR>1{s+=$4}END{print s+0}' "$REPORT_SUCCESS")
    total_loose_kb=$(awk -F, 'NR>1{s+=$9}END{print s+0}' "$REPORT_SUCCESS")

    echo "Repos scanned:        $((success_count + fail_count))"
    echo "  Readable:           $success_count"
    echo "  Scan errors:        $fail_count"
    echo "Total .git size:      ${total_size}MB"
    echo "Total loose obj size: ${total_loose_kb}KB (minimum gc savings)"
    echo ""
    echo "Largest repos:"
    awk -F, 'NR>1 && $4>50{printf "  %6dMB %-53s (%s loose objects, %sKB loose)\n", $4, $2, $5, $9}' "$REPORT_SUCCESS" | sort -rn | head -20
else
    total_before=$(awk -F, 'NR>1{s+=$4}END{print s+0}' "$REPORT_SUCCESS")
    total_after=$(awk -F, 'NR>1{s+=$5}END{print s+0}' "$REPORT_SUCCESS")
    total_saved=$((total_before - total_after))

    echo "Repos processed: $((success_count + fail_count))"
    echo "  Succeeded:     $success_count"
    echo "  Failed:        $fail_count"
    echo "Total before:    ${total_before}MB"
    echo "Total after:     ${total_after}MB"
    echo "Total saved:     ${total_saved}MB"
    echo ""
    echo "Repos still > 50MB after gc:"
    awk -F, 'NR>1 && $5>50{printf "  %-60s %sMB\n", $2, $5}' "$REPORT_SUCCESS"
fi
echo ""
if [ "$fail_count" -gt 0 ]; then
    echo "Failed repos (see $REPORT_FAILURE):"
    if [ "$DRY_RUN" -eq 1 ]; then
        awk -F, 'NR>1{printf "  %-60s %s\n", $2, $4}' "$REPORT_FAILURE"
    else
        awk -F, 'NR>1{printf "  %-60s exit=%s\n", $2, $6}' "$REPORT_FAILURE"
    fi
    echo ""
fi
echo "Success report:  $REPORT_SUCCESS"
echo "Failure report:  $REPORT_FAILURE"
echo "Per-repo logs:   $LOGDIR/"
