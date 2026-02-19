#!/usr/bin/env bash
# collect-starfighter-debug.sh
# Run with:  sudo bash collect-starfighter-debug.sh

set -euo pipefail

# Detect the non-root user who invoked sudo
TARGET_USER=${SUDO_USER:-$(whoami)}
TARGET_HOME=$(getent passwd "$TARGET_USER" | cut -d: -f6)

OUTDIR="$TARGET_HOME/Downloads/starfighter-debug"
mkdir -p "$OUTDIR"

echo "Collecting StarFighter debug info into: $OUTDIR"
echo "Detected user: $TARGET_USER (home: $TARGET_HOME)"
echo

########################################
# 0. lspci, lsusb
########################################

lspci -kv > "$OUTDIR/lspci_kv.txt"
lsusb > "$OUTDIR/lsusb.txt"

########################################
# 1. ACPI, power, and firmware info
########################################

{
  echo "## DMI / Firmware"
  grep . /sys/class/dmi/id/{sys_vendor,product_name,product_version,bios_*} 2>/dev/null || true
} > "$OUTDIR/dmi-info.txt"

dmesg > "$OUTDIR/dmesg-full.txt"

lsmod > "$OUTDIR/lsmod.txt"
modprobe -c > "$OUTDIR/modprobe.conf.txt" 2>/dev/null || echo "modprobe -c failed" > "$OUTDIR/modprobe.conf.txt"

{
  echo "## /sys/power/state"
  cat /sys/power/state 2>/dev/null || echo "no /sys/power/state"
  echo
  echo "## /sys/power/mem_sleep"
  cat /sys/power/mem_sleep 2>/dev/null || echo "no /sys/power/mem_sleep"
} > "$OUTDIR/power-sleep-states.txt"

journalctl -b -u systemd-logind > "$OUTDIR/journal-logind.txt"
journalctl -b | grep -iE 'suspend|resume|acpi|thermal' > "$OUTDIR/journal-power-thermal.txt" || true

########################################
# 2. CPU, GPU, and thermal basics
########################################

# Run user-space-readable bits as the target user where possible
sudo -u "$TARGET_USER" lscpu > "$OUTDIR/lscpu.txt"

{
  echo "## scaling_driver"
  cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_driver 2>/dev/null || echo "no scaling_driver"
  echo
  echo "## Available policies"
  for p in /sys/devices/system/cpu/cpufreq/policy*; do
    [ -d "$p" ] || continue
    echo "== $p =="
    cat "$p/scaling_governor" 2>/dev/null || true
    cat "$p/energy_performance_preference" 2>/dev/null || true
  done
} > "$OUTDIR/cpu-freq-and-epp.txt"

{
  echo "## /sys/devices/system/cpu/intel_pstate contents"
  if [ -d /sys/devices/system/cpu/intel_pstate ]; then
    ls -l /sys/devices/system/cpu/intel_pstate
    echo
    grep . /sys/devices/system/cpu/intel_pstate/* 2>/dev/null || true
  else
    echo "intel_pstate directory not present"
  fi
} > "$OUTDIR/intel_pstate-sysfs.txt"

sudo -u "$TARGET_USER" sensors > "$OUTDIR/sensors.txt" 2>&1 || echo "sensors failed" > "$OUTDIR/sensors.txt"

########################################
# 3. Graphics stack details
########################################

dmesg | grep -iE 'drm|i915|xe ' > "$OUTDIR/dmesg-drm.txt" || true
journalctl -b | grep -iE 'drm|i915|xe ' > "$OUTDIR/journal-drm.txt" || true

sudo -u "$TARGET_USER" glxinfo -B > "$OUTDIR/glxinfo-B.txt" 2>&1 || echo "glxinfo not available" > "$OUTDIR/glxinfo-B.txt"
sudo -u "$TARGET_USER" vulkaninfo --summary > "$OUTDIR/vulkaninfo-summary.txt" 2>&1 || echo "vulkaninfo not available" > "$OUTDIR/vulkaninfo-summary.txt"

if zgrep -q . /proc/config.gz 2>/dev/null; then
  {
    echo "## DRM / Intel / power config"
    zgrep -E 'CONFIG_DRM_XE|CONFIG_DRM_I915|CONFIG_INTEL_PMC|CONFIG_CPU_IDLE' /proc/config.gz || true
  } > "$OUTDIR/kernel-config-gfx-power.txt"
else
  echo "/proc/config.gz not available; please later send relevant .config snippets" > "$OUTDIR/kernel-config-gfx-power.txt"
fi

########################################
# 4. Storage, NVMe, and I/O
########################################

lsblk -o NAME,MODEL,SIZE,ROTA,DISC-GRAN,DISC-MAX,WSAME > "$OUTDIR/lsblk-detail.txt"

nvme list > "$OUTDIR/nvme-list.txt" 2>&1 || echo "nvme command not available" > "$OUTDIR/nvme-list.txt"

{
  for dev in /dev/nvme[0-9]; do
    [ -e "$dev" ] || continue
    echo "===== $dev: id-ctrl ====="
    nvme id-ctrl "$dev" 2>&1 || echo "id-ctrl failed for $dev"
    echo
    echo "===== $dev: feature 2 (power mgmt) ====="
    nvme get-feature "$dev" -f 2 -H 2>&1 || echo "get-feature -f 2 failed for $dev"
    echo
  done
} > "$OUTDIR/nvme-controllers-and-power.txt" 2>&1

{
  for b in /sys/block/nvme*; do
    [ -d "$b" ] || continue
    dev=$(basename "$b")
    echo "===== $dev ====="
    echo -n "scheduler: "
    cat "$b/queue/scheduler" 2>/dev/null || echo "no scheduler file"
    echo -n "add_random: "
    cat "$b/queue/add_random" 2>/dev/null || echo "no add_random file"
    echo
  done
} > "$OUTDIR/nvme-queue-settings.txt"

########################################
# 5. Network and wireless behavior
########################################

sudo -u "$TARGET_USER" nmcli device show > "$OUTDIR/nmcli-device-show.txt" 2>&1 || echo "nmcli not available" > "$OUTDIR/nmcli-device-show.txt"

{
  for phy in /sys/class/ieee80211/*; do
    [ -d "$phy" ] || continue
    phyname=$(basename "$phy")
    echo "===== $phyname: iw phy info ====="
    iw "$phyname" info 2>&1 || echo "iw info failed for $phyname"
    echo
  done
} > "$OUTDIR/iw-phy-info.txt" 2>&1

{
  for ifc in $(ls /sys/class/net 2>/dev/null | grep -E '^wlan|^wl'); do
    echo "===== $ifc ====="
    iw dev "$ifc" link 2>&1 || echo "iw link failed for $ifc"
    echo
    iw dev "$ifc" get power_save 2>&1 || echo "iw get power_save failed for $ifc"
    echo
  done
} > "$OUTDIR/wifi-link-and-powersave.txt" 2>&1

journalctl -b | grep -iE 'iwlwifi|ax210|wifi|wlan' > "$OUTDIR/journal-wifi.txt" || true

########################################
# 6. Current power/battery baseline
########################################

sudo -u "$TARGET_USER" upower -d > "$OUTDIR/upower-dump.txt" 2>&1 || echo "upower not available" > "$OUTDIR/upower-dump.txt"

{
  for b in /sys/class/power_supply/BAT*; do
    [ -d "$b" ] || continue
    echo "===== $b ====="
    cat "$b/uevent"
    echo
  done
} > "$OUTDIR/battery-uevent.txt" 2>&1

# 10-second, non-interactive HTML + CSV snapshot
sudo powertop --time=10 --iteration=1 --html=powertop.html --csv=powertop.csv

sudo -u "$TARGET_USER" bash -c "cat > '$OUTDIR/notes-user-observations.txt' << 'EOF'
Idle power on battery (from powertop or upower): ...
Approximate battery life under typical workload: ...
Anything odd you notice (fans, heat, glitches): ...
EOF
"

########################################
# 7. Systemd and user-space environment
########################################

sudo -u "$TARGET_USER" systemctl list-unit-files --state=enabled > "$OUTDIR/systemd-units-enabled.txt"
sudo -u "$TARGET_USER" systemctl --user list-unit-files --state=enabled > "$OUTDIR/systemd-user-units-enabled.txt" 2>&1 || echo "systemd --user not available" > "$OUTDIR/systemd-user-units-enabled.txt"

{
  echo "## loginctl show-session"
  SESSION_ID=$(loginctl | awk 'NR==2 {print $1}')
  echo "SESSION_ID=${SESSION_ID}"
  [ -n "$SESSION_ID" ] && loginctl show-session "$SESSION_ID" || echo "could not determine session id"
  echo
  echo "## loginctl show-user"
  loginctl show-user "$TARGET_USER" || loginctl show-user "$USER" || true
} > "$OUTDIR/loginctl-info.txt" 2>&1

# Hyprland config and environment.d for the target user
if [ -f "$TARGET_HOME/.config/hypr/hyprland.conf" ]; then
  cp "$TARGET_HOME/.config/hypr/hyprland.conf" "$OUTDIR/hyprland.conf.txt"
fi

if [ -d "$TARGET_HOME/.config/environment.d" ]; then
  tar czf "$OUTDIR/environment.d.tar.gz" -C "$TARGET_HOME/.config" environment.d
fi

########################################
# 8. Kernel command line and EFI stub details
########################################

cat /proc/cmdline > "$OUTDIR/kernel-cmdline.txt"

sudo -u "$TARGET_USER" bash -c "cat > '$OUTDIR/notes-kernel-install.txt' << 'EOF'
Describe (or paste) how you build and install your EFI stub kernel here.
For example:
- make commands
- genkernel/dracut/dracut-systemd steps (if any)
- how you copy the kernel to the EFI partition
- whether you use an initramfs (and which generator)
EOF
"

echo
echo "Done. All files are under: $OUTDIR"
echo "You can now tar them with:"
echo "  cd '$OUTDIR' && tar czf starfighter-debug.tar.gz ."
