#!/usr/bin/env bash
# Reconcile the installed battery-care policy with the current time and power
# state. This is intentionally a root-only helper: TLP thresholds and the
# battery charge_behaviour sysfs attribute are privileged interfaces.
set -euo pipefail

MODE="${1:-reconcile}"
CONFIG="${BATTERY_CARE_CONFIG:-/etc/tlp-battery-care/battery-care.conf}"

log() { echo "$*"; logger -t battery-care -- "$*" 2>/dev/null || true; }

[[ -r "$CONFIG" ]] || { log "Missing runtime configuration: $CONFIG"; exit 1; }
# The installer writes this root-owned file with shell-escaped values.
# shellcheck disable=SC1090
source "$CONFIG"

POWER_SUPPLY_DIR="${POWER_SUPPLY_DIR:-/sys/class/power_supply}"
SYSTEMCTL_BIN="${SYSTEMCTL_BIN:-/usr/bin/systemctl}"
DATE_BIN="${DATE_BIN:-date}"

set_normal() {
    log "Applying normal charge window ${DAY_START_THRESHOLD}-${DAY_STOP_THRESHOLD}% (${1:-policy})"
    "$TLP_BIN" setcharge "$DAY_START_THRESHOLD" "$DAY_STOP_THRESHOLD" "$BATTERY"
}

set_low() {
    log "Applying low charge window ${NIGHT_START_THRESHOLD}-${NIGHT_STOP_THRESHOLD}%"
    "$TLP_BIN" setcharge "$NIGHT_START_THRESHOLD" "$NIGHT_STOP_THRESHOLD" "$BATTERY"
}

ac_online() {
    local supply type online
    for supply in "$POWER_SUPPLY_DIR"/*; do
        [[ -d "$supply" && -r "$supply/type" && -r "$supply/online" ]] || continue
        type=$(<"$supply/type")
        online=$(<"$supply/online")
        [[ "$type" == "Mains" && "$online" == "1" ]] && return 0
    done
    return 1
}

is_workday() {
    local dow="$1" part start end
    [[ "$WORKDAYS" == "*" ]] && return 0
    IFS=',' read -ra parts <<< "$WORKDAYS"
    for part in "${parts[@]}"; do
        if [[ "$part" == *-* ]]; then
            start=${part%-*}; end=${part#*-}
            (( start == 7 )) && start=0
            (( end == 7 )) && end=0
            if (( start <= end )); then
                (( dow >= start && dow <= end )) && return 0
            else
                (( dow >= start || dow <= end )) && return 0
            fi
        else
            (( part == 7 )) && part=0
            (( dow == part )) && return 0
        fi
    done
    return 1
}

in_normal_interval() {
    local hour dow
    hour=$("$DATE_BIN" +%H)
    hour=$((10#$hour))
    # date %u is 1..7; accept the cron convention 0 or 7 for Sunday.
    dow=$("$DATE_BIN" +%u)
    (( dow == 7 )) && dow=0
    is_workday "$dow" && (( hour >= MORNING_HOUR && hour < NIGHT_HOUR ))
}

stop_low_discharge() {
    "$SYSTEMCTL_BIN" stop battery-care-low.service 2>/dev/null || true
}

case "$MODE" in
    departure)
        # A sleep/shutdown is treated as a possible departure. Stop the
        # long-running low service first so its cleanup cannot outlive this.
        stop_low_discharge
        set_normal "departure (${2:-unknown})"
        ;;
    reconcile)
        if in_normal_interval; then
            stop_low_discharge
            set_normal "normal interval"
        elif ! ac_online; then
            # Mobile use must never be constrained by the overnight policy.
            stop_low_discharge
            set_normal "low interval but AC is offline"
        else
            set_low
            log "Low interval with AC online; starting bounded discharge"
            "$SYSTEMCTL_BIN" restart --no-block battery-care-low.service || log "Warning: could not queue battery-care-low.service"
        fi
        ;;
    discharge)
        # Recheck after systemd has queued this service: a normal-boundary or
        # departure event may have happened between reconcile and service start.
        if in_normal_interval || ! ac_online; then
            log "Not starting discharge: policy is no longer low with AC online"
            exit 0
        fi
        set_low
        exec "$DISCHARGE_BIN" "$NIGHT_DISCHARGE_TARGET" "$BATTERY"
        ;;
    *)
        echo "Usage: $0 {reconcile|departure|discharge}" >&2
        exit 2
        ;;
esac
