# tlp-battery-care

`tlp-battery-care` keeps a plugged-in laptop at a low charge overnight, then
restores normal charging for the workday. It is a root-managed, event-driven
layer on top of [TLP](https://linrunner.de/tlp/).

- **Low interval:** from `NIGHT_HOUR` every day until `MORNING_HOUR` on a
  configured workday. With the defaults, this includes the entire weekend.
- **Normal interval:** 96–100% on workdays from 07:00 to 22:00.
- **Departure:** suspend, hibernate, hybrid sleep, suspend-then-hibernate,
  reboot, halt, and clean poweroff immediately restore normal thresholds.
- **Wake:** the current interval is recalculated. If it is low time and AC is
  connected, the low thresholds and bounded discharge are started again.

This is designed for a laptop that normally stays plugged in. When AC is not
online, the policy keeps normal thresholds and never force-discharges.

## Requirements

- Linux with systemd and TLP.
- A battery exposed under `/sys/class/power_supply/` (usually `BAT0`).
- For active draining, `charge_behaviour` must support `force-discharge`.
  Threshold-only low charging still works without it.
- Root installation: TLP thresholds, battery sysfs, and system sleep/shutdown
  lifecycle hooks are privileged interfaces.

## Install

```bash
git clone https://github.com/rlrosa/tlp-battery-care
cd tlp-battery-care
# optional: edit config.sh
sudo -E systemd/install.sh
```

Or without cloning:

```bash
curl -fsSL https://raw.githubusercontent.com/rlrosa/tlp-battery-care/main/get.sh | sudo bash
```

Use environment overrides for a one-off install:

```bash
NIGHT_HOUR=23 NIGHT_DISCHARGE_TARGET=60 sudo -E systemd/install.sh
```

Re-run the installer after changing `config.sh`. It regenerates root-owned
runtime configuration and systemd units, then immediately reconciles policy.
If migrating from the retired cron variant, run `sudo -E cron/uninstall.sh`
first, then install the systemd policy.

## Configuration

| Variable | Default | Meaning |
| --- | --- | --- |
| `BATTERY` | `BAT0` | Battery under `/sys/class/power_supply` |
| `NIGHT_DISCHARGE_TARGET` | `50` | Active-discharge target during low time |
| `NIGHT_START_THRESHOLD` / `NIGHT_STOP_THRESHOLD` | `45` / `50` | Low charge window |
| `DAY_START_THRESHOLD` / `DAY_STOP_THRESHOLD` | `96` / `100` | Normal charge window |
| `NIGHT_DISCHARGE_MAX_RUNTIME_MINUTES` | `720` | Per-attempt discharge limit |
| `NIGHT_HOUR` / `MORNING_HOUR` | `22` / `7` | Low begins / normal begins |
| `WORKDAYS` | `1-5` | Cron-style normal days; `*` means daily |
| `UNIT_DIR` | `/etc/systemd/system` | Generated systemd unit directory |
| `RUNTIME_DIR` | `/etc/tlp-battery-care` | Root-only generated runtime configuration |
| `SYSTEM_SLEEP_DIR` | `/usr/lib/systemd/system-sleep` | Generated system-sleep hook directory |

`MORNING_HOUR` must be earlier than `NIGHT_HOUR`. `WORKDAYS` accepts `*` or
comma-separated day numbers/ranges (`0` or `7` is Sunday), such as `1-5`.

## Operation

```bash
# Inspect the state and active discharge worker.
systemctl status battery-care-reconcile.service battery-care-low.service

# See scheduled boundaries.
systemctl list-timers 'battery-care-*'

# Re-evaluate policy now.
sudo systemctl start battery-care-reconcile.service

# Review decisions and discharge progress.
journalctl -t battery-care --since today
```

`battery-care-reconcile.service` is a one-shot service, so `inactive (dead)`
with a successful last exit is the expected status after it applies policy.
`battery-care-low.service` is active only while a low-interval discharge is in
progress. `battery-care-departure.service` should remain `active (exited)` and
enabled while the policy is installed.

The installed system-sleep hook changes to normal thresholds before suspend,
hibernate, hybrid sleep, and suspend-then-hibernate; it starts a non-blocking
reconcile after wake. A shutdown guard runs the same departure policy on clean
reboot/halt/poweroff. Sudden power loss cannot run a hook.

To pause policy persistently, disable the two timers and the departure guard;
re-enable them and start a reconcile to resume:

```bash
sudo systemctl disable --now battery-care-night.timer battery-care-morning.timer battery-care-departure.service
sudo systemctl enable --now battery-care-night.timer battery-care-morning.timer battery-care-departure.service
sudo systemctl start battery-care-reconcile.service
```

## Uninstall

```bash
sudo -E systemd/uninstall.sh
# or:
curl -fsSL https://raw.githubusercontent.com/rlrosa/tlp-battery-care/main/get.sh | sudo bash -s -- uninstall
```

Uninstall restores `charge_behaviour=auto` but intentionally leaves your TLP
thresholds unchanged. To reset them fully: `sudo tlp setcharge 0 100 BAT0`.

## License

[MIT](LICENSE) © Rodrigo Rosa.
