#!/bin/sh
# Usage: set-power-profile.sh ac|battery

INTEL_PSTATE_DIR=/sys/devices/system/cpu/intel_pstate
WIFI_IFACE="wlp1s0"
NVME_DEVS="nvme0 nvme1"
BAT0="/sys/class/power_supply/BAT0"
BAT1="/sys/class/power_supply/BAT1"
STATE_DIR="/tmp/power-profile"
STATE_FILE="$STATE_DIR/battery_since"      # stores: "<start_time> <start_pct>"

detect_bat() {
  if [ -d "$BAT0" ]; then
    echo "BAT0"
  elif [ -d "$BAT1" ]; then
    echo "BAT1"
  else
    echo ""
  fi
}

start_battery_session() {
  bat=$(detect_bat)
  cur_pct=$(cat "/sys/class/power_supply/$bat/capacity" 2>/dev/null)

  [ -d "$STATE_DIR" ] || mkdir -p "$STATE_DIR"
  now=$(date +%s)

  # Initialize state when first going on battery
  if [ ! -f "$STATE_FILE" ]; then
    # If we do not know current percentage, just store 0
    [ -z "$cur_pct" ] && cur_pct=0
    echo "$now $cur_pct" > "$STATE_FILE"
    chmod 666 $STATE_FILE
    return
  fi
}

reset_battery_session() {
  # On AC: reset timer
  [ -f "$STATE_FILE" ] && rm -f "$STATE_FILE"
  echo "-"
}

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
    start_battery_session
    ;;
  ac)
    set_cpu_ac
    set_nvme_ac
    set_wifi_ac
    set_epp_all balance_performance
    reset_battery_session
    ;;
  *)
    echo "Usage: $0 ac|battery" >&2
    exit 1
    ;;
esac
