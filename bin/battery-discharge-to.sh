#!/usr/bin/env bash
# Force-discharge the battery down to a target percentage, then stop cleanly.
#
# Requires AC power (you can only force-discharge while plugged in) and a
# kernel that exposes /sys/class/power_supply/<BAT>/charge_behaviour.
#
# Usage: sudo ./battery-discharge-to.sh [TARGET%] [BAT]
#   TARGET%   charge level to drain down to   (default 70)
#   BAT       battery name under /sys          (default BAT0)
#
# Logs to both stdout (manual runs) and the journal (cron runs):
#   journalctl -t battery-care
set -euo pipefail

TARGET="${1:-70}"
BAT="${2:-BAT0}"
SYS="/sys/class/power_supply/${BAT}"
BEHAVIOUR="${SYS}/charge_behaviour"
CAP="${SYS}/capacity"
# A failed firmware request must not leave the scheduler wedged indefinitely.
# Installers set this from NIGHT_DISCHARGE_MAX_RUNTIME_MINUTES; it is also
# useful when the helper is run directly.
MAX_RUNTIME_SECONDS="${BATTERY_DISCHARGE_MAX_RUNTIME_SECONDS:-43200}"

log() { echo "$*"; logger -t battery-care -- "$*" 2>/dev/null || true; }

[[ -w "$BEHAVIOUR" ]] || { log "Need root and a kernel with charge_behaviour ($BEHAVIOUR)"; exit 1; }
[[ "$TARGET" =~ ^[0-9]+$ && "$TARGET" -le 100 ]] || { log "Target must be a percentage from 0 to 100 (got '$TARGET')"; exit 2; }
[[ "$MAX_RUNTIME_SECONDS" =~ ^[1-9][0-9]*$ ]] || { log "BATTERY_DISCHARGE_MAX_RUNTIME_SECONDS must be a positive integer (got '$MAX_RUNTIME_SECONDS')"; exit 2; }

# Always restore normal charging on exit, even on Ctrl-C / kill / error. A
# signal handler is followed by EXIT, so make the cleanup idempotent.
restored=0
restore() {
    (( restored )) && return
    restored=1
    echo auto > "$BEHAVIOUR" 2>/dev/null || true
    log "restored charge_behaviour=auto"
}
trap restore EXIT INT TERM

enable_force_discharge() {
    local mode
    if ! printf '%s\n' force-discharge > "$BEHAVIOUR"; then
        log "Could not set charge_behaviour=force-discharge"
        return 1
    fi
    mode=$(<"$BEHAVIOUR")
    if [[ "$mode" != *"[force-discharge]"* ]]; then
        log "force-discharge did not stick (charge_behaviour=$mode)"
        return 1
    fi
}

ensure_force_discharge() {
    local mode
    mode=$(<"$BEHAVIOUR")
    [[ "$mode" == *"[force-discharge]"* ]] && return 0

    # Firmware commonly restores the default behaviour during suspend/resume.
    # Re-apply the requested mode before continuing the poll loop.
    log "force-discharge is no longer active (charge_behaviour=$mode); re-applying"
    enable_force_discharge
}

now=$(cat "$CAP")
if (( now <= TARGET )); then
    log "Already at ${now}% (target ${TARGET}%); nothing to do."
    exit 0
fi

log "Discharging ${BAT} from ${now}% to ${TARGET}% ..."
enable_force_discharge || exit 1

# Log progress each time we drop another STEP percent.
STEP=5
last_logged=$now
deadline=$((SECONDS + MAX_RUNTIME_SECONDS))
while :; do
    if (( SECONDS >= deadline )); then
        log "Timed out after ${MAX_RUNTIME_SECONDS}s before reaching ${TARGET}%; stopping discharge attempt."
        exit 1
    fi

    ensure_force_discharge || exit 1
    cur=$(cat "$CAP")
    (( cur > TARGET )) || break
    if (( last_logged - cur >= STEP )); then
        log "  ... ${cur}% (target ${TARGET}%)"
        last_logged=$cur
    fi
    sleep 60
done

log "Reached $(cat "$CAP")%; restoring normal charging."
# restore() runs via trap on exit
