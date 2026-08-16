#!/usr/bin/env bash
# Helper script to enable, disable, or check status of tlp-battery-care protection.
#
# Usage: sudo ./bin/battery-care-toggle.sh [enable|disable|on|off|max|status]
#   enable / on:  Re-enable systemd timers and reconcile battery care policy
#   disable / off: Disable systemd timers and set charge threshold to 100%
#   status:        Show current timer, service, and battery status
set -euo pipefail

CONFIG="${BATTERY_CARE_CONFIG:-/etc/tlp-battery-care/battery-care.conf}"
POWER_SUPPLY_DIR="${POWER_SUPPLY_DIR:-/sys/class/power_supply}"
SYSTEMCTL_BIN="${SYSTEMCTL_BIN:-/usr/bin/systemctl}"
TLP_BIN="${TLP_BIN:-}"
INSTALL_BIN_DIR="${INSTALL_BIN_DIR:-/usr/local/bin}"

log() { echo "$*"; logger -t battery-care -- "$*" 2>/dev/null || true; }

# Default battery name
BATTERY="BAT0"

# Load runtime config if available
if [[ -r "$CONFIG" ]]; then
    # shellcheck disable=SC1090
    source "$CONFIG"
fi

if [[ -z "$TLP_BIN" ]]; then
    TLP_BIN="$(command -v tlp 2>/dev/null || true)"
    [[ -z "$TLP_BIN" && -x /usr/sbin/tlp ]] && TLP_BIN=/usr/sbin/tlp
fi

MODE="${1:-status}"

case "$MODE" in
    enable|on|auto)
        log "Enabling battery-care policy..."
        "$SYSTEMCTL_BIN" enable --now battery-care-night.timer battery-care-morning.timer battery-care-departure.service 2>/dev/null || true
        
        POLICY_SCRIPT="${INSTALL_BIN_DIR%/}/battery-care-policy.sh"
        LOCAL_POLICY="$(dirname "$0")/battery-care-policy.sh"
        
        if [[ -x "$POLICY_SCRIPT" ]]; then
            "$POLICY_SCRIPT" reconcile
        elif [[ -x "$LOCAL_POLICY" ]]; then
            "$LOCAL_POLICY" reconcile
        else
            "$SYSTEMCTL_BIN" start battery-care-reconcile.service 2>/dev/null || true
        fi
        log "Battery care protection ENABLED."
        ;;

    disable|off|max)
        log "Disabling battery-care policy..."
        "$SYSTEMCTL_BIN" disable --now battery-care-night.timer battery-care-morning.timer battery-care-departure.service 2>/dev/null || true
        "$SYSTEMCTL_BIN" stop battery-care-low.service 2>/dev/null || true
        
        if [[ -n "$TLP_BIN" && -x "$TLP_BIN" ]]; then
            log "Setting TLP charge thresholds for ${BATTERY} to max (0-100%)..."
            "$TLP_BIN" setcharge 0 100 "$BATTERY"
        else
            log "Warning: tlp binary not found to set charge thresholds."
        fi
        log "Battery care protection DISABLED."
        ;;

    status)
        echo "=== Battery Care Timers ==="
        "$SYSTEMCTL_BIN" is-enabled battery-care-night.timer battery-care-morning.timer battery-care-departure.service 2>&1 || true
        echo ""
        echo "=== Active Discharge Service ==="
        "$SYSTEMCTL_BIN" status battery-care-low.service --no-pager 2>&1 || true
        echo ""
        echo "=== Battery Status (${BATTERY}) ==="
        if [[ -d "${POWER_SUPPLY_DIR}/${BATTERY}" ]]; then
            [[ -r "${POWER_SUPPLY_DIR}/${BATTERY}/capacity" ]] && echo "Capacity: $(<"${POWER_SUPPLY_DIR}/${BATTERY}/capacity")%"
            [[ -r "${POWER_SUPPLY_DIR}/${BATTERY}/status" ]] && echo "Status: $(<"${POWER_SUPPLY_DIR}/${BATTERY}/status")"
            [[ -r "${POWER_SUPPLY_DIR}/${BATTERY}/charge_behaviour" ]] && echo "Charge Behaviour: $(<"${POWER_SUPPLY_DIR}/${BATTERY}/charge_behaviour")"
        else
            echo "Battery ${BATTERY} not found under ${POWER_SUPPLY_DIR}."
        fi
        ;;

    *)
        echo "Usage: $0 {enable|disable|on|off|max|status}" >&2
        exit 2
        ;;
esac
