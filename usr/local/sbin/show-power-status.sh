#!/bin/sh

# ── config ───────────────────────────────────────────────────────────────────

INTEL_PSTATE_DIR=/sys/devices/system/cpu/intel_pstate
WIFI_IFACE="wlp1s0"
NVME_DEVS="nvme0 nvme1"
AC_PATH="/sys/class/power_supply/ADP1"
BAT0="/sys/class/power_supply/BAT0"
BAT1="/sys/class/power_supply/BAT1"
STATE_DIR="/tmp/power-profile"
STATE_FILE="$STATE_DIR/battery_since"   # written by power-profile switcher

# ── data helpers (no output) ─────────────────────────────────────────────────

hr() { printf '%s\n' "----------------------------------------"; }

detect_bat() {
  if   [ -d "$BAT0" ]; then echo "BAT0"
  elif [ -d "$BAT1" ]; then echo "BAT1"
  fi
}

brightness_pct() {
  local bl_dir='' cur max
  for d in /sys/class/backlight/*; do
    [ -d "$d" ] && bl_dir="$d" && break
  done
  [ -z "$bl_dir" ] && return 1
  cur=$(cat "$bl_dir/brightness"     2>/dev/null)
  max=$(cat "$bl_dir/max_brightness" 2>/dev/null)
  [ -z "$cur" ] || [ -z "$max" ] || [ "$max" -eq 0 ] 2>/dev/null && return 1
  printf '%d%%' $(( cur * 100 / max ))
}

bat_power_w() {
  local bat=$1
  [ -n "$bat" ] || return 1
  if [ -f "/sys/class/power_supply/$bat/power_now" ]; then
    awk '{ printf "%.2f", $1 / 1e6 }' "/sys/class/power_supply/$bat/power_now"
    return
  fi
  if [ -f "/sys/class/power_supply/$bat/voltage_now" ] &&
     [ -f "/sys/class/power_supply/$bat/current_now" ]; then
    local v i
    v=$(cat "/sys/class/power_supply/$bat/voltage_now")
    i=$(cat "/sys/class/power_supply/$bat/current_now")
    awk -v v="$v" -v i="$i" 'BEGIN { printf "%.2f", (i * v) / 1e12 }'
    return
  fi
  return 1
}

bat_time_remaining() {
  local bat=$1 en_now_Wh pw_w seconds
  [ -n "$bat" ] || return 1

  if [ -f "/sys/class/power_supply/$bat/charge_now" ] &&
     [ -f "/sys/class/power_supply/$bat/charge_full" ] &&
     [ -f "/sys/class/power_supply/$bat/voltage_now" ]; then
    local c v
    c=$(cat "/sys/class/power_supply/$bat/charge_now")
    v=$(cat "/sys/class/power_supply/$bat/voltage_now")
    en_now_Wh=$(awk -v c="$c" -v v="$v" 'BEGIN { printf "%.4f", (c * v) / 1e12 }')
  elif [ -f "/sys/class/power_supply/$bat/energy_now" ]; then
    local e
    e=$(cat "/sys/class/power_supply/$bat/energy_now")
    en_now_Wh=$(awk -v e="$e" 'BEGIN { printf "%.4f", e / 1e6 }')
  else
    return 1
  fi

  pw_w=$(bat_power_w "$bat") || return 1
  seconds=$(awk -v e="$en_now_Wh" -v p="$pw_w" \
    'BEGIN { if (p == 0) print 0; else printf "%.0f", (e / p) * 3600 }')
  printf '%02d:%02d:%02d' $(( seconds/3600 )) $(( (seconds%3600)/60 )) $(( seconds%60 ))
}

epp_summary() {
  local first='' mixed=0 val
  for p in /sys/devices/system/cpu/cpufreq/policy*/energy_performance_preference; do
    [ -f "$p" ] || continue
    val=$(cat "$p" 2>/dev/null) || continue
    if [ -z "$first" ]; then
      first="$val"
    elif [ "$val" != "$first" ]; then
      mixed=1; break
    fi
  done
  if   [ -z "$first"     ]; then echo "(no EPP)"
  elif [ "$mixed" -eq 0  ]; then echo "$first"
  else                           echo "mixed"
  fi
}

battery_elapsed() {
  # prints "HH:MM:SS (N% drop)" while on battery, nothing while on AC
  local cur_state=$1 cur_pct=$2 start_time start_pct now elapsed drop
  [ "$cur_state" = "battery" ] || return
  [ -d "$STATE_DIR" ] || mkdir -p "$STATE_DIR"
  now=$(date +%s)

  read start_time start_pct 2>/dev/null < "$STATE_FILE"
  : "${start_time:=$now}" "${start_pct:=$cur_pct}"

  elapsed=$(( now - start_time ))
  drop=0
  if [ -n "$cur_pct" ] && [ -n "$start_pct" ]; then
    drop=$(( start_pct - cur_pct ))
    [ "$drop" -lt 0 ] && drop=0
  fi
  printf '%02d:%02d:%02d (%d%% drop)' \
    $(( elapsed/3600 )) $(( (elapsed%3600)/60 )) $(( elapsed%60 )) "$drop"
}

# ── gather all data ──────────────────────────────────────────────────────────

bat=$(detect_bat)
cur_mode="ac"
cur_pct=""

# AC / Battery
ac_state=""
if [ -r "$AC_PATH/online" ]; then
  if [ "$(cat "$AC_PATH/online")" = "1" ]; then
    ac_state="online";  cur_mode="ac"
  else
    ac_state="offline"; cur_mode="battery"
  fi
fi

bat_status="" bat_cap="" pw="" time_remaining=""
if [ -n "$bat" ] && [ -r "/sys/class/power_supply/$bat/status" ]; then
  bat_status=$(cat "/sys/class/power_supply/$bat/status")
  bat_cap=$(cat    "/sys/class/power_supply/$bat/capacity" 2>/dev/null)
  cur_pct="$bat_cap"
  pw=$(bat_power_w "$bat" 2>/dev/null)
  if [ "$bat_status" = "Discharging" ] && [ -n "$pw" ]; then
    time_remaining=$(bat_time_remaining "$bat" 2>/dev/null)
  fi
fi

brightness=$(brightness_pct)
time_on_bat=$(battery_elapsed "$cur_mode" "$cur_pct")

# CPU
cpu_status="" cpu_minp="" cpu_maxp="" cpu_noturbo="" cpu_gov="" cpu_mhz="" cpu_epp=""
if [ -d "$INTEL_PSTATE_DIR" ]; then
  cpu_status=$(cat  "$INTEL_PSTATE_DIR/status")
  cpu_minp=$(cat    "$INTEL_PSTATE_DIR/min_perf_pct")
  cpu_maxp=$(cat    "$INTEL_PSTATE_DIR/max_perf_pct")
  cpu_noturbo=$(cat "$INTEL_PSTATE_DIR/no_turbo")
fi
if [ -d /sys/devices/system/cpu/cpufreq/policy0 ]; then
  cpu_gov=$(cat /sys/devices/system/cpu/cpufreq/policy0/scaling_governor)
  cpu_khz=$(cat /sys/devices/system/cpu/cpufreq/policy0/scaling_cur_freq)
  cpu_mhz=$(awk -v k="$cpu_khz" 'BEGIN { printf "%.1f", k / 1000.0 }')
  epp_path=/sys/devices/system/cpu/cpufreq/policy0/energy_performance_preference
  [ -r "$epp_path" ] && cpu_epp=$(cat "$epp_path") || cpu_epp="(no EPP)"
fi
epp_all=$(epp_summary)

# NVMe (pre-format lines; each ends with a real newline)
nvme_out=""
for dev in $NVME_DEVS; do
  base="/sys/class/nvme/$dev"
  if [ -d "$base" ]; then
    pctl="(n/a)"
    [ -r "$base/device/power/control" ] && pctl=$(cat "$base/device/power/control")
    nvme_out="${nvme_out}  $dev: power/control: $pctl
"
  fi
done

# Wi-Fi
wifi_state="" wifi_ps=""
if ip link show "$WIFI_IFACE" >/dev/null 2>&1; then
  wifi_state=$(ip link show "$WIFI_IFACE" | awk '/state/ {print $9}')
  wifi_ps=$(iw dev "$WIFI_IFACE" get power_save 2>/dev/null | sed 's/^[[:space:]]*//')
fi

# ── output ───────────────────────────────────────────────────────────────────

echo "Power status overview"
hr

echo "AC / Battery:"
[ -n "$ac_state"       ] && printf '  AC adapter:      %s\n'            "$ac_state"
[ -n "$bat"            ] && printf '  Battery:         %s (%s%%)\n'     "$bat_status" "${bat_cap:-?}"
[ -n "$brightness"     ] && printf '  Brightness:      %s\n'            "$brightness"
[ -n "$pw"             ] && printf '  Power draw:      %s W\n'          "$pw"
[ -n "$time_remaining" ] && printf '  Time remaining:  %s (approx)\n'   "$time_remaining"
[ -n "$time_on_bat"    ] && printf '  Time on battery: %s\n'            "$time_on_bat"
hr

echo "CPU (Intel P-state):"
[ -n "$cpu_status"  ] && printf '  Status:          %s\n'      "$cpu_status"
[ -n "$cpu_minp"    ] && printf '  Min perf:        %s%%\n'    "$cpu_minp"
[ -n "$cpu_maxp"    ] && printf '  Max perf:        %s%%\n'    "$cpu_maxp"
[ -n "$cpu_noturbo" ] && printf '  Turbo disabled:  %s\n'      "$cpu_noturbo"
[ -n "$cpu_gov"     ] && printf '  Governor:        %s\n'      "$cpu_gov"
[ -n "$cpu_mhz"     ] && printf '  Cur freq:        %s MHz\n'  "$cpu_mhz"
[ -n "$cpu_epp"     ] && printf '  EPP (policy0):   %s\n'      "$cpu_epp"
printf '  EPP (all):       %s\n' "$epp_all"
hr

echo "NVMe devices:"
if [ -n "$nvme_out" ]; then
  printf '%s' "$nvme_out"
else
  echo "  (none found)"
fi
hr

echo "Wi-Fi ($WIFI_IFACE):"
if [ -n "$wifi_state" ]; then
  printf '  Link state:  %s\n' "$wifi_state"
  [ -n "$wifi_ps" ] && printf '  %s\n' "$wifi_ps" || echo "  Power save: (unknown)"
else
  echo "  Interface not found"
fi
hr
