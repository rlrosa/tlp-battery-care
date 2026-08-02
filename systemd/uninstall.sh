#!/usr/bin/env bash
# Remove the event-driven systemd battery-care installation.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
# shellcheck source=../config.sh
source "$ROOT/config.sh"

[[ $EUID -eq 0 ]] || { echo "Please run as root: sudo -E systemd/uninstall.sh" >&2; exit 1; }

UD="${UNIT_DIR%/}"
RD="${RUNTIME_DIR%/}"
SLEEP_HOOK="${SYSTEM_SLEEP_DIR%/}/battery-care"
units=(battery-care-night.timer battery-care-morning.timer battery-care-night.service battery-care-morning.service battery-care-reconcile.service battery-care-low.service battery-care-departure.service)

if command -v systemctl >/dev/null; then
    systemctl disable --now battery-care-night.timer battery-care-morning.timer battery-care-departure.service 2>/dev/null || true
    systemctl stop battery-care-low.service battery-care-reconcile.service 2>/dev/null || true
fi

removed=0
for unit in "${units[@]}"; do
    if [[ -f "$UD/$unit" ]]; then
        rm -f "$UD/$unit"
        echo "Removed $UD/$unit"
        removed=1
    fi
done
if [[ -f "$SLEEP_HOOK" ]]; then
    rm -f "$SLEEP_HOOK"
    echo "Removed $SLEEP_HOOK"
fi
rm -f "$RD/battery-care.conf"
rmdir "$RD" 2>/dev/null || true

for helper in battery-discharge-to.sh battery-care-policy.sh; do
    path="${INSTALL_BIN_DIR%/}/$helper"
    [[ -f "$path" ]] && { rm -f "$path"; echo "Removed $path"; }
done

if command -v systemctl >/dev/null && (( removed )); then systemctl daemon-reload; fi

BEHAVIOUR="/sys/class/power_supply/${BATTERY}/charge_behaviour"
if [[ -w "$BEHAVIOUR" ]]; then
    echo auto > "$BEHAVIOUR" 2>/dev/null || true
    echo "Restored charge_behaviour=auto for ${BATTERY}"
fi
echo "Done. Thresholds are unchanged; use 'tlp setcharge 0 100 ${BATTERY}' to reset them."
