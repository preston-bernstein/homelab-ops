#!/bin/bash
# Regression test: this repo is public and skills/incident-triage's bot opens
# PRs into it unattended. A literal RFC1918 (private-LAN) IPv4 address
# anywhere in a tracked file -- or one that survives a pass through the
# redaction generator -- means real host/topology detail has leaked into a
# public PR. Two checks:
#
#   A. static scan  -- no tracked file in the repo may contain a literal
#      RFC1918 address (this is what caught the original NTFY_URL leak).
#   B. generator     -- skills/incident-triage/scripts/redact.sh, the choke
#      point every future incident report is meant to pass through before
#      it's written to incidents/*.md or a PR body, must actually strip
#      RFC1918 addresses out of sample "dirty" report text.
#
# Run from anywhere: tests/test_no_host_identifiers.sh
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

RFC1918='(10\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}|172\.(1[6-9]|2[0-9]|3[01])\.[0-9]{1,3}\.[0-9]{1,3}|192\.168\.[0-9]{1,3}\.[0-9]{1,3})'

fail=0

echo "== test A: no RFC1918 literal in any tracked file =="
hits="$(git ls-files -z | xargs -0 grep -InE "$RFC1918" 2>/dev/null | grep -v '^tests/test_no_host_identifiers\.sh:' || true)"
if [ -n "$hits" ]; then
    echo "FAIL: literal RFC1918 address(es) found in tracked files:"
    echo "$hits"
    fail=1
else
    echo "PASS: no RFC1918 literal in tracked files"
fi

echo
echo "== test B: redaction generator strips RFC1918 addresses from report text =="
REDACT="$REPO_ROOT/skills/incident-triage/scripts/redact.sh"
if [ ! -x "$REDACT" ]; then
    echo "FAIL: $REDACT missing or not executable"
    fail=1
else
    sample="Incident detected on host 10.0.0.250, restart posted to 192.168.1.5 and 172.20.0.4. ContainerManager back up."
    out="$(printf '%s\n' "$sample" | "$REDACT")"
    if echo "$out" | grep -qE "$RFC1918"; then
        echo "FAIL: redact.sh left an RFC1918 address in its output:"
        echo "$out"
        fail=1
    else
        echo "PASS: redact.sh output is clean:"
        echo "$out"
    fi
fi

exit "$fail"
