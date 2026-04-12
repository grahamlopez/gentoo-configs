#!/bin/bash
set -euo pipefail

SERVICE=gpu-fan-control.service
MIN_PWM=60
HIGH_PWM=255
PULSE_SECONDS=10
RPM_SETTLE_SECONDS=2
RPM_AFTER_RESTORE_SECONDS=3

usage() {
    cat <<'EOF'
Usage:
  sudo ./poke-fan.sh <pwm2|pwm3|2|3> [pulse|stop]

Examples:
  sudo ./poke-fan.sh pwm2 pulse
  sudo ./poke-fan.sh 3 stop

Modes:
  pulse  Safer default: max -> min -> restore BIOS control
  stop   Briefly set PWM to 0 -> restore BIOS control

This script will:
  - stop gpu-fan-control.service if it is running
  - print a full snapshot before, during, and after the poke, including:
      * selected pwm value and enable mode
      * all pwmN / pwmN_enable values on the it8688 hwmon node
      * selected RPM input (when available)
      * all fan*_input readings on the it8688 hwmon node
  - put the selected fan header into manual mode
  - apply the requested test pattern
  - restore BIOS control afterward
  - restart the service if it was running before
EOF
}

log() {
    printf '%s\n' "$*"
}

warn() {
    printf 'WARNING: %s\n' "$*" >&2
}

if (( $# < 1 || $# > 2 )); then
    usage >&2
    exit 2
fi

case "$1" in
    pwm2|2)
        PWM_ID=2
        FAN_NAME="SYS_FAN1 / rear exhaust"
        ;;
    pwm3|3)
        PWM_ID=3
        FAN_NAME="SYS_FAN2 / front bottom intake"
        ;;
    *)
        usage >&2
        exit 2
        ;;
esac

MODE=${2:-pulse}
case "$MODE" in
    pulse|stop)
        ;;
    *)
        usage >&2
        exit 2
        ;;
esac

find_it8688() {
    local hwmon
    for hwmon in /sys/class/hwmon/hwmon*; do
        [ -r "$hwmon/name" ] || continue
        if [ "$(<"$hwmon/name")" = "it8688" ]; then
            echo "$hwmon"
            return 0
        fi
    done
    return 1
}

find_rpm_input() {
    local candidate="$HWMON/fan${PWM_ID}_input"
    if [ -r "$candidate" ]; then
        echo "$candidate"
        return 0
    fi
    return 1
}

read_sysfs_value() {
    local path="$1"
    local raw

    if [ ! -r "$path" ]; then
        echo "unavailable"
        return 0
    fi

    if read -r raw < "$path"; then
        if [[ "$raw" =~ ^[0-9]+$ ]]; then
            echo "$raw"
        else
            echo "invalid:${raw}"
        fi
    else
        echo "read-error"
    fi
}

read_rpm() {
    if [ -z "${RPM_INPUT:-}" ]; then
        echo "unavailable"
        return 0
    fi

    read_sysfs_value "$RPM_INPUT"
}

log_rpm() {
    local phase="$1"
    local rpm
    rpm=$(read_rpm)
    log "RPM ${phase}: ${rpm}"
}

log_selected_pwm_state() {
    local phase="$1"
    local pwm_value
    local enable_value

    pwm_value=$(read_sysfs_value "$PWM_PATH")
    enable_value=$(read_sysfs_value "$ENABLE_PATH")
    log "Selected PWM ${phase}: pwm${PWM_ID}=${pwm_value} enable=${enable_value}"
}

log_all_pwm_state() {
    local phase="$1"
    local path
    local label
    local pwm_value
    local enable_value
    local entries=()

    for path in "$HWMON"/pwm[1-9] "$HWMON"/pwm[1-9][0-9]; do
        [ -e "$path" ] || continue
        [ -f "$path" ] || continue
        label=$(basename "$path")
        pwm_value=$(read_sysfs_value "$path")
        enable_value=$(read_sysfs_value "${path}_enable")
        entries+=("${label}=${pwm_value}(enable=${enable_value})")
    done

    if (( ${#entries[@]} == 0 )); then
        log "All PWM ${phase}: unavailable"
    else
        log "All PWM ${phase}: ${entries[*]}"
    fi
}

log_all_rpms() {
    local phase="$1"
    local path
    local label
    local rpm_value
    local entries=()

    for path in "$HWMON"/fan*_input; do
        [ -r "$path" ] || continue
        label=$(basename "$path" _input)
        rpm_value=$(read_sysfs_value "$path")
        entries+=("${label}=${rpm_value}")
    done

    if (( ${#entries[@]} == 0 )); then
        log "All RPM ${phase}: unavailable"
    else
        log "All RPM ${phase}: ${entries[*]}"
    fi
}

log_snapshot() {
    local phase="$1"
    log "--- Snapshot: ${phase} ---"
    log_selected_pwm_state "$phase"
    log_all_pwm_state "$phase"
    log_rpm "$phase"
    log_all_rpms "$phase"
}

restore() {
    if [ -n "${PWM_PATH:-}" ] && [ -f "${PWM_PATH}_enable" ]; then
        echo 2 > "${PWM_PATH}_enable" 2>/dev/null || true
    fi

    if (( RESTART_SERVICE )); then
        log "Restarting ${SERVICE}..."
        systemctl start "$SERVICE" || warn "failed to restart ${SERVICE}"
    fi
}

RESTART_SERVICE=0
PWM_PATH=""
trap restore EXIT INT TERM

if systemctl is-active --quiet "$SERVICE"; then
    RESTART_SERVICE=1
    log "Stopping ${SERVICE}..."
    systemctl stop "$SERVICE"
fi

HWMON=$(find_it8688) || {
    warn "could not find it8688 hwmon device"
    exit 1
}

PWM_PATH="$HWMON/pwm${PWM_ID}"
ENABLE_PATH="${PWM_PATH}_enable"
RPM_INPUT=$(find_rpm_input || true)

if [ ! -f "$PWM_PATH" ] || [ ! -f "$ENABLE_PATH" ]; then
    warn "missing control files for pwm${PWM_ID} under $HWMON"
    exit 1
fi

log "Testing pwm${PWM_ID} (${FAN_NAME})"
log "hwmon path: $HWMON"
log "pwm path: $PWM_PATH"
log "enable path: $ENABLE_PATH"
if [ -n "$RPM_INPUT" ]; then
    log "selected RPM input: $RPM_INPUT"
else
    warn "no obvious RPM input found for pwm${PWM_ID}; full RPM snapshots may still identify the tach"
fi
log_snapshot "before"
log "Putting header into manual mode..."
echo 1 > "$ENABLE_PATH"
log_snapshot "after-manual-enable"

case "$MODE" in
    pulse)
        log "Setting pwm${PWM_ID} to ${HIGH_PWM} for ${PULSE_SECONDS}s..."
        echo "$HIGH_PWM" > "$PWM_PATH"
        sleep "$RPM_SETTLE_SECONDS"
        log_snapshot "during-high"
        sleep "$(( PULSE_SECONDS - RPM_SETTLE_SECONDS ))"

        log "Setting pwm${PWM_ID} to ${MIN_PWM} for ${PULSE_SECONDS}s..."
        echo "$MIN_PWM" > "$PWM_PATH"
        sleep "$RPM_SETTLE_SECONDS"
        log_snapshot "during-low"
        sleep "$(( PULSE_SECONDS - RPM_SETTLE_SECONDS ))"
        ;;
    stop)
        warn "Brief stop test: only use while system is idle."
        log "Setting pwm${PWM_ID} to 0 for ${PULSE_SECONDS}s..."
        echo 0 > "$PWM_PATH"
        sleep "$RPM_SETTLE_SECONDS"
        log_snapshot "during-stop"
        sleep "$(( PULSE_SECONDS - RPM_SETTLE_SECONDS ))"
        ;;
esac

log "Restoring BIOS control to pwm${PWM_ID}..."
echo 2 > "$ENABLE_PATH"
log_snapshot "immediately-after-restore"
sleep "$RPM_AFTER_RESTORE_SECONDS"
log_snapshot "after-restore"
PWM_PATH=""

log "Done. Observe which fan changed."
