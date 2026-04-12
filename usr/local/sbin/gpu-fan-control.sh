#!/bin/bash
#
# gpu-fan-control.sh — GPU-reactive case fan controller
#
# Leaves CPU_FAN, CPU_OPT, and PCH_FAN under BIOS SmartFan control.
# Controls SYS_FAN1 (rear exhaust) and SYS_FAN2 (front bottom intake)
# based on GPU temperature.
# SYS_FAN4 (front top intake) is not software-controllable.
#
# Designed for: Gigabyte X570 Aorus Master + incoming RTX PRO 6000 Ada
# Fan controllers: ITE IT8688E (primary) + ITE IT8792E (secondary)
#
# Behavior overview:
#
# 1. Finds the IT8688E by scanning hwmon device names, with a short retry window
#    to tolerate sysfs startup races after module load.
# 2. Takes manual control of pwm2 (rear exhaust) and pwm3 (front bottom intake)
#    by setting their pwm_enable to 1, starting them at minimum PWM (60/255).
# 3. Every 3 seconds, reads the highest NVIDIA GPU temperature from nvidia-smi.
# 4. Interpolates a PWM value from the fan curve (40°C→30%, linear ramp up to
#    85°C→100%).
# 5. Writes the new PWM value to both fans, but only if it changed since the last
#    cycle (avoids unnecessary Super I/O writes).
# 6. Logs each change with timestamp, temp source, and PWM percentage.
#
# Fallback chain for temperature reads:
# - Primary: GPU temp via nvidia-smi
# - Secondary: CPU temp via k10temp (e.g. if GPU driver isn't loaded yet)
# - Failsafe: if neither is readable for 5 consecutive cycles (15 seconds), set
#   fans to 100%
#
# On exit (Ctrl+C, SIGTERM, service stop, or crash):
# - A trap restores pwm_enable to 2 on both fans, handing them back to BIOS SmartFan
# - The systemd service can also call this script with --restore for a redundant
#   best-effort handoff if the main process exits badly

set -euo pipefail

INTERVAL=3            # seconds between updates
HWMON_RETRIES=10      # tolerate hwmon appearance races at startup
HWMON_RETRY_DELAY=1   # seconds between hwmon lookup attempts
CONTROLLED_PWM_IDS=(2 3)

# Fan curve: GPU_TEMP -> PWM (0-255)
# Tuned for RTX PRO 6000 Ada (300W TDP)
#
#   GPU °C    PWM%    RPM (approx)    Rationale
#   ≤40       30%     low             idle/desktop
#    50       40%                     light work
#    60       50%                     moderate load
#    70       65%                     sustained compute
#    78       80%                     heavy load
#    85      100%     max             thermal limit
#
CURVE_TEMPS=(40 50 60 70 78 85)
CURVE_PWMS=(77 102 128 166 204 255)

# Minimum PWM the fans will reliably spin at (don't go below this)
MIN_PWM=60

find_hwmon() {
    local target="$1"
    local hwmon

    for hwmon in /sys/class/hwmon/hwmon*; do
        [ -r "$hwmon/name" ] || continue
        if [ "$(<"$hwmon/name")" = "$target" ]; then
            echo "$hwmon"
            return 0
        fi
    done

    return 1
}

wait_for_hwmon() {
    local target="$1"
    local attempts="$2"
    local delay="$3"
    local attempt
    local hwmon

    for (( attempt=1; attempt<=attempts; attempt++ )); do
        hwmon=$(find_hwmon "$target") && {
            echo "$hwmon"
            return 0
        }

        if (( attempt < attempts )); then
            sleep "$delay"
        fi
    done

    return 1
}

restore_case_fans_to_bios() {
    local it8688
    local enable_path
    local pwm_id

    it8688=$(find_hwmon "it8688") || {
        echo "WARNING: hwmon device 'it8688' not found; nothing to restore" >&2
        return 0
    }

    for pwm_id in "${CONTROLLED_PWM_IDS[@]}"; do
        enable_path="$it8688/pwm${pwm_id}_enable"
        [ -f "$enable_path" ] && echo 2 > "$enable_path" 2>/dev/null || true
    done
}

if [[ "${1:-}" == "--restore" ]]; then
    restore_case_fans_to_bios
    exit 0
fi

if (( $# != 0 )); then
    echo "Usage: $0 [--restore]" >&2
    exit 2
fi

IT8688=$(wait_for_hwmon "it8688" "$HWMON_RETRIES" "$HWMON_RETRY_DELAY") || {
    echo "ERROR: hwmon device 'it8688' not found after ${HWMON_RETRIES} attempts" >&2
    exit 1
}

# Verified fan mapping (Gigabyte X570 Aorus Master rev 1.1):
#   IT8688E pwm1 = CPU_FAN      — leave on BIOS
#   IT8688E pwm2 = SYS_FAN1     (rear exhaust)
#   IT8688E pwm3 = SYS_FAN2     (front bottom intake, BQ SW3 HF)
#   IT8688E pwm4 = PCH_FAN or CPU_OPT — leave on BIOS
#   IT8688E pwm5 = PCH_FAN or CPU_OPT — leave on BIOS
#   IT8792E fan3 = SYS_FAN4     (front top intake, BQ SW3 LF) — not software-controllable
CASE_FANS=("$IT8688/pwm2" "$IT8688/pwm3")
CASE_FAN_NAMES=("SYS_FAN1/rear-exhaust" "SYS_FAN2/front-bottom-intake")
K10TEMP_HWMON=""
RESTORED=0

restore_bios_control() {
    if (( RESTORED )); then
        return
    fi

    RESTORED=1
    echo "Restoring BIOS SmartFan control on case fans..."
    restore_case_fans_to_bios
    echo "Done. Exiting."
}

handle_exit_signal() {
    exit 0
}

trap restore_bios_control EXIT
trap handle_exit_signal INT TERM

# --- Take manual control of case fans ---

for i in "${!CASE_FANS[@]}"; do
    pwm="${CASE_FANS[$i]}"
    if [ ! -f "${pwm}_enable" ]; then
        echo "ERROR: ${pwm}_enable not found" >&2
        exit 1
    fi
    echo 1 > "${pwm}_enable"
    echo "$MIN_PWM" > "$pwm"
    echo "Took manual control of ${CASE_FAN_NAMES[$i]}"
done

# --- Interpolate fan curve ---

interpolate_pwm() {
    local temp="$1"
    local len=${#CURVE_TEMPS[@]}

    # Below curve: minimum curve value
    if (( temp <= CURVE_TEMPS[0] )); then
        echo "${CURVE_PWMS[0]}"
        return
    fi

    # Above curve: maximum
    if (( temp >= CURVE_TEMPS[len-1] )); then
        echo "${CURVE_PWMS[len-1]}"
        return
    fi

    # Linear interpolation between curve points
    for (( i=1; i<len; i++ )); do
        if (( temp <= CURVE_TEMPS[i] )); then
            local t0=${CURVE_TEMPS[i-1]}
            local t1=${CURVE_TEMPS[i]}
            local p0=${CURVE_PWMS[i-1]}
            local p1=${CURVE_PWMS[i]}
            local pwm=$(( p0 + (temp - t0) * (p1 - p0) / (t1 - t0) ))
            echo "$pwm"
            return
        fi
    done
}

# --- Read GPU temperature ---

get_gpu_temp() {
    # Use the hottest NVIDIA GPU if multiple are present.
    local temp
    temp=$(
        nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader,nounits 2>/dev/null \
        | awk 'BEGIN { max = "" } /^[0-9]+$/ { if (max == "" || $1 > max) max = $1 } END { if (max != "") print max }'
    )

    if [ -z "$temp" ]; then
        return 1
    fi

    echo "$temp"
}

# --- Also read CPU temp as a secondary input ---

get_cpu_temp() {
    local raw

    if [ -z "$K10TEMP_HWMON" ] || [ ! -r "$K10TEMP_HWMON/temp1_input" ]; then
        K10TEMP_HWMON=$(find_hwmon "k10temp") || return 1
    fi

    read -r raw < "$K10TEMP_HWMON/temp1_input" || return 1
    [[ "$raw" =~ ^[0-9]+$ ]] || return 1
    echo $(( raw / 1000 ))
}

# --- Main loop ---

echo "gpu-fan-control started (interval=${INTERVAL}s)"
echo "Fan curve: ${CURVE_TEMPS[*]} °C -> ${CURVE_PWMS[*]} PWM"

echo "Monitoring highest available NVIDIA GPU temperature"

FAILSAFE_COUNT=0
LAST_PWM=0

while true; do
    gpu_temp=$(get_gpu_temp) || gpu_temp=""
    cpu_temp=$(get_cpu_temp) || cpu_temp=""

    # Use GPU temp as primary driver; fall back to CPU temp; failsafe if neither
    if [ -n "$gpu_temp" ]; then
        drive_temp=$gpu_temp
        temp_source="GPU"
        FAILSAFE_COUNT=0
    elif [ -n "$cpu_temp" ]; then
        drive_temp=$cpu_temp
        temp_source="CPU(fallback)"
        FAILSAFE_COUNT=0
    else
        FAILSAFE_COUNT=$((FAILSAFE_COUNT + 1))
        if (( FAILSAFE_COUNT >= 5 )); then
            # Can't read any temp for 15s — go full speed for safety
            drive_temp=999
            temp_source="FAILSAFE"
        else
            sleep "$INTERVAL"
            continue
        fi
    fi

    target_pwm=$(interpolate_pwm "$drive_temp")

    # Enforce minimum
    if (( target_pwm < MIN_PWM )); then
        target_pwm=$MIN_PWM
    fi

    # Only write if changed (reduce I/O writes to the Super I/O)
    if (( target_pwm != LAST_PWM )); then
        for pwm in "${CASE_FANS[@]}"; do
            echo "$target_pwm" > "$pwm"
        done
        echo "$(date '+%H:%M:%S') ${temp_source}=${drive_temp}°C -> PWM=${target_pwm}/255 ($(( target_pwm * 100 / 255 ))%)"
        LAST_PWM=$target_pwm
    fi

    sleep "$INTERVAL"
done
