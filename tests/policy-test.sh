#!/usr/bin/env bash
# Lightweight policy tests; no TLP or real systemd required.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/power/AC"
LOG="$TMP/actions"
export TEST_LOG="$LOG"

cat > "$TMP/bin/tlp" <<'EOF'
#!/usr/bin/env bash
echo "tlp $*" >> "$TEST_LOG"
EOF
cat > "$TMP/bin/systemctl" <<'EOF'
#!/usr/bin/env bash
echo "systemctl $*" >> "$TEST_LOG"
EOF
cat > "$TMP/bin/date" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  +%H) echo "$DATE_HOUR" ;;
  +%u) echo "$DATE_DOW" ;;
esac
EOF
chmod 0755 "$TMP/bin"/*
printf 'Mains\n' > "$TMP/power/AC/type"

cat > "$TMP/config" <<EOF
BATTERY=BAT0
NIGHT_DISCHARGE_TARGET=50
NIGHT_START_THRESHOLD=45
NIGHT_STOP_THRESHOLD=50
DAY_START_THRESHOLD=96
DAY_STOP_THRESHOLD=100
NIGHT_HOUR=22
MORNING_HOUR=7
WORKDAYS=1-5
TLP_BIN=$TMP/bin/tlp
DISCHARGE_BIN=/bin/true
EOF

run() {
    : > "$LOG"
    BATTERY_CARE_CONFIG="$TMP/config" POWER_SUPPLY_DIR="$TMP/power" \
      SYSTEMCTL_BIN="$TMP/bin/systemctl" DATE_BIN="$TMP/bin/date" \
      DATE_HOUR="$1" DATE_DOW="$2" bash "$ROOT/bin/battery-care-policy.sh" "$3" >>"$LOG" 2>&1
}
expect() { grep -q -- "$1" "$LOG" || { echo "expected '$1':"; cat "$LOG"; exit 1; }; }

# Weekday daytime is normal and cancels active low discharge.
run 12 3 reconcile
expect 'systemctl stop battery-care-low.service'
expect 'tlp setcharge 96 100 BAT0'

# Weekday night on AC sets low thresholds and queues the worker.
printf '1\n' > "$TMP/power/AC/online"
run 23 3 reconcile
expect 'tlp setcharge 45 50 BAT0'
expect 'systemctl restart --no-block battery-care-low.service'

# Weekend stays low, but no AC falls back to normal thresholds.
printf '0\n' > "$TMP/power/AC/online"
run 12 6 reconcile
expect 'tlp setcharge 96 100 BAT0'

# Departure always stops low work and restores normal charging.
run 23 3 departure
expect 'systemctl stop battery-care-low.service'
expect 'tlp setcharge 96 100 BAT0'

# Reconcile during sleep conflict (systemctl restart fails with status 4) does not exit non-zero
printf '1\n' > "$TMP/power/AC/online"
cat > "$TMP/bin/systemctl" <<'EOF'
#!/usr/bin/env bash
echo "systemctl $*" >> "$TEST_LOG"
if [[ "$1" == "restart" ]]; then exit 4; fi
EOF
run 23 3 reconcile
expect 'Warning: could not queue battery-care-low.service'

# Test config threshold auto-derivation when NIGHT_DISCHARGE_TARGET=75
(
    unset NIGHT_START_THRESHOLD NIGHT_STOP_THRESHOLD
    NIGHT_DISCHARGE_TARGET=75 source "$ROOT/config.sh"
    [[ "$NIGHT_STOP_THRESHOLD" == "75" ]] || { echo "expected NIGHT_STOP_THRESHOLD=75, got '$NIGHT_STOP_THRESHOLD'"; exit 1; }
    [[ "$NIGHT_START_THRESHOLD" == "70" ]] || { echo "expected NIGHT_START_THRESHOLD=70, got '$NIGHT_START_THRESHOLD'"; exit 1; }
)

# Test battery-care-toggle.sh disable
: > "$LOG"
BATTERY_CARE_CONFIG="$TMP/config" POWER_SUPPLY_DIR="$TMP/power" \
  SYSTEMCTL_BIN="$TMP/bin/systemctl" TLP_BIN="$TMP/bin/tlp" \
  bash "$ROOT/bin/battery-care-toggle.sh" disable >>"$LOG" 2>&1
expect 'systemctl disable --now battery-care-night.timer battery-care-morning.timer battery-care-departure.service'
expect 'systemctl stop battery-care-low.service'
expect 'tlp setcharge 0 100 BAT0'
expect 'Battery care protection DISABLED.'

# Test battery-care-toggle.sh enable
: > "$LOG"
BATTERY_CARE_CONFIG="$TMP/config" POWER_SUPPLY_DIR="$TMP/power" \
  SYSTEMCTL_BIN="$TMP/bin/systemctl" TLP_BIN="$TMP/bin/tlp" \
  DATE_BIN="$TMP/bin/date" DATE_HOUR="12" DATE_DOW="3" \
  bash "$ROOT/bin/battery-care-toggle.sh" enable >>"$LOG" 2>&1
expect 'systemctl enable --now battery-care-night.timer battery-care-morning.timer battery-care-departure.service'
expect 'Battery care protection ENABLED.'

# Test battery-care-toggle.sh status
: > "$LOG"
BATTERY_CARE_CONFIG="$TMP/config" POWER_SUPPLY_DIR="$TMP/power" \
  SYSTEMCTL_BIN="$TMP/bin/systemctl" TLP_BIN="$TMP/bin/tlp" \
  bash "$ROOT/bin/battery-care-toggle.sh" status >>"$LOG" 2>&1
expect '=== Battery Care Timers ==='

echo "policy tests passed"
