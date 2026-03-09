#!/bin/bash
set -euo pipefail

REPO="git@github.com:grahamlopez/gentoo-configs"
GIT_DIR="/root/.gentoo-configs"
BRANCH="main"
BACKUP_DIR="/root/config_backups"

git clone --bare "$REPO" "$GIT_DIR"

_sys() { git --git-dir="$GIT_DIR" --work-tree=/ -C / "$@"; }

_sys config --local status.showUntrackedFiles no

echo "Cloned bare repo to $GIT_DIR"

# Try a simple checkout first
if _sys checkout "$BRANCH"; then
    echo "Checked out branch '$BRANCH' with no conflicts."
    exit 0
fi

# If we got here, there were conflicts
echo "Conflicts detected, backing up and retrying checkout..."

# Capture the conflict list
CONFLICT_LIST=$(_sys checkout "$BRANCH" 2>&1 | sed -n 's/^[[:space:]]\+//p' || true)

while IFS= read -r f; do
    case "$f" in
        The*|error:*|Please*|Aborting*|"") continue ;;
    esac
    echo "  backing up /$f -> $BACKUP_DIR/$f"
    mkdir -p "$BACKUP_DIR/$(dirname "$f")"
    mv "/$f" "$BACKUP_DIR/$f"
done <<< "$CONFLICT_LIST"

_sys checkout "$BRANCH"
echo "Checked out branch '$BRANCH'. Conflicts backed up to $BACKUP_DIR/"

