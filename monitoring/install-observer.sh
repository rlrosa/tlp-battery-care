#!/usr/bin/env bash
# OPTIONAL: run battery-observer.sh as a systemd user service so it keeps
# watching across logins. Most people don't need this -- it only matters if
# you want email alerts while validating the schedule.
#
#   1. cp battery-observer.env.example battery-observer.env  && edit it
#   2. ./install-observer.sh         # installs + starts a --user service
#
# Stop/remove later with:
#   systemctl --user disable --now battery-observer.service
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$HERE/battery-observer.env"
BAT="${1:-BAT0}"
POLL="${2:-30}"

[[ -f "$ENV_FILE" ]] || {
    echo "Missing $ENV_FILE" >&2
    echo "Copy the example and edit it first:" >&2
    echo "  cp $HERE/battery-observer.env.example $ENV_FILE" >&2
    exit 1
}

UNIT_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
mkdir -p "$UNIT_DIR"
UNIT="$UNIT_DIR/battery-observer.service"

cat > "$UNIT" <<EOF
[Unit]
Description=Battery charge_behaviour observer (tlp-battery-care)
After=default.target

[Service]
Type=simple
EnvironmentFile=${ENV_FILE}
ExecStart=${HERE}/battery-observer.sh ${BAT} ${POLL}
Restart=on-failure

[Install]
WantedBy=default.target
EOF

echo "Wrote $UNIT"
systemctl --user daemon-reload
systemctl --user enable --now battery-observer.service
echo "Started battery-observer.service"
echo "Logs:  journalctl --user -t battery-observer -f"
echo "Stop:  systemctl --user disable --now battery-observer.service"
