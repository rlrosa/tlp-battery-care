#!/usr/bin/env bash
# tlp-battery-care configuration.
#
# Edit the values below, then run:
#   sudo -E systemd/install.sh
#
# Every value can also be overridden from the environment, which is handy for
# one-off installs without editing this file:
#   BATTERY=BAT1 NIGHT_DISCHARGE_TARGET=60 sudo -E systemd/install.sh
#
# The defaults below are a sane "work laptop" profile: keep the battery low
# overnight to reduce wear, then charge to full before the workday.

# Which battery to manage. Look under /sys/class/power_supply/ (usually BAT0,
# sometimes BAT1).
: "${BATTERY:=BAT0}"

# --- Overnight: hold the charge LOW to reduce wear ---------------------------
# At night, force-discharge down to this percentage...
: "${NIGHT_DISCHARGE_TARGET:=50}"
# ...then pin TLP charge thresholds so it floats in this window overnight.
: "${NIGHT_STOP_THRESHOLD:=${NIGHT_DISCHARGE_TARGET}}"
: "${NIGHT_START_THRESHOLD:=$((NIGHT_STOP_THRESHOLD > 5 ? NIGHT_STOP_THRESHOLD - 5 : 0))}"
# Stop a failed discharge attempt from blocking all later nightly runs. This
# counts the helper's running time; it will re-check force-discharge on every
# poll so a suspend/resume reset is normally recovered automatically.
: "${NIGHT_DISCHARGE_MAX_RUNTIME_MINUTES:=720}"

# --- Morning: charge to FULL for the day -------------------------------------
: "${DAY_START_THRESHOLD:=96}"     # resume charging below this %
: "${DAY_STOP_THRESHOLD:=100}"     # charge all the way up

# --- Schedule (24h clock, machine local time) --------------------------------
: "${NIGHT_HOUR:=22}"      # hour to discharge down to the night target
: "${MORNING_HOUR:=7}"     # hour to charge back up to full
: "${WORKDAYS:=1-5}"       # Cron-style days for the normal daytime interval.
                           # 1-5 = Mon-Fri (weekends stay low). Use * for daily.

# --- Install locations -------------------------------------------------------
: "${INSTALL_BIN_DIR:=/usr/local/bin}"     # where the discharge helper lands
: "${UNIT_DIR:=/etc/systemd/system}"       # where the generated units land
: "${RUNTIME_DIR:=/etc/tlp-battery-care}"  # generated root-only runtime config
: "${SYSTEM_SLEEP_DIR:=/usr/lib/systemd/system-sleep}" # lifecycle hook location
