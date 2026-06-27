#!/usr/bin/env bash
# tlp-battery-care bootstrap installer -- no clone required.
#
#   curl -fsSL https://raw.githubusercontent.com/rlrosa/tlp-battery-care/main/get.sh | sudo bash
#
# With custom settings (export first, then -E to pass them through sudo):
#   export NIGHT_HOUR=23 NIGHT_DISCHARGE_TARGET=60
#   curl -fsSL .../get.sh | sudo -E bash
#
# To uninstall:
#   curl -fsSL .../get.sh | sudo bash -s -- uninstall
#
# It just downloads the few files it needs into a temp dir and runs the normal
# install.sh / uninstall.sh from this repo. See config.sh for every tunable.
set -euo pipefail

ACTION="${1:-install}"
REF="${TLP_BATTERY_CARE_REF:-main}"
BASE="${TLP_BATTERY_CARE_RAW:-https://raw.githubusercontent.com/rlrosa/tlp-battery-care/${REF}}"

case "$ACTION" in
    install)   FILES=(config.sh install.sh bin/battery-discharge-to.sh); RUN=install.sh ;;
    uninstall) FILES=(config.sh uninstall.sh);                           RUN=uninstall.sh ;;
    *) echo "Usage: get.sh [install|uninstall]" >&2; exit 2 ;;
esac

command -v curl >/dev/null || { echo "curl is required" >&2; exit 1; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin"

echo "Fetching tlp-battery-care (${REF}) ..."
for f in "${FILES[@]}"; do
    curl -fsSL "${BASE}/${f}" -o "${TMP}/${f}"
done
chmod +x "${TMP}/${RUN}" 2>/dev/null || true
[[ -f "${TMP}/bin/battery-discharge-to.sh" ]] && chmod +x "${TMP}/bin/battery-discharge-to.sh"

exec bash "${TMP}/${RUN}"
