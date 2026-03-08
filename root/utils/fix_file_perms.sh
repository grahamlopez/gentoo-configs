#!/bin/bash
# sysperms.sh - check and fix file ownership/permissions for system configs
# Keep this in your sysfiles bare repo. Edit the list below.
# Optionally add 'sysperms.sh --fix' to '.git/hooks/post-checkout'
# Usage: sysperms [--check | --fix]

set -euo pipefail

GIT_DIR="/root/.gentoo-configs"
WORK_TREE="/"

# FORMAT: "path:owner:group:mode"
FILES=(
    "/root/.README:root:root:0600"
    "/etc/portage/make.conf:root:root:0644"
    "/etc/hostname:root:root:0644"
    #"/etc/sudoers:root:root:0440"
    # Add more entries as needed
)

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

MODE="${1:---check}"
ERRORS=0

# Build a set of tracked paths from the FILES array
declare -A TRACKED
for entry in "${FILES[@]}"; do
    IFS=':' read -r path _ _ _ <<< "$entry"
    TRACKED["$path"]=1
done

# Check permissions on all listed files
for entry in "${FILES[@]}"; do
    IFS=':' read -r path owner group mode <<< "$entry"

    if [[ ! -e "$path" ]]; then
        printf "${RED}MISSING${NC}  %s\n" "$path"
        ((ERRORS++))
        continue
    fi

    cur_owner=$(stat -c '%U' "$path")
    cur_group=$(stat -c '%G' "$path")
    cur_mode=$(stat -c '%04a' "$path")

    ok=true
    detail=""

    if [[ "$cur_owner" != "$owner" ]]; then
        ok=false
        detail+=" owner=${cur_owner}→${owner}"
    fi
    if [[ "$cur_group" != "$group" ]]; then
        ok=false
        detail+=" group=${cur_group}→${group}"
    fi
    if [[ "$cur_mode" != "$mode" ]]; then
        ok=false
        detail+=" mode=${cur_mode}→${mode}"
    fi

    if $ok; then
        printf "${GREEN}OK${NC}       %s\n" "$path"
    else
        printf "${RED}MISMATCH${NC} %s%s\n" "$path" "$detail"
        ERRORS=$((ERRORS + 1))

        if [[ "$MODE" == "--fix" ]]; then
            chown "${owner}:${group}" "$path"
            chmod "$mode" "$path"
            printf "         ${GREEN}FIXED${NC}\n"
        fi
    fi
done

# Check for repo files not in the FILES array
UNTRACKED=0
while IFS= read -r repo_file; do
    if [[ -z "${TRACKED[$repo_file]+_}" ]]; then
        if [[ $UNTRACKED -eq 0 ]]; then
            printf "\n${YELLOW}Files in repo without permission entries:${NC}\n"
        fi
        cur_owner=$(stat -c '%U' "/$repo_file")
        cur_group=$(stat -c '%G' "/$repo_file")
        cur_mode=$(stat -c '%04a' "/$repo_file")
        printf "${YELLOW}UNMANAGED${NC} /%s:%s:%s:%s${NC}\n" "$repo_file" "$cur_owner" "$cur_group" "$cur_mode"
        UNTRACKED=$((UNTRACKED + 1))
    fi
done < <(git --git-dir="$GIT_DIR" --work-tree="$WORK_TREE" -C / ls-files)

# Summary
if [[ $UNTRACKED -gt 0 ]]; then
    printf "\n%d file(s) in repo not listed in FILES array.\n" "$UNTRACKED"
    ERRORS=$((ERRORS + UNTRACKED))
fi

if [[ $ERRORS -gt 0 && "$MODE" == "--check" ]]; then
    printf "%d total issue(s) found. Run with --fix to correct permissions.\n" "$ERRORS"
    exit 1
elif [[ $ERRORS -eq 0 ]]; then
    printf "\nAll files OK.\n"
fi
