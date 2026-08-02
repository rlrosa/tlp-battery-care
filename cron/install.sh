#!/usr/bin/env bash
# Retired entrypoint retained to direct existing users to the supported mode.
set -euo pipefail

echo "The cron variant is no longer supported: it cannot handle sleep, resume, or shutdown safely." >&2
echo "Use: sudo -E systemd/install.sh" >&2
exit 1
