#!/usr/bin/env bash

set -u

QQ_RUNTIME="/run/user/$UID/app/com.qq.QQ"

find_xvfb() {
    local line display auth

    while IFS= read -r line; do
        [[ "$line" =~ Xvfb[[:space:]]+(:[0-9]+) ]] || continue
        display="${BASH_REMATCH[1]}"

        [[ "$line" =~ -auth[[:space:]]([^[:space:]]+) ]] || continue
        auth="${BASH_REMATCH[1]}"

        [[ "$auth" == "$QQ_RUNTIME/"* ]] || continue
        [[ -f "$auth" ]] || continue

        printf '%s\n%s\n' "$display" "$auth"
        return 0
    done < <(ps -eo args= | grep '[X]vfb' || true)

    return 1
}

while true; do
    xvfb="$(find_xvfb || true)"

    if [[ -z "$xvfb" ]]; then
        sleep 2
        continue
    fi

    DISPLAY="$(sed -n '1p' <<< "$xvfb")"
    XAUTHORITY="$(sed -n '2p' <<< "$xvfb")"

    export DISPLAY
    export XAUTHORITY

    last_text=""
    last_image=""

    while true; do
        xvfb_pid="$(pgrep -f "^Xvfb $DISPLAY " | head -n1)"

        if [[ -z "$xvfb_pid" ]] || ! kill -0 "$xvfb_pid" 2>/dev/null; then
            break
        fi

        targets="$(xclip -selection clipboard -target TARGETS -o 2>/dev/null || true)"

        if grep -qx 'image/png' <<< "$targets"; then
            tmp_image="$(mktemp)"

            if xclip -selection clipboard -target image/png -o > "$tmp_image" 2>/dev/null && [[ -s "$tmp_image" ]]; then
                hash="$(sha256sum "$tmp_image" | cut -d' ' -f1)"

                if [[ "$hash" != "$last_image" ]]; then
                    wl-copy --type image/png < "$tmp_image"
                    last_image="$hash"
                    last_text=""
                fi
            fi

            rm -f "$tmp_image"

        elif grep -Eq '^(UTF8_STRING|STRING|text/plain|text/plain;charset=utf-8)$' <<< "$targets"; then
            current="$(xclip -selection clipboard -o 2>/dev/null || true)"

            if [[ -n "$current" && "$current" != "$last_text" ]]; then
                printf '%s' "$current" | wl-copy
                last_text="$current"
                last_image=""
            fi
        fi

        sleep 2
    done

    unset DISPLAY
    unset XAUTHORITY
done
