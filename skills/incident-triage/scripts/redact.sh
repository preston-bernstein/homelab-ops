#!/bin/bash
# Redacts host-identifying detail from incident-report text before it is
# written to incidents/*.md, a PR body, or an ntfy notification.
#
# This repo is public and skills/incident-triage opens PRs into it
# unattended (claude -p, no human review before the write happens). That
# means the SKILL.md instructions are the only thing standing between a
# real NAS incident and a public PR full of live infra detail -- and prose
# instructions get silently dropped by fresh unattended runs. This script
# is the deterministic choke point instead: SKILL.md's Output section pipes
# every report draft through it, so redaction happens by construction, not
# by an agent remembering to do it.
#
# Implemented in Python (via -c, not a heredoc -- a heredoc would consume
# the same stdin stream this needs for piped input) rather than sed: BSD
# sed (macOS, used for local dev/testing) does not support \b word
# boundaries the way GNU sed does, and silently no-ops the substitution
# instead of erroring -- exactly the kind of failure that must not happen
# here. Python's `re` module behaves identically on every platform this
# runs on (dev Mac, CI, the desktop box that actually executes this skill).
#
# Extend the pattern in redact.py (not just SKILL.md's prose) when a new
# class of host-identifying detail turns up in a report.
#
# Usage:
#   redact.sh < draft-report.md > clean-report.md
#   redact.sh draft-report.md > clean-report.md
set -euo pipefail

exec python3 "$(dirname "${BASH_SOURCE[0]}")/redact.py" "$@"
