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

log() { echo "$*"; logger -t battery-care -- "$*" 2>/dev/null || true; }

[[ -w "$BEHAVIOUR" ]] || { log "Need root and a kernel with charge_behaviour ($BEHAVIOUR)"; exit 1; }

# Always restore normal charging on exit, even on Ctrl-C / kill / error.
restore() { echo auto > "$BEHAVIOUR" 2>/dev/null || true; log "restored charge_behaviour=auto"; }
trap restore EXIT INT TERM

now=$(cat "$CAP")
if (( now <= TARGET )); then
    log "Already at ${now}% (target ${TARGET}%); nothing to do."
    exit 0
fi

log "Discharging ${BAT} from ${now}% to ${TARGET}% ..."
echo force-discharge > "$BEHAVIOUR"

# Log progress each time we drop another STEP percent.
STEP=5
last_logged=$now
while :; do
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
