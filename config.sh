#!/usr/bin/env bash
# tlp-battery-care configuration.
#
# Edit the values below, then run:  sudo -E ./install.sh
#
# Every value can also be overridden from the environment, which is handy for
# one-off installs without editing this file:
#   BATTERY=BAT1 NIGHT_DISCHARGE_TARGET=60 sudo -E ./install.sh
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
: "${NIGHT_START_THRESHOLD:=45}"   # resume charging if it drops below this %
: "${NIGHT_STOP_THRESHOLD:=50}"    # stop charging once it reaches this %

# --- Morning: charge to FULL for the day -------------------------------------
: "${DAY_START_THRESHOLD:=96}"     # resume charging below this %
: "${DAY_STOP_THRESHOLD:=100}"     # charge all the way up

# --- Schedule (24h clock, machine local time) --------------------------------
: "${NIGHT_HOUR:=22}"      # hour to discharge down to the night target
: "${MORNING_HOUR:=7}"     # hour to charge back up to full
: "${WORKDAYS:=1-5}"       # cron day-of-week for the morning charge.
                           # 1-5 = Mon-Fri (weekends stay low). Use * for daily.

# --- Install locations -------------------------------------------------------
: "${INSTALL_BIN_DIR:=/usr/local/bin}"     # where the discharge helper lands
: "${CRON_FILE:=/etc/cron.d/battery-care}" # generated cron schedule
: "${CRON_USER:=root}"                     # user the cron jobs run as
