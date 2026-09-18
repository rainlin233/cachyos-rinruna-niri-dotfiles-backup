#!/usr/bin/env bash

cleanup_and_wake() {
    if [[ -n "$INHIBIT_PID" ]] && kill -0 "$INHIBIT_PID" 2>/dev/null; then
        kill "$INHIBIT_PID" 2>/dev/null
        wait "$INHIBIT_PID" 2>/dev/null
    fi
    INHIBIT_PID=""

    # 1. 留出足够的 1 秒，确保 D-Bus 上的 inhibit 锁彻底解除
    sleep 1

    # 2. 连续发送两次 50 像素的相对位移（移出后立刻移回）
    # 50 像素绝对能突破 libinput 的防抖阈值，强制唤醒 Niri 的空闲计时器，且光标不会发生偏移
    dotool << 'EOF'
mousemove 50 50
mousemove -50 -50
EOF
}

trap cleanup_and_wake EXIT

while true; do
    if compgen -G "/dev/input/js*" > /dev/null; then
        if [[ -z "$INHIBIT_PID" ]] || ! kill -0 "$INHIBIT_PID" 2>/dev/null; then
            systemd-inhibit --why="Gamepad Active" --who="Niri Gamepad Inhibitor" --what="idle" sleep infinity &
            INHIBIT_PID=$!
        fi
        sleep 10
    else
        if [[ -n "$INHIBIT_PID" ]]; then
            cleanup_and_wake
        fi
        sleep 10
    fi
done
