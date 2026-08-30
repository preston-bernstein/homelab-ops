---
name: incident-triage
description: >-
  Unattended root-cause investigation for a ContainerManager-down incident on
  the NAS, triggered headlessly by the incident-triage.timer on the desktop
  after cm-watchdog.sh (on the NAS) detects and auto-restarts a downed
  ContainerManager. Investigates over SSH (nas-agent), writes an incident
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

You may only run **read-only** commands on `nas-agent` and `desktop-agent`
(status checks, log reads, `docker ps`/`docker logs`, `cat`, `grep`, etc.).
Do not restart services, edit configs, kill processes, or otherwise change
live state on either machine. `cm-watchdog.sh` already attempted the
recovery restart before you were invoked — your job is explaining what
happened and proposing hardening, not fixing it further. If you believe a
live action is genuinely needed, say so in the report; don't take it.

## Inputs

You'll be given an incident id (a unix timestamp) and should already know
from that timestamp roughly when to look. `NTFY_URL` must be set in your
environment (see `.env.example` at the repo root -- this is provisioned on
the desktop where this skill runs, not something you configure). Confirm
the ntfy message for this incident id
(`curl -s "${NTFY_URL}/json?tags=incident-detected"`) to get the exact
detection time and current state (restored / still down) before
investigating further.

## Investigation checklist

Work through these in order, on `nas-agent`:

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
this one up, and reference cross-cutting patterns if you see a repeat).
These are deliberately written at the same generic level you must write
your own report at — see Redaction below before you add to this list or
write incidents/*.md:
- 2026-07-11: OOM crash, root cause was ContainerManager starting most of
  the NAS's containers simultaneously with no per-container memory limits
  on a capacity-constrained NAS.
- 2026-07-17: Watchdog auto-stop after several days of healthy uptime, no
  OOM, no disk-full — cause unconfirmed beyond the watchdog's own "abnormal
  status" determination; the NAS's journald had already rotated past the
  event by the time it was investigated (tens of minutes later), which is
  part of why this skill leads with `/var/log/synopkg.log` instead.

## Redaction (required, before anything below is written or posted)

This repo is public and you are opening a PR into it unattended — nobody
reviews your draft before it becomes a public commit. Before writing
`incidents/*.md`, the PR body, or the ntfy notification in step 4:

- Draft the report normally, using whatever you learned from SSH (real
  hostnames/IPs are fine to *reason about* while investigating — the
  constraint is on what gets written down).
- Pipe the finished draft through the redaction generator:
  `skills/incident-triage/scripts/redact.sh < draft.md > clean.md`. This
  strips literal RFC1918 addresses (`10.x`, `172.16-31.x`, `192.168.x`)
  automatically — treat it as the floor, not the whole job.
- On top of what the script catches, write the report itself at the same
  generic level as the "Known prior incidents" entries above: say "the NAS"
  / "the desktop", not a hostname-as-IP; describe capacity qualitatively
  ("a capacity-constrained NAS", "most of the NAS's containers") rather than
  exact RAM/disk/container-count figures; container names are fine (they're
  software, not infra topology) but don't combine them with exact resource
  numbers in a way that reconstructs the real deployment.
- If you are unsure whether a detail is safe to publish, leave it out and
  say in the report that you omitted it for that reason — an incomplete
  report is fine; a public infra leak is not.

## Output

1. Write the redacted report to `incidents/<incident_id>-<short-slug>.md` in
   this repo: timeline, root cause (or best-supported hypothesis if not
   fully confirmed — say which it is), what recovered on its own vs needed
   intervention, and any hardening you'd propose (e.g., a still-pending
   capacity upgrade, per-container memory limits, journald buffer size
   increase so future investigations aren't working blind).
2. If you have a concrete, low-risk hardening change to propose (e.g. a
   tweak to `cm-watchdog.sh`'s debounce timing, a documentation fix), include
   it as a diff in the same PR. Do not propose changes to NAS docker-compose
   files or credentials — those are out of scope for this repo by design.
3. Commit to a new branch (`incident/<incident_id>`), push, and
   `gh pr create` with a title like `Incident <incident_id>: <one-line root
   cause>` and the *redacted* report as the PR body.
4. Post the final ntfy notification yourself (this text is short and
   PR-URL-only, but redact it too — never paste raw investigation output
   into a notification):
   ```
   curl -s -H "Title: Incident report ready" -H "Tags: clipboard" \
     -d "<PR URL> — review when you can" "${NTFY_URL}"
   ```

If you get through the checklist and still can't determine a root cause,
that's a valid outcome — write that up honestly (what you checked, what you
ruled out, what's still unknown) rather than forcing a conclusion.
