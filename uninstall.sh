#!/usr/bin/env bash
# Remove the tlp-battery-care cron schedule and discharge helper, and restore
# normal charging behaviour. Does NOT change /etc/tlp.conf thresholds.
#
#   sudo -E ./uninstall.sh
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=config.sh
source "$HERE/config.sh"

[[ $EUID -eq 0 ]] || { echo "Please run as root:  sudo -E ./uninstall.sh" >&2; exit 1; }

if [[ -f "$CRON_FILE" ]]; then
    rm -f "$CRON_FILE"
    echo "Removed  $CRON_FILE"
fi

DISCHARGE="${INSTALL_BIN_DIR%/}/battery-discharge-to.sh"
if [[ -f "$DISCHARGE" ]]; then
    rm -f "$DISCHARGE"
    echo "Removed  $DISCHARGE"
fi

# Make sure we are not left in force-discharge.
BEHAVIOUR="/sys/class/power_supply/${BATTERY}/charge_behaviour"
if [[ -w "$BEHAVIOUR" ]]; then
    echo auto > "$BEHAVIOUR" 2>/dev/null || true
    echo "Restored charge_behaviour=auto for ${BATTERY}"
fi

echo
echo "Done. To also reset charge thresholds to charge fully again, run e.g.:"
echo "  sudo tlp setcharge 0 100 ${BATTERY}"
