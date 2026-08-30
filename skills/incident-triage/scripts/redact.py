#!/usr/bin/env python3
"""RFC1918 (private-LAN) address redaction for incident-triage report text.

Invoked by redact.sh -- see that file's header for why this is Python and
not sed, and why it is a separate file rather than a heredoc.
"""
from __future__ import annotations

import re
import sys

RFC1918 = re.compile(
    r"\b(?:"
    r"10(?:\.\d{1,3}){3}"
    r"|172\.(?:1[6-9]|2\d|3[01])(?:\.\d{1,3}){2}"
    r"|192\.168(?:\.\d{1,3}){2}"
    r")\b"
)


def redact(text: str) -> str:
    return RFC1918.sub("<lan-host>", text)


def main() -> None:
    if len(sys.argv) > 1:
        with open(sys.argv[1], "r", encoding="utf-8") as fh:
            data = fh.read()
    else:
        data = sys.stdin.read()
    sys.stdout.write(redact(data))


if __name__ == "__main__":
    main()
