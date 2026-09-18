#!/usr/bin/env bash
# dotfiles-sync — one-way auto-sync: live system ($HOME, /etc) -> ~/dotfiles (git repo)
#
# Usage:
#   dotfiles-sync.sh          one-shot sync + commit + push (default action)
#                     (started via niri spawn-at-startup, runs once per login)
#
# Rules:
#   - ALWAYS edit the HOME copy (system folders). The repo is a read-only mirror;
#     anything edited directly in the repo gets overwritten by the next sync.
#   - Full-sync trees (rsync, deletions propagate): .config/niri .config/fish
#     .config/noctalia .config/fastfetch .local/share/applications .local/share/icons .local/share/icons
#   - Whitelist mode (git-tracked files only): .local/bin (deletions propagate),
#     /etc/udev/rules.d (never auto-delete repo copies)
#   - Excluded from sync: niri effects.kdl (eyecare mode-pointer symlink),
#     fish fish_variables* (rewritten on every shell exit), editor backups.
set -uo pipefail

REPO="$HOME/dotfiles"
STATE_DIR="$HOME/.local/share/dotfiles-sync"
LOG="$STATE_DIR/sync.log"
LOCK="$STATE_DIR/lock"

FULL_DIRS=(.config/niri .config/fish .config/noctalia .config/fastfetch .local/share/applications .local/share/icons)
SINGLE_FILES=(.config/starship.toml)
export GIT_SSH_COMMAND="ssh -o BatchMode=yes -o ConnectTimeout=15"

log() {
    mkdir -p "$STATE_DIR"
    if [ -f "$LOG" ] && [ "$(wc -l <"$LOG")" -gt 3000 ]; then
        tail -n 1000 "$LOG" >"$LOG.tmp" && mv "$LOG.tmp" "$LOG"
    fi
    printf '%s %s\n' "$(date '+%F %T')" "$*" >>"$LOG"
}

sync_tree() { # $1 = repo-relative dir, synced $HOME/<dir> -> $REPO/<dir>
    local rel="$1"
    local src="$HOME/$rel" dst="$REPO/$rel"
    [ -d "$src" ] || { log "skip missing dir: $src"; return 0; }
    mkdir -p "$dst"
    local -a x=(--exclude='*~' --exclude='*.swp' --exclude='*.swo' --exclude='icon-theme.cache')
    case "$rel" in
        .config/niri) x+=(--exclude='/effects.kdl') ;;
        .config/fish) x+=(--exclude='/fish_variables*') ;;
    esac
    rsync -a --delete "${x[@]}" "$src/" "$dst/" || { log "rsync FAILED: $rel"; return 1; }
}

sync_file() { # $1 = repo-relative file, synced $HOME/<file> -> $REPO/<file>
    local rel="$1"
    local src="$HOME/$rel" dst="$REPO/$rel"
    [ -f "$src" ] || { log "notice: $rel missing in HOME, keeping repo copy"; return 0; }
    mkdir -p "$(dirname "$dst")"
    cmp -s "$src" "$dst" || cp -p "$src" "$dst"
}

sync_whitelist() { # $1 = source prefix (use $HOME or empty for /)  $2 = repo subdir  $3 = rm|keep
    local prefix="$1" sub="$2" rmmode="$3" f src dst
    while IFS= read -r f; do
        [ -n "$f" ] || continue
        src="${prefix}/${f}"
        dst="$REPO/$f"
        if [ -f "$src" ] || [ -L "$src" ]; then
            if ! cmp -s "$src" "$dst" 2>/dev/null; then
                mkdir -p "$(dirname "$dst")"
                cp -p "$src" "$dst" && log "updated: $f"
            fi
        else
            if [ "$rmmode" = rm ]; then
                git -C "$REPO" rm -q "$f" && log "removed: $f"
            else
                log "notice: $f missing at $src, keeping repo copy"
            fi
        fi
    done < <(git -C "$REPO" ls-files "$sub")
}

commit_and_push() {
    git -C "$REPO" add -A -- .config .local etc || { log "git add FAILED"; return 1; }
    local pending
    pending="$(git -C "$REPO" status --porcelain -- .config .local etc)"
    if [ -n "$pending" ]; then
        if git -C "$REPO" commit -q -m "Auto-sync $(date '+%F %T')" -m "$pending"; then
            log "committed changes"
        else
            log "git commit FAILED"; return 1
        fi
    fi
    local ahead
    ahead="$(git -C "$REPO" rev-list --count '@{u}..HEAD' 2>/dev/null || echo 0)"
    if [ "$ahead" -gt 0 ]; then
        if timeout 90 git -C "$REPO" push -q 2>>"$LOG"; then
            log "pushed ($ahead commit(s))"
        else
            log "push FAILED (kept locally, will retry next run)"
        fi
    fi
}

do_sync() {
    local d f
    for d in "${FULL_DIRS[@]}"; do sync_tree "$d"; done
    for f in "${SINGLE_FILES[@]}"; do sync_file "$f"; done
    sync_whitelist "$HOME" .local/bin rm
    sync_whitelist "" etc/udev/rules.d keep
    commit_and_push
}

case "${1:-}" in
    -h|--help) echo "usage: $0 [-h|--help]"; exit 0 ;;
    ""|--sync-now) : ;;
    *) echo "unknown argument: $1" >&2; exit 1 ;;
esac
mkdir -p "$STATE_DIR"
exec 9>"$LOCK"
flock -n 9 || { echo "dotfiles-sync: another instance is running"; exit 0; }
log "sync started (pid $$)"
do_sync
