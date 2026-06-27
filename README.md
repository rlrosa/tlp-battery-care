# tlp-battery-care

Keep a laptop battery healthy by holding it at a **low charge overnight** and
topping it up to **full just before you need it**. Lithium batteries wear
faster when held near 100% for long stretches, so sitting plugged in at a desk
all night (and all weekend) is exactly what you want to avoid.

This repo is a thin, scriptable layer on top of [TLP](https://linrunner.de/tlp/)
and `cron`:

- **22:00 every night** — force-discharge down to ~50%, then pin TLP charge
  thresholds so it floats around 45–50% all night.
- **07:00 Mon–Fri** — charge back up to 100% so it's full for the workday.
- **Weekends** — the morning charge is skipped, so the battery rests low until
  Monday morning.

Those are the defaults (a work-laptop profile); everything is configurable in
[`config.sh`](config.sh).

## Requirements

- Linux with **TLP** installed (`apt install tlp` / `dnf install tlp` / `pacman -S tlp`).
- A kernel that exposes `charge_behaviour` for your battery — check:
  ```bash
  cat /sys/class/power_supply/BAT0/charge_behaviour
  # e.g. [auto] inhibit-charge force-discharge
  ```
  Threshold pinning works without `force-discharge`, but the nightly *discharge*
  step needs it. This is common on ThinkPads and many recent laptops.
- `cron` (most distros ship it; otherwise `apt install cron`).
- The laptop must stay **awake and on AC overnight** — `cron` doesn't fire while
  suspended, and force-discharge requires AC power.

## Quick start (no clone)

```bash
curl -fsSL https://raw.githubusercontent.com/rlrosa/tlp-battery-care/main/get.sh | sudo bash
```

That installs the discharge helper to `/usr/local/bin` and generates
`/etc/cron.d/battery-care` with the default schedule. To use your own settings,
export them first and add `-E` so `sudo` passes them through:

```bash
export NIGHT_HOUR=23 NIGHT_DISCHARGE_TARGET=60 MORNING_HOUR=8
curl -fsSL https://raw.githubusercontent.com/rlrosa/tlp-battery-care/main/get.sh | sudo -E bash
```

Uninstall the same way:

```bash
curl -fsSL https://raw.githubusercontent.com/rlrosa/tlp-battery-care/main/get.sh | sudo bash -s -- uninstall
```

> The one-liner just downloads the few files it needs and runs the same
> `install.sh`. Prefer to read before you run? `curl` the URL on its own first,
> or clone and install locally (below).

## Quick start (clone)

```bash
git clone https://github.com/rlrosa/tlp-battery-care
cd tlp-battery-care

# (optional) edit config.sh to taste — the defaults are sensible
sudo -E ./install.sh
```

`install.sh` will:

1. install `battery-discharge-to.sh` to `/usr/local/bin`, and
2. generate `/etc/cron.d/battery-care` from your config.

That's it. Check that a run did what you expect:

```bash
journalctl -t battery-care --since today
```

To change anything later, edit `config.sh` and re-run `sudo -E ./install.sh`.
To remove everything:

```bash
sudo -E ./uninstall.sh
```

## Configuration

Edit [`config.sh`](config.sh), or override any value via the environment for a
one-off install (`-E` preserves your env through `sudo`):

```bash
BATTERY=BAT1 NIGHT_DISCHARGE_TARGET=60 MORNING_HOUR=8 sudo -E ./install.sh
```

| Variable                 | Default | Meaning                                                        |
| ------------------------ | ------- | -------------------------------------------------------------- |
| `BATTERY`                | `BAT0`  | Battery under `/sys/class/power_supply/`                       |
| `NIGHT_DISCHARGE_TARGET` | `50`    | Force-discharge down to this % at night                        |
| `NIGHT_START_THRESHOLD`  | `45`    | Overnight: resume charging below this %                        |
| `NIGHT_STOP_THRESHOLD`   | `50`    | Overnight: stop charging at this %                             |
| `DAY_START_THRESHOLD`    | `96`    | Morning: resume charging below this %                          |
| `DAY_STOP_THRESHOLD`     | `100`   | Morning: charge up to this %                                   |
| `NIGHT_HOUR`             | `22`    | Hour (0–23) to run the nightly discharge                       |
| `MORNING_HOUR`           | `7`     | Hour (0–23) to charge back up                                  |
| `WORKDAYS`               | `1-5`   | Cron day-of-week for the morning charge (`1-5`=Mon–Fri, `*`=daily) |
| `INSTALL_BIN_DIR`        | `/usr/local/bin` | Where the discharge helper is installed               |
| `CRON_FILE`              | `/etc/cron.d/battery-care` | Generated cron schedule                      |
| `CRON_USER`              | `root`  | User the cron jobs run as                                      |

## How it works

The generated `/etc/cron.d/battery-care` holds two lines:

```cron
# night: discharge to 50%, then hold 45-50%
0 22 * * *   root  /usr/local/bin/battery-discharge-to.sh 50 BAT0 && /usr/sbin/tlp setcharge 45 50 BAT0

# morning (Mon-Fri): charge to 96-100%
0 7  * * 1-5 root  /usr/sbin/tlp setcharge 96 100 BAT0
```

[`bin/battery-discharge-to.sh`](bin/battery-discharge-to.sh) flips the kernel's
`charge_behaviour` to `force-discharge`, polls until the battery reaches the
target, and **always restores `auto` on exit** — even on Ctrl-C, kill, or
error — so you can never get stuck discharging. `tlp setcharge` then pins the
start/stop thresholds that hold the level in place.

Everything logs to the journal under the `battery-care` tag:

```bash
journalctl -t battery-care --since today
```

## Run the discharge helper by hand

You don't need cron to use it — drain to any level on demand:

```bash
sudo /usr/local/bin/battery-discharge-to.sh 60 BAT0   # discharge to 60%
```

## Optional: email monitoring

If you want email alerts while you build confidence in the schedule, see
[`monitoring/`](monitoring/). It's entirely optional and most people won't need
it (it requires an SMTP relay).

## Troubleshooting

- **Nothing happened overnight.** The machine was probably asleep — cron doesn't
  run while suspended, and force-discharge needs AC. Keep it awake + plugged in,
  or adjust the hours in `config.sh`.
- **`charge_behaviour` missing / discharge is a no-op.** Your hardware/kernel
  doesn't support force-discharge. Threshold pinning still works; the battery
  just won't actively drain — it'll drift down to the night window over time.
- **Thresholds didn't change.** Confirm TLP is enabled (`sudo tlp-stat -s`) and
  that your battery supports thresholds (`sudo tlp-stat -b`).
- **Conflicting schedules.** This cron file is meant to be the single source of
  truth — remove any `tlp setcharge`/discharge lines from your personal crontab.

## License

[MIT](LICENSE) © Rodrigo Rosa.
