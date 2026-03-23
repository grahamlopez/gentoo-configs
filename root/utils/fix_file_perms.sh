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
    "/etc/hostname:root:root:0644"
    "/etc/hosts:root:root:0644"
    "/etc/keyd/default.conf:root:root:0644"
    "/etc/modprobe.d/blacklist-nouveau.conf:root:root:0644"
    "/etc/portage/make.conf:root:root:0644"
    "/etc/portage/package.accept_keywords/common:root:root:0644"
    "/etc/portage/package.use/common:root:root:0644"
    "/etc/portage/sets/early_install:root:root:0644"
    "/etc/portage/sets/hyprland_env:root:root:0644"
    "/etc/portage/sets/optionals:root:root:0644"
    "/etc/systemd/system/getty@tty1.service.d/override.conf:root:root:0644"
    "/etc/systemd/system/power-profile-init.service:root:root:0644"
    "/etc/systemd/system/power-profile@.service:root:root:0600"
    "/etc/udev/rules.d/99-power-profile.rules:root:root:0600"
    "/etc/vconsole.conf:root:root:0644"
    "/root/.README:root:root:0600"
    "/root/.config/nvim/after/ftplugin/markdown.lua:root:root:0600"
    "/root/.config/nvim/init.lua:root:root:0600"
    "/root/.config/nvim/queries/markdown/highlights.scm:root:root:0600"
    "/root/.dir_colors:root:root:0600"
    "/root/.gitconfig:root:root:0600"
    "/root/.tmux.conf:root:root:0600"
    "/root/.vimrc:root:root:0600"
    "/root/.zsh/completion/_conda:root:root:0600"
    "/root/.zsh/completion/_docker:root:root:0600"
    "/root/.zsh/completion/_lxc:root:root:0600"
    "/root/.zsh/completion/_task:root:root:0600"
    "/root/.zsh/git-prompt.sh:root:root:0600"
    "/root/.zshrc:root:root:0600"
    "/root/utils/enter_chroot.sh:root:root:0700"
    "/root/utils/fix_file_perms.sh:root:root:0700"
    "/root/utils/gentoo_configs_bootstrap.sh:root:root:0700"
    "/root/utils/get_stage3.sh:root:root:0700"
    "/root/utils/trim_systemd_services.sh:root:root:0700"
    "/usr/local/sbin/build_static_utils.sh:root:root:0755"
    "/usr/local/sbin/create-system-report.sh:root:root:0755"
    "/usr/local/sbin/dmesg_gaps.sh:root:root:0755"
    "/usr/local/sbin/powertop-tunables.sh:root:root:0755"
    "/usr/local/sbin/set-power-profile.sh:root:root:0755"
    "/usr/local/sbin/show-power-status.sh:root:root:0755"
    "/usr/share/keymaps/i386/qwerty/us-caps.map.gz:root:root:0644"
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
    if [[ -z "${TRACKED[/$repo_file]+_}" ]]; then
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
