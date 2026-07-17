---
name: incident-triage
description: >-
  Unattended root-cause investigation for a ContainerManager-down incident on
  the NAS, triggered headlessly by the incident-triage.timer on the desktop
  after cm-watchdog.sh (on the NAS) detects and auto-restarts a downed
  ContainerManager. Investigates over SSH (nas.example.internal), writes an incident
  report, and opens a PR in this repo. Diagnose-and-propose only — never
  applies changes to live NAS or desktop infra directly. Triggers: run
  non-interactively with an incident id and timestamp as arguments.
---

# Incident triage: ContainerManager down on NAS

You are running unattended (`claude -p`, no human watching in real time).
Preston will only see your output via the final PR and an ntfy notification.
Because of that: **be conservative, be read-only, and if you're not sure
what happened, say so plainly rather than guessing confidently.**

## Hard constraint

You may only run **read-only** commands on `nas.example.internal` and `desktop.example.internal`
(status checks, log reads, `docker ps`/`docker logs`, `cat`, `grep`, etc.).
Do not restart services, edit configs, kill processes, or otherwise change
live state on either machine. `cm-watchdog.sh` already attempted the
recovery restart before you were invoked — your job is explaining what
happened and proposing hardening, not fixing it further. If you believe a
live action is genuinely needed, say so in the report; don't take it.

## Inputs

You'll be given an incident id (a unix timestamp) and should already know
from that timestamp roughly when to look. Confirm the ntfy message for this
incident id (`curl -s http://nas.example.internal:8090/<ntfy-topic>/json?tags=incident-detected`)
to get the exact detection time and current state (restored / still down)
before investigating further.

## Investigation checklist

Work through these in order, on `nas.example.internal`:

1. **Was it OOM?** `sudo dmesg | grep -iE 'oom|killed process'`. If populated
   around the incident time, that's the cause — check `free -h` too.
2. **Was it a watchdog auto-stop?** `/var/log/synopkg.log` is the ground
   truth here, NOT `journalctl` — this NAS's systemd journal buffer resets
   on a timescale of hours, so by the time you're investigating (you're
   running some minutes after detection at minimum) the relevant journal
   entries may already be gone. Look for `grep "begin to stop" /var/log/synopkg.log`
   near the incident timestamp — `"begin to stop due to abnormal status"`
   means Synology's own health-check watchdog fired, not a crash.
3. **Disk space:** `df -h / /var /volume1` — rule out a full filesystem.
4. **Container state:** once ContainerManager is back (check
   `sudo synopkg status ContainerManager`), spot-check that containers
   people actually depend on came back healthy — at minimum `docker ps` and
   `docker logs gluetun --tail 30` (the VPN kill-switch container everything
   download-related depends on) for anything alarming.
5. **Was it reachable after restart?** If the incident report is being
   written well after the restart, you can't observe the transient
   unreachable window that sometimes follows a fresh container restart
   (ARP/conntrack settling — this has been seen once already, see prior
   incident note below) — don't assume every "briefly unreachable" report
   from Preston is a new bug; check if it self-resolved within ~5 minutes
   of the restart completing before treating it as a distinct finding.

Known prior incidents (context, not exhaustive — check
`homelab-ops/incidents/` in this repo for the full history before writing
this one up, and reference cross-cutting patterns if you see a repeat):
- 2026-07-11: OOM crash, root cause was ContainerManager starting all ~35
  containers simultaneously on an 8GB NAS with no per-container memory
  limits.
- 2026-07-17: Watchdog auto-stop after 5 days of healthy uptime, no OOM, no
  disk-full — cause unconfirmed beyond the watchdog's own "abnormal status"
  determination; NAS's journald had already rotated past the event by the
  time it was investigated (~40 min later), which is part of why this
  skill leads with `/var/log/synopkg.log` instead.

## Output

1. Write `incidents/<incident_id>-<short-slug>.md` in this repo: timeline,
   root cause (or best-supported hypothesis if not fully confirmed — say
   which it is), what recovered on its own vs needed intervention, and any
   hardening you'd propose (e.g., RAM upgrade still pending from the
   2026-07-11 incident, per-container memory limits, journald buffer size
   increase so future investigations aren't working blind).
2. If you have a concrete, low-risk hardening change to propose (e.g. a
   tweak to `cm-watchdog.sh`'s debounce timing, a documentation fix), include
   it as a diff in the same PR. Do not propose changes to NAS docker-compose
   files or credentials — those are out of scope for this repo by design.
3. Commit to a new branch (`incident/<incident_id>`), push, and
   `gh pr create` with a title like `Incident <incident_id>: <one-line root
   cause>` and the report as the PR body.
4. Post the final ntfy notification yourself:
   ```
   curl -s -H "Title: Incident report ready" -H "Tags: clipboard" \
     -d "<PR URL> — review when you can" http://nas.example.internal:8090/<ntfy-topic>
   ```

If you get through the checklist and still can't determine a root cause,
that's a valid outcome — write that up honestly (what you checked, what you
ruled out, what's still unknown) rather than forcing a conclusion.
