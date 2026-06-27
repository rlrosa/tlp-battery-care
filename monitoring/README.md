# Optional: email monitoring

This directory is **completely optional**. The battery schedule in the repo
root works fine on its own — this just lets you get **email alerts** while you
gain confidence that the discharge/charge cycle behaves as expected.

`battery-observer.sh` only *reads* the kernel's `charge_behaviour`, so it
reports what actually happens regardless of what scheduled it. It emails on:

- force-discharge **started**,
- back to **auto** (discharge finished), and
- a one-shot **low-battery** warning below a threshold.

It sends mail with `curl` through an SMTP relay you provide — no auth, so it
assumes an open/internal relay reachable from the machine (common on corporate
networks). If you don't have one, skip all of this.

## Run it ad hoc

```bash
cp battery-observer.env.example battery-observer.env   # then edit it
set -a; source battery-observer.env; set +a
./battery-observer.sh BAT0 30        # battery, poll seconds
```

Stop it with Ctrl-C when you're done watching.

## Run it as a background service (optional)

```bash
cp battery-observer.env.example battery-observer.env   # then edit it
./install-observer.sh                # installs + starts a systemd --user unit
journalctl --user -t battery-observer -f
```

Remove it later:

```bash
systemctl --user disable --now battery-observer.service
```

## Configuration

| Variable                 | Required | Default                      | Meaning                                   |
| ------------------------ | -------- | ---------------------------- | ----------------------------------------- |
| `BATTERY_OBSERVER_TO`    | yes      | —                            | Destination email address                 |
| `BATTERY_OBSERVER_RELAY` | yes      | —                            | SMTP relay URL, e.g. `smtp://host:25`     |
| `BATTERY_OBSERVER_FROM`  | no       | `battery-observer@<host>`    | Sender address                            |
| `BATTERY_OBSERVER_LOW`   | no       | `40`                         | Low-battery warning threshold (%)         |
