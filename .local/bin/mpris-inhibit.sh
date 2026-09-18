#!/usr/bin/env bash

INHIBIT_PID=""
declare -A PLAYERS


cleanup() {
    if [ -n "$INHIBIT_PID" ] && kill -0 "$INHIBIT_PID" 2>/dev/null; then
        kill "$INHIBIT_PID" 2>/dev/null
        wait "$INHIBIT_PID" 2>/dev/null
    fi
}

trap cleanup EXIT INT TERM HUP


start_inhibit() {
    if [ -n "$INHIBIT_PID" ] && kill -0 "$INHIBIT_PID" 2>/dev/null; then
        return
    fi

    systemd-inhibit \
        --who="MPRIS Player" \
        --why="MPRIS Media Playing" \
        --what=sleep \
        --mode=block \
        sleep infinity &

    INHIBIT_PID=$!
}


stop_inhibit() {
    if [ -n "$INHIBIT_PID" ]; then
        kill "$INHIBIT_PID" 2>/dev/null
        wait "$INHIBIT_PID" 2>/dev/null
        INHIBIT_PID=""
    fi
}


update_inhibit() {
    for status in "${PLAYERS[@]}"; do
        if [ "$status" = "Playing" ]; then
            start_inhibit
            return
        fi
    done

    stop_inhibit
}


while IFS=$'\t' read -r player status; do
    PLAYERS["$player"]="$status"
    update_inhibit
done < <(
    playerctl -a metadata --format '{{playerName}}\t{{status}}' --follow 2>/dev/null
)
