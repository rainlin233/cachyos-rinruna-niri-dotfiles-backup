#!/usr/bin/env bash
# Niri 手柄防息屏：有手柄连接时持有 systemd idle 锁，拔掉后晃一下鼠标唤醒空闲计时器
set -uo pipefail

# 单实例：niri 重启时旧进程没死透也不会跑重
LOCK_FILE="${XDG_RUNTIME_DIR:-/tmp}/gamepad-keepawake.lock"
exec 9>"$LOCK_FILE"
flock -n 9 || exit 0

INHIBIT_PID=""
HAS_DOTOOL=""
command -v dotool >/dev/null 2>&1 && HAS_DOTOOL=1

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
    if [[ -n "$HAS_DOTOOL" ]]; then
        dotool << 'EOF'
mousemove 50 50
mousemove -50 -50
EOF
    fi
}

# 手柄是否在线：传统 js* 节点，或名字像手柄的 evdev 设备
gamepad_present() {
    compgen -G "/dev/input/js*" > /dev/null && return 0

    local node name lower
    for node in /dev/input/event*; do
        [ -e "$node" ] || continue
        name="$(cat "/sys/class/input/${node##*/}/device/name" 2>/dev/null)" || continue
        lower="${name,,}"
        # 先排除键鼠触屏类（比如名字带 Wheel 的鼠标），再匹配手柄类
        case "$lower" in
            *mouse*|*keyboard*|*touchpad*|*trackpoint*|*touchscreen*|*tablet*|*wacom*|*pen*|*stylus*|*receiver*|*kvm*) continue ;;
        esac
        case "$lower" in
            *gamepad*|*controller*|*joystick*|*joy-con*|*xbox*|*playstation*|*dualshock*|*dualsense*|*8bitdo*|*nintendo*|*wheel*|*guitar*|*drum*|*fightstick*|*arcade*|*dance*) return 0 ;;
        esac
    done
    return 1
}

apply_state() {
    if gamepad_present; then
        if [[ -z "$INHIBIT_PID" ]] || ! kill -0 "$INHIBIT_PID" 2>/dev/null; then
            systemd-inhibit --why="Gamepad Active" --who="Niri Gamepad Inhibitor" --what="idle" sleep infinity &
            INHIBIT_PID=$!
        fi
    else
        if [[ -n "$INHIBIT_PID" ]]; then
            cleanup_and_wake
        fi
    fi
}

trap cleanup_and_wake EXIT

apply_state # 启动时先扫一遍，覆盖 niri 启动前就插着手柄的情况

# 事件驱动即时响应 + 60 秒超时兜底（防止事件丢失后永远不同步）
while true; do
    if inotifywait -e create -e delete -e move -t 60 --format '%e' /dev/input 2>/dev/null; then
        sleep 0.5 # 等设备节点稳定
    else
        [ "$?" -eq 2 ] || sleep 10 # 2 = 超时；其他错误退避 10 秒
    fi
    apply_state
done
