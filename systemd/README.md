# systemd installation

This is the supported installation method. It installs root-owned services,
timers, a system sleep hook, and a clean-shutdown guard.

```bash
sudo -E systemd/install.sh
```

The installer creates:

- `battery-care-{night,morning}.timer` — interval-boundary triggers;
- `battery-care-reconcile.service` — decides low versus normal policy now;
- `battery-care-low.service` — the bounded active-discharge worker;
- `battery-care-departure.service` — changes to normal thresholds on clean
  shutdown; and
- `/usr/lib/systemd/system-sleep/battery-care` — applies normal policy before
  sleep and triggers reconciliation after resume.

The low worker is stopped before departure/normal policy, preventing an old
force-discharge process from surviving a lifecycle transition.

```bash
systemctl list-timers 'battery-care-*'
systemctl status battery-care-reconcile.service battery-care-low.service
journalctl -t battery-care --since today
```

Expected steady-state status:

- `battery-care-reconcile.service` is `inactive (dead)` after a successful
  one-shot run;
- `battery-care-low.service` is active only while force-discharge is running;
- `battery-care-departure.service` is enabled and `active (exited)`.

The two timers are persistent, so a missed boundary causes a reconciliation on
the next start. The post-wake hook also starts reconciliation, which is what
enforces the current interval after suspend or hibernate.

To uninstall, run `sudo -E systemd/uninstall.sh`.
