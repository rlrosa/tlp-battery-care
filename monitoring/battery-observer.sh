#!/usr/bin/env bash
# Observe the battery's charge_behaviour and email on every force-discharge
# start and return-to-auto, plus a one-shot low-battery warning.
#
# This is INDEPENDENT of the install.sh cron/scripts: it only READS the kernel
# state, so it reports whatever actually happens regardless of what scheduled
# it. Meant to run for a few days while you gain confidence, then be stopped.
#
# Runs as a normal user (reading sysfs + curl need no root).
#
# Usage:   battery-observer.sh [BAT] [POLL_SECONDS]
#
# Required environment (see battery-observer.env.example):
#   BATTERY_OBSERVER_TO      destination email address
#   BATTERY_OBSERVER_RELAY   SMTP relay URL, e.g. smtp://smtp.example.com:25
# Optional:
#   BATTERY_OBSERVER_FROM    sender address (default battery-observer@<host>)
#   BATTERY_OBSERVER_LOW     low-battery warning threshold % (default 40)
#
# Logs to journal tag "battery-observer":  journalctl -t battery-observer
set -euo pipefail

BAT="${1:-BAT0}"
POLL="${2:-30}"
LOW="${BATTERY_OBSERVER_LOW:-40}"   # warn once if charge drops below this %
TO="${BATTERY_OBSERVER_TO:?set BATTERY_OBSERVER_TO to the destination email}"
RELAY="${BATTERY_OBSERVER_RELAY:?set BATTERY_OBSERVER_RELAY, e.g. smtp://smtp.example.com:25}"
FROM="${BATTERY_OBSERVER_FROM:-battery-observer@$(hostname -f 2>/dev/null || hostname)}"

SYS="/sys/class/power_supply/${BAT}"
BEHAVIOUR="${SYS}/charge_behaviour"
CAP="${SYS}/capacity"
START="${SYS}/charge_control_start_threshold"
STOP="${SYS}/charge_control_end_threshold"
HOST="$(hostname)"

[[ -r "$BEHAVIOUR" ]] || { echo "Cannot read $BEHAVIOUR" >&2; exit 1; }

log() { logger -t battery-observer -- "$*"; }

# The active behaviour is the [bracketed] token, e.g. "auto inhibit-charge [force-discharge]".
current_state() { grep -oP '\[\K[^]]+' "$BEHAVIOUR"; }

# The charge thresholds set by "tlp setcharge", as "START-STOP" (e.g. "45-50").
# These are separate sysfs files from charge_behaviour, so behaviour-only
# watching never sees them change. Returns "n/a" if the kernel doesn't expose
# them for this battery.
current_window() {
    if [[ -r "$START" && -r "$STOP" ]]; then
        echo "$(cat "$START")-$(cat "$STOP")"
    else
        echo "n/a"
    fi
}

send_email() {
    local subject="$1" body="$2" tmp
    tmp=$(mktemp)
    printf 'From: battery-observer <%s>\r\nTo: %s\r\nSubject: %s\r\n\r\n%s\r\n' \
        "$FROM" "$TO" "$subject" "$body" > "$tmp"
    if curl -sS --connect-timeout 10 --url "$RELAY" --mail-from "$FROM" --mail-rcpt "$TO" -T "$tmp"; then
        log "sent: $subject"
    else
        log "EMAIL FAILED: $subject"
    fi
    rm -f "$tmp"
}

notify() {
    local subject="$1" prev="$2" cur="$3" cap="$4"
    send_email "$subject" "Host: ${HOST}
Time: $(date '+%Y-%m-%d %H:%M:%S')
charge_behaviour: ${prev} -> ${cur}
Battery: ${cap}%"
}

prev=$(current_state)
prev_window=$(current_window)
warned_low=0   # 1 once we've emailed the low-battery warning, until charge recovers
log "started; initial state=${prev} window=${prev_window} cap=$(cat "$CAP")% poll=${POLL}s low=${LOW}% to=${TO}"

while :; do
    sleep "$POLL"
    cap=$(cat "$CAP")

    # Charge-threshold window changes (e.g. night 45-50 -> morning 96-100).
    # Written by "tlp setcharge" into files separate from charge_behaviour,
    # so they'd otherwise go unnoticed.
    cur_window=$(current_window)
    if [[ "$cur_window" != "$prev_window" ]]; then
        log "window: ${prev_window} -> ${cur_window} at ${cap}%"
        send_email "[battery] charge window ${prev_window} -> ${cur_window}" "Host: ${HOST}
Time: $(date '+%Y-%m-%d %H:%M:%S')
charge window (start-stop): ${prev_window} -> ${cur_window}
Battery: ${cap}%
charge_behaviour: $(current_state)"
        prev_window="$cur_window"
    fi

    # Low-battery warning (independent of charge_behaviour transitions).
    # Fire once on crossing below LOW; re-arm only after recovering a few % above it.
    if (( cap < LOW )) && (( warned_low == 0 )); then
        log "LOW: ${cap}% < ${LOW}%"
        send_email "[battery] WARNING: ${cap}% (below ${LOW}%)" "Host: ${HOST}
Time: $(date '+%Y-%m-%d %H:%M:%S')
Battery: ${cap}% (threshold ${LOW}%)
charge_behaviour: $(current_state)"
        warned_low=1
    elif (( cap >= LOW + 3 )) && (( warned_low == 1 )); then
        log "recovered to ${cap}%; re-arming low warning"
        warned_low=0
    fi

    cur=$(current_state)
    [[ "$cur" == "$prev" ]] && continue
    log "transition: ${prev} -> ${cur} at ${cap}%"
    if [[ "$cur" == "force-discharge" ]]; then
        notify "[battery] discharge STARTED at ${cap}%" "$prev" "$cur" "$cap"
    elif [[ "$prev" == "force-discharge" ]]; then
        notify "[battery] back to AUTO at ${cap}%" "$prev" "$cur" "$cap"
    fi
    prev="$cur"
done
