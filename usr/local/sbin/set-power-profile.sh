#!/bin/sh
# Usage: set-power-profile.sh ac|battery

INTEL_PSTATE_DIR=/sys/devices/system/cpu/intel_pstate
WIFI_IFACE="wlp1s0"
NVME_DEVS="nvme0 nvme1"

set_cpu_battery() {
  echo 40 > "$INTEL_PSTATE_DIR/max_perf_pct"
  echo 1  > "$INTEL_PSTATE_DIR/no_turbo"
}

set_cpu_ac() {
  echo 100 > "$INTEL_PSTATE_DIR/max_perf_pct"
  echo 0   > "$INTEL_PSTATE_DIR/no_turbo"
}

set_nvme_battery() {
  for dev in $NVME_DEVS; do
    base="/sys/class/nvme/$dev"
    [ -d "$base" ] || continue
    echo auto > "$base/device/power/control" 2>/dev/null || true
  done
}

set_nvme_ac() {
  for dev in $NVME_DEVS; do
    base="/sys/class/nvme/$dev"
    [ -d "$base" ] || continue
    echo on > "$base/device/power/control" 2>/dev/null || true
  done
}

set_wifi_battery() {
  iw dev "$WIFI_IFACE" set power_save on 2>/dev/null || true
}

set_wifi_ac() {
  iw dev "$WIFI_IFACE" set power_save off 2>/dev/null || true
}

set_epp_all() {
  val="$1"  # performance | balance_performance | balance_power | power
  for p in /sys/devices/system/cpu/cpufreq/policy*/energy_performance_preference; do
    [ -f "$p" ] || continue
    echo "$val" > "$p" 2>/dev/null || true
  done
}

case "$1" in
  battery)
    set_cpu_battery
    set_nvme_battery
    set_wifi_battery
    set_epp_all balance_power
    ;;
  ac)
    set_cpu_ac
    set_nvme_ac
    set_wifi_ac
    set_epp_all balance_performance
    ;;
  *)
    echo "Usage: $0 ac|battery" >&2
    exit 1
    ;;
esac
