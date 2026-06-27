#!/usr/bin/env bash
# Install the tlp-battery-care discharge helper and cron schedule.
# Reads settings from config.sh (override any of them via the environment).
#
#   sudo -E ./install.sh
#
# Re-run any time after editing config.sh to regenerate the schedule.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=config.sh
source "$HERE/config.sh"

[[ $EUID -eq 0 ]] || { echo "Please run as root:  sudo -E ./install.sh" >&2; exit 1; }

# --- locate tlp --------------------------------------------------------------
TLP_BIN="$(command -v tlp 2>/dev/null || true)"
[[ -z "$TLP_BIN" && -x /usr/sbin/tlp ]] && TLP_BIN=/usr/sbin/tlp
[[ -n "$TLP_BIN" ]] || {
    echo "tlp not found. Install it first, e.g.:" >&2
    echo "  Debian/Ubuntu: sudo apt install tlp" >&2
    echo "  Fedora:        sudo dnf install tlp" >&2
    echo "  Arch:          sudo pacman -S tlp"   >&2
    exit 1
}

# --- sanity-check the battery ------------------------------------------------
SYS="/sys/class/power_supply/${BATTERY}"
[[ -e "$SYS" ]] || {
    echo "Battery '${BATTERY}' not found under /sys/class/power_supply/." >&2
    echo "Available: $(ls /sys/class/power_supply/ 2>/dev/null | tr '\n' ' ')" >&2
    exit 1
}
if [[ ! -e "$SYS/charge_behaviour" ]]; then
    echo "WARNING: $SYS/charge_behaviour is missing." >&2
    echo "         Force-discharge is likely unsupported on this hardware/kernel;" >&2
    echo "         the nightly threshold pinning will still work, but the discharge" >&2
    echo "         step will be a no-op. Continuing anyway." >&2
fi

# --- install the discharge helper -------------------------------------------
DISCHARGE="${INSTALL_BIN_DIR%/}/battery-discharge-to.sh"
install -D -m 0755 "$HERE/bin/battery-discharge-to.sh" "$DISCHARGE"
echo "Installed  $DISCHARGE"

# --- generate the cron schedule ----------------------------------------------
cat > "$CRON_FILE" <<EOF
# === Battery longevity schedule (managed by tlp-battery-care) ===
#
# Overnight: hold charge low (~${NIGHT_DISCHARGE_TARGET}%) to reduce wear.
# Morning:   charge to full (${DAY_STOP_THRESHOLD}%) before the workday.
#
# Generated from config.sh by install.sh -- edit config.sh and re-run, do not
# hand-edit this file.
#
# GOTCHAS:
#   * The laptop must stay AWAKE and on AC overnight: force-discharge needs AC,
#     and cron does not fire while the machine is suspended.
#   * Logs go to the journal:  journalctl -t battery-care --since today
#   * This is the single source of truth for battery scheduling -- do not add
#     duplicate tlp setcharge/discharge lines to your personal crontab.

SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# ${NIGHT_HOUR}:00 every night -- drain to ${NIGHT_DISCHARGE_TARGET}%, then hold ${NIGHT_START_THRESHOLD}-${NIGHT_STOP_THRESHOLD}%.
0 ${NIGHT_HOUR} * * * ${CRON_USER} ${DISCHARGE} ${NIGHT_DISCHARGE_TARGET} ${BATTERY} && ${TLP_BIN} setcharge ${NIGHT_START_THRESHOLD} ${NIGHT_STOP_THRESHOLD} ${BATTERY}

# ${MORNING_HOUR}:00 (day-of-week ${WORKDAYS}) -- charge to ${DAY_START_THRESHOLD}-${DAY_STOP_THRESHOLD}% for the day.
0 ${MORNING_HOUR} * * ${WORKDAYS} ${CRON_USER} ${TLP_BIN} setcharge ${DAY_START_THRESHOLD} ${DAY_STOP_THRESHOLD} ${BATTERY}
EOF
chmod 0644 "$CRON_FILE"
echo "Installed  $CRON_FILE"

echo
echo "Done. Current schedule:"
echo "  ${NIGHT_HOUR}:00 daily      -> discharge to ${NIGHT_DISCHARGE_TARGET}%, hold ${NIGHT_START_THRESHOLD}-${NIGHT_STOP_THRESHOLD}%"
echo "  ${MORNING_HOUR}:00 (dow ${WORKDAYS}) -> charge to ${DAY_START_THRESHOLD}-${DAY_STOP_THRESHOLD}%"
echo
echo "Verify a run with:  journalctl -t battery-care --since today"
echo "Email monitoring is optional -- see monitoring/README.md"
