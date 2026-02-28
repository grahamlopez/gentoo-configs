#!/usr/bin/env bash
# unified debug + Markdown report
# Run with: sudo bash create-system-report.sh
#
# This script collects a unified hardware / power / graphics / network debug
# snapshot from a system running Gentoo, systemd, and Hyprland,
# and writes a single Markdown report plus a few helper artifacts into:
#
#   $HOME/Downloads
#
# HOW TO RUN
# ----------
#   sudo bash collect-system-report.sh
#
# The script is intended to be run under sudo. It will:
#   - Detect the invoking non-root user via $SUDO_USER
#   - Write all outputs under that user's $HOME/Downloads
#   - chown the output directory back to that user at the end
#
# MAJOR COMMANDS USED
# -------------------
# Core utilities:
#   - bash, cat, grep, sed, ls, hostname, date, tar, mktemp
#
# Hardware / kernel:
#   - lspci        (from pciutils)
#   - lsusb        (from usbutils)
#   - dmesg
#   - lsmod, modprobe
#   - lsblk        (from util-linux)
#   - nvme         (from sys-apps/nvme-cli; optional but recommended)
#
# CPU / thermal:
#   - lscpu        (from util-linux)
#   - sensors      (from sys-apps/lm-sensors)
#
# Graphics:
#   - glxinfo      (from media-libs/mesa-progs or x11-apps/mesa-progs)
#   - vulkaninfo   (from dev-util/vulkan-tools)
#
# Power / battery:
#   - upower       (from sys-power/upower)
#   - powertop     (from sys-power/powertop)
#
# Network / Wi-Fi:
#   - nmcli        (from net-misc/networkmanager; optional if you use NM)
#   - iw           (from net-wireless/iw)
#
# systemd / login:
#   - systemctl
#   - loginctl
#   - journalctl
#
# SCRIPT BEHAVIOR
# ---------------
# - Uses `set -euo pipefail` for safety but wraps all external commands so that
#   failures are captured into the Markdown (with a [WARN] block) instead of
#   aborting the script.
# - Where a command is missing, the report includes a clear note such as:
#     [WARN] <description>: command 'foo' not found.
# - Reads from /sys and /proc (e.g. DMI info, cpufreq, intel_pstate, power
#   states, power_supply, /proc/cmdline). Missing or unreadable files are
#   handled gracefully and noted in the report.
#
# PREREQUISITES / ASSUMPTIONS
# ---------------------------
# - Systemd is PID 1 and journalctl/systemctl/loginctl are available.
# - You run the script with sudo from your login session on the system.
# - For maximum coverage, the following Gentoo packages are recommended:
#     sys-apps/pciutils        (lspci)
#     sys-apps/usbutils        (lsusb)
#     sys-apps/util-linux      (lsblk, lscpu, etc.)
#     sys-apps/lm-sensors      (sensors)
#     sys-apps/nvme-cli        (nvme)
#     net-misc/networkmanager  (nmcli; if you use NetworkManager)
#     net-wireless/iw          (iw)
#     sys-power/upower         (upower)
#     sys-power/powertop       (powertop)
#     dev-util/vulkan-tools    (vulkaninfo)
#     media-libs/mesa-progs    (glxinfo)
#
# If some of these are missing, the script still completes and notes the
# missing pieces in the Markdown so you can see which commands were skipped.

set -euo pipefail

trap 'echo "ERROR: command failed at line $LINENO: $BASH_COMMAND" >&2' ERR

###############################################################################
# Setup
###############################################################################

TITLE="System Info"
TARGET_USER="${SUDO_USER:-$(whoami)}"
TARGET_HOME=$(getent passwd "$TARGET_USER" | cut -d: -f6 || echo "/home/$TARGET_USER")
TARGET_HOSTNAME=$(hostname)
OUTDIR="$TARGET_HOME/Downloads"
mkdir -p "$OUTDIR"

MD_FILE="$OUTDIR/$TARGET_HOSTNAME-system-report.md"
TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT

###############################################################################
# Helpers
###############################################################################

log_warn() {
  echo "WARNING: $*" >&2
}

log_info() {
  echo "INFO: $*" >&2
}

append_section() {
  # Usage:
  #   append_section "Title"
  #   append_section "Title" "" /path/to/file
  #   append_section "Title" "Note text" /path/to/file
  local title="${1:-}"
  local note="${2:-}"
  local src="${3:-}"

  echo "" >> "$MD_FILE"
  echo "## $title" >> "$MD_FILE"

  if [ -n "$note" ]; then
    echo "" >> "$MD_FILE"
    echo "_${note}_" >> "$MD_FILE"
  fi

  echo "" >> "$MD_FILE"
  echo '```' >> "$MD_FILE"
  if [ -n "$src" ] && [ -f "$src" ]; then
    cat "$src" >> "$MD_FILE"
  else
    echo "No data collected for this section." >> "$MD_FILE"
  fi
  echo '```' >> "$MD_FILE"
}

run_cmd_to_file() {
  # run_cmd_to_file "description" /path/to/file cmd args...
  local desc="$1"
  local outfile="$2"
  shift 2

  {
    "$@" >"$outfile" 2>"$outfile.err" || {
      {
        echo "[WARN] $desc failed. See stderr snippet below."
        echo "Command: $*"
        echo ""
        echo "stderr:"
        sed -e 's/^/  /' "$outfile.err" || true
      } >"$outfile"
      log_warn "$desc failed"
    }
  } || true

  rm -f "$outfile.err" 2>/dev/null || true
}

run_cmd_if_exists_to_file() {
  # run_cmd_if_exists_to_file "desc" /file cmd args...
  local desc="$1"
  local outfile="$2"
  shift 2

  if ! command -v "$1" >/dev/null 2>&1; then
    echo "[WARN] $desc: command '$1' not found." >"$outfile"
    log_warn "$desc: '$1' missing"
    return
  fi

  run_cmd_to_file "$desc" "$outfile" "$@"
}

log_info "Collecting system info into $OUTDIR"
log_info "Detected user $TARGET_USER, home $TARGET_HOME"

###############################################################################
# Header
###############################################################################

{
  echo "# $TITLE"
  echo
  echo "- Date: $(date)"
  echo "- Host: $(hostname)"
  echo "- User: $TARGET_USER"
  echo "- Home: $TARGET_HOME"
  echo
} >"$MD_FILE"

###############################################################################
# 0. lspci, lsusb, DMI
###############################################################################

run_cmd_if_exists_to_file "lspci -kv" "$TEMP_DIR/lspci_kv.txt" lspci -kv
run_cmd_if_exists_to_file "lsusb"      "$TEMP_DIR/lsusb.txt"    lsusb

# DMI firmware info
{
  for f in sys_vendor product_name product_version bios_date bios_version bios_vendor; do
    echo "=== $f ==="
    if [ -r "/sys/class/dmi/id/$f" ]; then
      cat "/sys/class/dmi/id/$f"
    else
      echo "(not present or not readable)"
    fi
    echo
  done
} >"$TEMP_DIR/dmi-info.txt" 2>/dev/null || {
  echo "[WARN] Failed to read /sys/class/dmi/id/*" >"$TEMP_DIR/dmi-info.txt"
  log_warn "Failed to read /sys/class/dmi/id/*"
}

append_section "PCI Devices (lspci -kv)" "" "$TEMP_DIR/lspci_kv.txt"
append_section "USB Devices (lsusb)" "" "$TEMP_DIR/lsusb.txt"
append_section "DMI / Firmware Info" "" "$TEMP_DIR/dmi-info.txt"

###############################################################################
# 1. ACPI, power, and firmware info
###############################################################################

run_cmd_if_exists_to_file "dmesg"           "$TEMP_DIR/dmesg-full.txt" dmesg
run_cmd_if_exists_to_file "lsmod"           "$TEMP_DIR/lsmod.txt"      lsmod
run_cmd_if_exists_to_file "modprobe -c"     "$TEMP_DIR/modprobe.conf.txt" modprobe -c

# Power sleep states
{
  echo "== /sys/power/state =="
  if [ -r /sys/power/state ]; then
    cat /sys/power/state
  else
    echo "(no /sys/power/state)"
  fi
  echo
  echo "== /sys/power/mem_sleep =="
  if [ -r /sys/power/mem_sleep ]; then
    cat /sys/power/mem_sleep
  else
    echo "(no /sys/power/mem_sleep)"
  fi
} >"$TEMP_DIR/power-sleep-states.txt" 2>/dev/null || true

run_cmd_if_exists_to_file "journalctl -b -u systemd-logind" \
  "$TEMP_DIR/journal-logind.txt" journalctl -b -u systemd-logind

run_cmd_if_exists_to_file "journalctl -b (power/thermal filter)" \
  "$TEMP_DIR/journal-power-thermal.txt" \
  bash -c "journalctl -b | grep -iE 'suspend|resume|acpi|thermal' || echo 'No matches found.'"

append_section "Kernel dmesg (full)" "" "$TEMP_DIR/dmesg-full.txt"
append_section "Loaded Modules (lsmod)" "" "$TEMP_DIR/lsmod.txt"
append_section "modprobe Configuration" "" "$TEMP_DIR/modprobe.conf.txt"
append_section "ACPI / Power Sleep States" "" "$TEMP_DIR/power-sleep-states.txt"
append_section "systemd-logind Journal" "" "$TEMP_DIR/journal-logind.txt"
append_section "Power / Thermal Journal" "" "$TEMP_DIR/journal-power-thermal.txt"

###############################################################################
# 2. CPU, GPU, and thermal basics
###############################################################################

run_cmd_if_exists_to_file "lscpu as $TARGET_USER" \
  "$TEMP_DIR/lscpu.txt" sudo -u "$TARGET_USER" lscpu

# CPU freq + EPP
{
  echo "scaling_driver:"
  if [ -r /sys/devices/system/cpu/cpu0/cpufreq/scaling_driver ]; then
    cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_driver
  else
    echo "(no /sys/devices/system/cpu/cpu0/cpufreq/scaling_driver)"
  fi
  echo

  for p in /sys/devices/system/cpu/cpufreq/policy*; do
    [ -d "$p" ] || continue
    echo "=== Policy $(basename "$p") ==="
    echo -n "scaling_governor: "
    if [ -r "$p/scaling_governor" ]; then
      cat "$p/scaling_governor"
    else
      echo "(not present)"
    fi
    echo -n "energy_performance_preference: "
    if [ -r "$p/energy_performance_preference" ]; then
      cat "$p/energy_performance_preference"
    else
      echo "(not present)"
    fi
    echo
  done
} >"$TEMP_DIR/cpu-freq-and-epp.txt" 2>/dev/null || true

{
  if [ -d /sys/devices/system/cpu/intel_pstate ]; then
    echo "Contents of /sys/devices/system/cpu/intel_pstate:"
    ls -l /sys/devices/system/cpu/intel_pstate || true
    echo
    grep . /sys/devices/system/cpu/intel_pstate/* 2>/dev/null || echo "(no readable files)"
  else
    echo "intel_pstate directory not present."
  fi
} >"$TEMP_DIR/intel_pstate-sysfs.txt" 2>/dev/null || true

run_cmd_if_exists_to_file "sensors as $TARGET_USER" \
  "$TEMP_DIR/sensors.txt" sudo -u "$TARGET_USER" sensors

append_section "CPU Info (lscpu)" "" "$TEMP_DIR/lscpu.txt"
append_section "CPU Frequency / EPP" "" "$TEMP_DIR/cpu-freq-and-epp.txt"
append_section "Intel P-State Sysfs" "" "$TEMP_DIR/intel_pstate-sysfs.txt"
append_section "Sensors / Thermal Readings" "" "$TEMP_DIR/sensors.txt"

###############################################################################
# 3. Graphics stack details
###############################################################################

run_cmd_if_exists_to_file "DRM dmesg filter" \
  "$TEMP_DIR/dmesg-drm.txt" \
  bash -c "dmesg | grep -iE 'drm|i915|xe' || echo 'No DRM-related lines found.'"

run_cmd_if_exists_to_file "DRM journal filter" \
  "$TEMP_DIR/journal-drm.txt" \
  bash -c "journalctl -b | grep -iE 'drm|i915|xe' || echo 'No DRM-related lines found.'"

run_cmd_if_exists_to_file "glxinfo -B as $TARGET_USER" \
  "$TEMP_DIR/glxinfo-B.txt" sudo -u "$TARGET_USER" glxinfo -B

run_cmd_if_exists_to_file "vulkaninfo --summary as $TARGET_USER" \
  "$TEMP_DIR/vulkaninfo-summary.txt" sudo -u "$TARGET_USER" vulkaninfo --summary

{
  if [ -r /proc/config.gz ]; then
    zgrep -E 'CONFIG_DRM_XE|CONFIG_DRM_I915|CONFIG_INTEL_PMC|CONFIG_CPU_IDLE' /proc/config.gz \
      || echo "No matching DRM/Intel power config options found."
  else
    echo "/proc/config.gz not available; please include relevant .config snippets manually."
  fi
} >"$TEMP_DIR/kernel-config-gfx-power.txt" 2>/dev/null || true

append_section "DRM-related dmesg" "" "$TEMP_DIR/dmesg-drm.txt"
append_section "DRM-related journal entries" "" "$TEMP_DIR/journal-drm.txt"
append_section "GLX Info (-B)" "" "$TEMP_DIR/glxinfo-B.txt"
append_section "Vulkan Summary" "" "$TEMP_DIR/vulkaninfo-summary.txt"
append_section "Kernel Graphics/Power Config" "" "$TEMP_DIR/kernel-config-gfx-power.txt"

###############################################################################
# 4. Storage, NVMe, and IO
###############################################################################

run_cmd_if_exists_to_file "lsblk detail" \
  "$TEMP_DIR/lsblk-detail.txt" \
  lsblk -o NAME,MODEL,SIZE,ROTA,DISC-GRAN,DISC-MAX,WSAME

run_cmd_if_exists_to_file "nvme list" \
  "$TEMP_DIR/nvme-list.txt" \
  nvme list

{
  for dev in /dev/nvme[0-9]*; do
    [ -e "$dev" ] || continue
    echo "=== $dev ==="
    if command -v nvme >/dev/null 2>&1; then
      nvme id-ctrl "$dev" 2>/dev/null || echo "id-ctrl failed for $dev"
      echo
      echo "Feature 2 (power mgmt):"
      nvme get-feature "$dev" -f 2 -H 2>/dev/null || echo "get-feature -f 2 failed for $dev"
      echo
    else
      echo "nvme command not available."
    fi
    echo
  done
} >"$TEMP_DIR/nvme-controllers-and-power.txt" 2>/dev/null || true

{
  for b in /sys/block/nvme*; do
    [ -d "$b" ] || continue
    dev=$(basename "$b")
    echo "=== $dev ==="
    echo -n "scheduler: "
    if [ -r "$b/queue/scheduler" ]; then
      cat "$b/queue/scheduler"
    else
      echo "(no scheduler file)"
    fi
    echo -n "add_random: "
    if [ -r "$b/queue/add_random" ]; then
      cat "$b/queue/add_random"
    else
      echo "(no add_random file)"
    fi
    echo
  done
} >"$TEMP_DIR/nvme-queue-settings.txt" 2>/dev/null || true

append_section "Block Devices (lsblk)" "" "$TEMP_DIR/lsblk-detail.txt"
append_section "NVMe Devices (nvme list)" "" "$TEMP_DIR/nvme-list.txt"
append_section "NVMe Controllers and Power Features" "" "$TEMP_DIR/nvme-controllers-and-power.txt"
append_section "NVMe Queue Settings" "" "$TEMP_DIR/nvme-queue-settings.txt"

###############################################################################
# 5. Network and wireless behavior
###############################################################################

run_cmd_if_exists_to_file "nmcli device show as $TARGET_USER" \
  "$TEMP_DIR/nmcli-device-show.txt" sudo -u "$TARGET_USER" nmcli device show

{
  for phy in /sys/class/ieee80211/*; do
    [ -d "$phy" ] || continue
    phyname=$(basename "$phy")
    echo "=== $phyname ==="
    if command -v iw >/dev/null 2>&1; then
      iw phy "$phyname" info 2>/dev/null || echo "iw phy info failed for $phyname"
    else
      echo "iw command not available."
    fi
    echo
  done
} >"$TEMP_DIR/iw-phy-info.txt" 2>/dev/null || true

{
  if command -v iw >/dev/null 2>&1; then
    for ifc in $(ls /sys/class/net 2>/dev/null | grep -E 'wlan|wl'); do
      echo "=== $ifc ==="
      iw dev "$ifc" link 2>/dev/null || echo "iw link failed for $ifc"
      iw dev "$ifc" get power_save 2>/dev/null || iw dev "$ifc" get powersave 2>/dev/null || echo "iw get powersave failed for $ifc"
      echo
    done
  else
    echo "iw command not available."
  fi
} >"$TEMP_DIR/wifi-link-and-powersave.txt" 2>/dev/null || true

run_cmd_if_exists_to_file "Wi-Fi journal filter" \
  "$TEMP_DIR/journal-wifi.txt" \
  bash -c "journalctl -b | grep -iE 'iwlwifi|ax210|wifi|wlan' || echo 'No Wi-Fi related lines found.'"

append_section "Network Devices (nmcli)" "" "$TEMP_DIR/nmcli-device-show.txt"
append_section "Wi-Fi PHY Info (iw phy)" "" "$TEMP_DIR/iw-phy-info.txt"
append_section "Wi-Fi Link & Powersave" "" "$TEMP_DIR/wifi-link-and-powersave.txt"
append_section "Wi-Fi Related Journal Entries" "" "$TEMP_DIR/journal-wifi.txt"

###############################################################################
# 6. Current power / battery baseline
###############################################################################

run_cmd_if_exists_to_file "upower -d as $TARGET_USER" \
  "$TEMP_DIR/upower-dump.txt" sudo -u "$TARGET_USER" upower -d

{
  for b in /sys/class/power_supply/BAT*; do
    [ -d "$b" ] || continue
    echo "=== $(basename "$b") ==="
    if [ -r "$b/uevent" ]; then
      cat "$b/uevent"
    else
      echo "(no uevent file)"
    fi
    echo
  done
} >"$TEMP_DIR/battery-uevent.txt" 2>/dev/null || true

append_section "upower -d" "" "$TEMP_DIR/upower-dump.txt"
append_section "Battery uevent" "" "$TEMP_DIR/battery-uevent.txt"

run_cmd_if_exists_to_file "powertop HTML/CSV snapshot" \
  "$TEMP_DIR/powertop.log" \
  sudo powertop --time=10 --iteration=1 --html="$OUTDIR/powertop.html" --csv="$OUTDIR/powertop.csv"

append_section "powertop snapshot note" \
  "powertop.html and powertop.csv are saved next to this Markdown file in $OUTDIR." \
  "$TEMP_DIR/powertop.log"

###############################################################################
# 7. Systemd and user-space environment
###############################################################################

run_cmd_if_exists_to_file "systemctl list-unit-files --state=enabled (system)" \
  "$TEMP_DIR/systemd-units-enabled.txt" \
  sudo -u "$TARGET_USER" systemctl list-unit-files --state=enabled

run_cmd_if_exists_to_file "systemctl --user list-unit-files --state=enabled" \
  "$TEMP_DIR/systemd-user-units-enabled.txt" \
  sudo -u "$TARGET_USER" systemctl --user list-unit-files --state=enabled

{
  SESSION_ID=$(loginctl | awk 'NR==2 {print $1}' || true)
  echo "Detected session id: ${SESSION_ID:-'(none)'}"
  echo
  if [ -n "${SESSION_ID:-}" ]; then
    echo "loginctl show-session $SESSION_ID:"
    loginctl show-session "$SESSION_ID" || echo "could not show session $SESSION_ID"
    echo
  fi
  echo "loginctl show-user $TARGET_USER:"
  loginctl show-user "$TARGET_USER" || echo "could not show user $TARGET_USER"
  echo
} >"$TEMP_DIR/loginctl-info.txt" 2>/dev/null || true

append_section "systemd Enabled Units (system)" "" "$TEMP_DIR/systemd-units-enabled.txt"
append_section "systemd Enabled Units (user)" "" "$TEMP_DIR/systemd-user-units-enabled.txt"
append_section "loginctl Session/User Info" "" "$TEMP_DIR/loginctl-info.txt"

###############################################################################
# 8. Hyprland config and environment.d
###############################################################################

{
  echo "If present, Hyprland config and environment.d have been archived separately."
  echo
  if [ -f "$TARGET_HOME/.config/hypr/hyprland.conf" ]; then
    echo "Hyprland config: $TARGET_HOME/.config/hypr/hyprland.conf"
    cp "$TARGET_HOME/.config/hypr/hyprland.conf" "$OUTDIR/hyprland.conf"
  else
    echo "Hyprland config not found at $TARGET_HOME/.config/hypr/hyprland.conf"
  fi

  if [ -d "$TARGET_HOME/.config/environment.d" ]; then
    echo "environment.d: $TARGET_HOME/.config/environment.d"
    tar czf "$OUTDIR/environment.d.tar.gz" -C "$TARGET_HOME/.config" environment.d
  else
    echo "environment.d directory not found at $TARGET_HOME/.config/environment.d"
  fi
} >"$TEMP_DIR/hyprland-env-note.txt" 2>/dev/null || true

append_section "Hyprland & environment.d Notes" "" "$TEMP_DIR/hyprland-env-note.txt"

###############################################################################
# 9. Kernel command line and EFI stub details
###############################################################################

run_cmd_if_exists_to_file "cat /proc/cmdline" \
  "$TEMP_DIR/kernel-cmdline.txt" \
  cat /proc/cmdline

cat >"$OUTDIR/notes-kernel-install.txt" <<'EOF'
starting with sys-kernel/gentoo-sources

- create custom initramfs with static cryptsetup, busybox, and hand-written init:
```
#!/bin/busybox sh
export PATH="/bin:/sbin"

# Mount virtual filesystems
mount -t proc     proc     /proc
mount -t sysfs    sysfs    /sys
mount -t devtmpfs devtmpfs /dev

rescue_shell() {
    echo "Dropping to rescue shell"
    exec /bin/busybox sh
}

# Find a LUKS container device by its LUKS UUID
find_luks_by_uuid() {
    target_uuid="$1"
    for dev in /dev/sd?* /dev/nvme?n?p* /dev/vd?*; do
        [ -b "$dev" ] || continue
        uuid="$(cryptsetup luksUUID "$dev" 2>/dev/null || true)"
        [ -n "$uuid" ] || continue
        [ "$uuid" = "$target_uuid" ] && { echo "$dev"; return 0; }
    done
    return 1
}

luks_uuid=""
rootfstype="ext4"

# Parse kernel command line
for param in $(cat /proc/cmdline); do
    case "$param" in
        crypt_root=UUID=*)
            luks_uuid="${param#crypt_root=UUID=}"
            ;;
        rootfstype=*)
            rootfstype="${param#rootfstype=}"
            ;;
    esac
done

[ -z "$luks_uuid" ] && echo "No crypt_root=UUID= found" && rescue_shell

# Optional: populate /dev from sysfs (not strictly required for luksUUID)
mdev -s

CRYPTSETUP=/sbin/cryptsetup
[ ! -x "$CRYPTSETUP" ] && echo "cryptsetup missing" && rescue_shell

luks_source="$(find_luks_by_uuid "$luks_uuid")" || {
    echo "Could not find LUKS device with LUKS UUID=$luks_uuid"
    rescue_shell
}

"$CRYPTSETUP" luksOpen "$luks_source" luksroot || rescue_shell

# Hardcode root as the filesystem inside the mapper
mount -t "$rootfstype" -o ro /dev/mapper/luksroot /mnt/root || rescue_shell

umount /proc
umount /sys
umount /dev

exec switch_root /mnt/root /sbin/init
```
- cd /usr/src/linux
- make menuconfig
- KCFLAGS="-march-native -02 -pipe" make -j12
- make modules_install INSTALL_MOD_STRIP=1
- KCFLAGS="-march-native -02 -pipe" make -j12
- cp arch/x86/boot/bzImage /boot/EFI/boot/boot64x.efi
EOF

append_section "Kernel Command Line" "" "$TEMP_DIR/kernel-cmdline.txt"

###############################################################################
# 10. User observations placeholder
###############################################################################

cat >"$OUTDIR/notes-user-observations.txt" <<'EOF'
Idle power on battery from powertop or upower:
- e.g., "powertop reports ~X.X W"

Approximate battery life under typical workload:
- e.g., "I get about Y hours doing browser + editor + terminals"

Anything odd you notice (fans, heat, glitches, hangs, audio pops, etc.):
- e.g., "fans ramp under light load", "display occasionally blanks", etc.
EOF

append_section "Notes: Kernel Install & User Observations" \
  "Please edit notes-kernel-install.txt and notes-user-observations.txt next to this report and send them along with this Markdown file." \
  "$OUTDIR/notes-user-observations.txt"

###############################################################################
# Done
###############################################################################

echo "" >>"$MD_FILE"
echo "-----" >>"$MD_FILE"
echo "" >>"$MD_FILE"
echo "_End of system report. All raw artifacts are in $OUTDIR._" >>"$MD_FILE"

# Fix ownership so you can edit in your normal user session
if [ -n "${SUDO_USER:-}" ]; then
  chown -R "$SUDO_USER:$SUDO_USER" "$OUTDIR" || log_warn "Failed to chown $OUTDIR"
fi

log_info "Done. Markdown report: $MD_FILE"
log_info "Additional artifacts are in $OUTDIR"
log_info "Recommend also gathering full kernel .confg/defconfig"
