#!/bin/sh

INTEL_PSTATE_DIR=/sys/devices/system/cpu/intel_pstate
WIFI_IFACE="wlp1s0"
NVME_DEVS="nvme0 nvme1"
AC_PATH="/sys/class/power_supply/ADP1"
BAT0="/sys/class/power_supply/BAT0"
BAT1="/sys/class/power_supply/BAT1"
STATE_DIR="/tmp/power-profile"
STATE_FILE="$STATE_DIR/battery_since"      # stores: "<start_time> <start_pct>"

hr() { printf '%s\n' "----------------------------------------"; }

detect_bat() {
  if [ -d "$BAT0" ]; then
    echo "BAT0"
  elif [ -d "$BAT1" ]; then
    echo "BAT1"
  else
    echo ""
  fi
}

epp_all_summary() {
  first=""
  mixed=0

  for p in /sys/devices/system/cpu/cpufreq/policy*/energy_performance_preference; do
    [ -f "$p" ] || continue
    val=$(cat "$p" 2>/dev/null) || continue
    if [ -z "$first" ]; then
      first="$val"
    elif [ "$val" != "$first" ]; then
      mixed=1
      break
    fi
  done

  if [ -z "$first" ]; then
    echo "(no EPP)"
  elif [ "$mixed" -eq 0 ]; then
    echo "$first"
  else
    echo "mixed"
  fi
}

ensure_state_dir() {
  [ -d "$STATE_DIR" ] || mkdir -p "$STATE_DIR"
}

battery_elapsed() {
  # $1 = current mode: "ac" or "battery"
  # $2 = current battery percentage (integer or empty)
  cur_state="$1"
  cur_pct="$2"

  ensure_state_dir
  now=$(date +%s)

  if [ "$cur_state" = "battery" ]; then
    # Initialize state when first going on battery
    if [ ! -f "$STATE_FILE" ]; then
      # If we do not know current percentage, just store 0
      [ -z "$cur_pct" ] && cur_pct=0
      echo "$now $cur_pct" > "$STATE_FILE"
      echo "00:00:00 (0%% drop)"
      chmod 666 $STATE_FILE
      return
    fi

    # Read "start_time start_pct"
    read start_time start_pct 2>/dev/null < "$STATE_FILE"
    [ -z "$start_time" ] && start_time="$now"
    [ -z "$start_pct" ] && start_pct="$cur_pct"

    elapsed=$(( now - start_time ))
    h=$(( elapsed / 3600 ))
    m=$(( (elapsed % 3600) / 60 ))
    s=$(( elapsed % 60 ))

    if [ -n "$cur_pct" ] && [ -n "$start_pct" ]; then
      drop=$(( start_pct - cur_pct ))
      [ $drop -lt 0 ] && drop=0
    else
      drop=0
    fi

    printf "%02d:%02d:%02d (%d%%%% drop)" "$h" "$m" "$s" "$drop"
  else
    # On AC: reset timer
    [ -f "$STATE_FILE" ] && rm -f "$STATE_FILE"
    echo "-"
  fi
}

bat_power_w() {
  bat="$1"
  [ -n "$bat" ] || return 1

  # Prefer power_now if available (µW)
  if [ -f "/sys/class/power_supply/$bat/power_now" ]; then
    pw_uW=$(cat "/sys/class/power_supply/$bat/power_now")
    echo "$pw_uW" | awk '{ printf "%.2f", $1 / 1000000.0 }'
    return 0
  fi

  # Fallback: voltage_now (µV) * current_now (µA) → W
  if [ -f "/sys/class/power_supply/$bat/voltage_now" ] && \
     [ -f "/sys/class/power_supply/$bat/current_now" ]; then
    voltage_uV=$(cat "/sys/class/power_supply/$bat/voltage_now")
    current_uA=$(cat "/sys/class/power_supply/$bat/current_now")
    # W = (µA * µV) / 1e12
    echo "$current_uA $voltage_uV" | awk '{ printf "%.2f", ($1 * $2) / 1e12 }'
    return 0
  fi

  return 1
}

bat_time_remaining() {
  bat="$1"
  [ -n "$bat" ] || return 1

  # Use charge_* (µAh) + voltage_now (µV) to estimate energy in Wh
  if [ -f "/sys/class/power_supply/$bat/charge_now" ] && \
     [ -f "/sys/class/power_supply/$bat/charge_full" ] && \
     [ -f "/sys/class/power_supply/$bat/voltage_now" ]; then
    ch_now_uAh=$(cat "/sys/class/power_supply/$bat/charge_now")
    v_now_uV=$(cat "/sys/class/power_supply/$bat/voltage_now")
    # E (Wh) ≈ (charge in Ah) * (voltage in V)
    # Ah = µAh / 1e6, V = µV / 1e6 → Wh = (µAh * µV) / 1e12
    en_now_Wh=$(echo "$ch_now_uAh $v_now_uV" | awk '{ printf "%.4f", ($1 * $2) / 1e12 }')
  elif [ -f "/sys/class/power_supply/$bat/energy_now" ]; then
    # energy_now is often in µWh → Wh = µWh / 1e6
    en_now_uWh=$(cat "/sys/class/power_supply/$bat/energy_now")
    en_now_Wh=$(echo "$en_now_uWh" | awk '{ printf "%.4f", $1 / 1e6 }')
  else
    return 1
  fi

  pw_w=$(bat_power_w "$bat") || return 1

  # hours = Wh / W
  hours=$(echo "$en_now_Wh $pw_w" | awk '{ if ($2 == 0) print 0; else printf "%.4f", $1 / $2 }')
  # seconds = hours * 3600
  seconds=$(echo "$hours" | awk '{ printf "%.0f", $1 * 3600 }')

  h=$(( seconds / 3600 ))
  m=$(( (seconds % 3600) / 60 ))
  s=$(( seconds % 60 ))

  printf "%02d:%02d:%02d" "$h" "$m" "$s"
}

echo "Power status overview"
hr

# AC / Battery + wattage + time remaining
echo "AC / Battery:"
bat=$(detect_bat)
cur_mode="ac"
cur_pct=""

if [ -r "$AC_PATH/online" ]; then
  ac=$(cat "$AC_PATH/online")
  if [ "$ac" = "1" ]; then
    ac_state="AC online"
    cur_mode="ac"
  else
    ac_state="On battery"
    cur_mode="battery"
  fi
  echo "  AC adapter: $ac_state"
fi

if [ -n "$bat" ] && [ -r "/sys/class/power_supply/$bat/status" ]; then
  bat_status=$(cat "/sys/class/power_supply/$bat/status")
  bat_cap=$(cat "/sys/class/power_supply/$bat/capacity" 2>/dev/null)
  cur_pct="$bat_cap"
  echo "  Battery:   $bat_status (${bat_cap:-?}%)"

  pw=$(bat_power_w "$bat" 2>/dev/null)
  if [ -n "$pw" ]; then
    echo "  Power:     ${pw} W"
  fi

  # Only show time remaining when discharging and we have power
  if [ "$bat_status" = "Discharging" ] && [ -n "$pw" ]; then
    tr=$(bat_time_remaining "$bat" 2>/dev/null)
    [ -n "$tr" ] && echo "  Time left: ${tr} (approx)"
  fi
fi

elapsed=$(battery_elapsed "$cur_mode" "$cur_pct")
[ "$elapsed" != "-" ] && echo "  Time on battery: $elapsed"
hr

# CPU
echo "CPU (Intel P-state):"
if [ -d "$INTEL_PSTATE_DIR" ]; then
  status=$(cat "$INTEL_PSTATE_DIR/status")
  minp=$(cat "$INTEL_PSTATE_DIR/min_perf_pct")
  maxp=$(cat "$INTEL_PSTATE_DIR/max_perf_pct")
  noturbo=$(cat "$INTEL_PSTATE_DIR/no_turbo")
  echo "  Status:        $status"
  echo "  Min perf pct:  $minp"
  echo "  Max perf pct:  $maxp"
  echo "  Turbo disabled: $noturbo"
fi

if [ -d /sys/devices/system/cpu/cpufreq/policy0 ]; then
  gov=$(cat /sys/devices/system/cpu/cpufreq/policy0/scaling_governor)
  cur_khz=$(cat /sys/devices/system/cpu/cpufreq/policy0/scaling_cur_freq)
  cur_mhz=$(awk "BEGIN { printf \"%.1f\", $cur_khz / 1000.0 }")
  epp_path=/sys/devices/system/cpu/cpufreq/policy0/energy_performance_preference
  [ -r "$epp_path" ] && epp=$(cat "$epp_path") || epp="(no EPP)"
  echo "  Governor:      $gov"
  echo "  Cur freq MHz:  $cur_mhz"
  echo "  EPP policy0:   $epp"
fi

epp_all=$(epp_all_summary)
echo "  EPP all:       $epp_all"
hr


# NVMe
echo "NVMe devices:"
for dev in $NVME_DEVS; do
  base="/sys/class/nvme/$dev"
  if [ -d "$base" ]; then
    ctrl="$base/device"
    ctrl_name=$(basename "$base")
    pctl="(n/a)"
    [ -r "$ctrl/power/control" ] && pctl=$(cat "$ctrl/power/control")
    echo "  $ctrl_name:"
    echo "    power/control: $pctl"
  fi
done
hr

# Wi‑Fi
echo "Wi-Fi ($WIFI_IFACE):"
if ip link show "$WIFI_IFACE" >/dev/null 2>&1; then
  state=$(ip link show "$WIFI_IFACE" | awk '/state/ {print $9}')
  echo "  Link state: $state"
  ps_line=$(iw dev "$WIFI_IFACE" get power_save 2>/dev/null | sed 's/^[[:space:]]*//')
  [ -n "$ps_line" ] && echo "  $ps_line" || echo "  Power save: (unknown)"
else
  echo "  Interface not found"
fi
hr

