#!/usr/bin/env bash
# MPRIS 媒体播放防挂起：任一播放器 Playing 时持有 systemd sleep 锁
# 只拦挂起（sleep），不拦息屏；状态每次按实时快照判断，无残留
set -uo pipefail

command -v playerctl >/dev/null 2>&1 || { echo "mpris-inhibit: playerctl not found" >&2; exit 1; }

# 单实例
LOCK_FILE="${XDG_RUNTIME_DIR:-/tmp}/mpris-inhibit.lock"
exec 9>"$LOCK_FILE"
flock -n 9 || exit 0

INHIBIT_PID=""

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
    if playerctl -a status 2>/dev/null | grep -qx "Playing"; then
        start_inhibit
    else
        stop_inhibit
    fi
}


while true; do
    update_inhibit # 先按快照来一遍，覆盖启动时已在播的情况
    # --follow 只当触发器：任何播放事件都重新快照，避免播放器退出后状态残留
    while IFS= read -r _; do
        update_inhibit
    done < <(playerctl -a metadata --follow 2>/dev/null)
    sleep 5
done
