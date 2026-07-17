# homelab-ops

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

ntfy topic `<ntfy-topic>` on the existing `internal-finance-service-ntfy-1` container,
`http://nas.example.internal:8090/<ntfy-topic>`. Subscribe the ntfy app to that topic to
get pushes.
