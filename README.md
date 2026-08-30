# homelab-ops

[![CI](https://github.com/preston-bernstein/homelab-ops/actions/workflows/ci.yml/badge.svg)](https://github.com/preston-bernstein/homelab-ops/actions/workflows/ci.yml)  [![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

Watchdog + auto-triage pipeline for the household infra (NAS + desktop). Scoped
deliberately narrow: **scripts, runbooks, and incident reports only** — never
NAS docker-compose files or credentials. That keeps this repo safe to have a
bot open PRs against unattended.

## What's here

- `watchdog/cm-watchdog.sh` — runs on the NAS via cron every 5 minutes.
  Detects Synology ContainerManager (the Docker daemon package) going down,
  attempts an auto-restart, and posts status to ntfy at every state
  transition (down → restarting → restored, or → still-down if the restart
  itself fails).
- `skills/incident-triage/` — a Claude Code skill that runs on the desktop.
  A systemd timer polls the ntfy topic for `incident-detected` events; when
  one appears, it invokes this skill headlessly (`claude -p`) to investigate
  root cause over SSH and open a PR here with an incident report and
  hardening proposal. **It never touches live infra — diagnose and propose
  only.** Preston reviews and merges (or doesn't) by hand.
- `incidents/` — where triage PRs land their write-ups (created on first PR).

## Deploying a watchdog script change

The NAS has no git. After merging a change to `watchdog/cm-watchdog.sh`,
redeploy by hand:

```
scp watchdog/cm-watchdog.sh nas.example.internal:/var/services/homes/agent/homelab-ops/watchdog/cm-watchdog.sh
```

The desktop side (`skills/incident-triage/`, the systemd unit) lives in a
real clone (`~agent/homelab-ops` on desktop) — `git pull` there picks up
skill changes; the systemd unit itself isn't repo-managed, edit it directly
on the box if it needs to change.

## Notification channel

Both halves read a single `NTFY_URL` (a push URL for your own ntfy topic)
from the environment, with a safe loopback default
(`http://127.0.0.1:8080/homelab-ops`) so cloning this repo never silently
points anything at Preston's real infra. Copy `.env.example` to `.env`
(gitignored) and set the real value before deploying:

- `watchdog/cm-watchdog.sh` sources an optional `.env` next to itself on the
  NAS, or picks up `NTFY_URL` from cron's environment directly.
- `skills/incident-triage/` expects `NTFY_URL` set in the desktop
  environment the skill runs in.

ntfy has no built-in auth — anyone who knows a topic's URL can read and
publish to it — so treat the topic name as a shared secret and don't reuse
one that has ever appeared in a public repo or PR. Subscribe the ntfy app
to your topic to get pushes.

## License

MIT — see [LICENSE](LICENSE).
