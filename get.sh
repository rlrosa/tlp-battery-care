#!/usr/bin/env bash
# tlp-battery-care bootstrap installer -- no clone required.
#
# Install:
#   curl -fsSL https://raw.githubusercontent.com/rlrosa/tlp-battery-care/main/get.sh | sudo bash
# Uninstall:
#   curl -fsSL https://raw.githubusercontent.com/rlrosa/tlp-battery-care/main/get.sh | sudo bash -s -- uninstall
set -euo pipefail

ACTION="${1:-install}"
REF="${TLP_BATTERY_CARE_REF:-main}"
BASE="${TLP_BATTERY_CARE_RAW:-https://raw.githubusercontent.com/rlrosa/tlp-battery-care/${REF}}"

case "$ACTION" in
    install|uninstall) ;;
    *) echo "Usage: get.sh [install|uninstall]" >&2; exit 2 ;;
esac

FILES=(config.sh "systemd/${ACTION}.sh")
[[ "$ACTION" == install ]] && FILES+=(bin/battery-discharge-to.sh bin/battery-care-policy.sh)
RUN="systemd/${ACTION}.sh"
command -v curl >/dev/null || { echo "curl is required" >&2; exit 1; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/systemd"
echo "Fetching tlp-battery-care (${REF}, systemd) ..."
for f in "${FILES[@]}"; do curl -fsSL "${BASE}/${f}" -o "${TMP}/${f}"; done
chmod +x "${TMP}/${RUN}"
find "$TMP/bin" -type f -exec chmod 0755 {} +
exec bash "${TMP}/${RUN}"
