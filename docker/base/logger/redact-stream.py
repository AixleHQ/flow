#!/usr/bin/env python3
"""
Streaming secret redaction for the agent pane.

`tmux pipe-pane` sends the raw PTY stream to two sinks at once: the file the session
collector uploads as terminal_output.log, and /proc/1/fd/1, which is the container's
stdout and therefore the cluster's log stack. The second one has never been redacted
at all — get_config_item's own warning to the agent ("visible to the cluster's log
stack if it is printed") describes exactly this gap. Filtering here closes both.

Two properties the terminal needs that a whole-file pass does not have to think about:

  * nothing may be withheld for long, or the live terminal visibly lags. So the
    filter flushes everything except the smallest tail that could still be the start
    of a secret, which is almost always nothing at all;
  * a secret may be split across two writes. The tail is held exactly when it
    contains the first byte of some secret, which is the only way a split can begin.

What it cannot promise: a value the TUI redraws in pieces, with escape sequences
interleaved, is not contiguous in this stream and so is not matched. That is equally
true of the collector-side pass this supplements, and neither is the place to fix it
— an agent that prints a secret has already lost it to anyone watching the session.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import aixle_redact  # noqa: E402

BUFSIZE = 65536


def splittable_tail(buf, secrets):
    """How many trailing bytes must be held back because a secret may start in them."""
    if not secrets:
        return 0

    longest = max(len(secret) for secret in secrets)
    window = min(len(buf), longest - 1)
    if window <= 0:
        return 0

    earliest = None
    tail = buf[-window:]
    for secret in secrets:
        found = tail.find(secret[:1])
        if found != -1 and (earliest is None or found < earliest):
            earliest = found

    return 0 if earliest is None else window - earliest


def main():
    out = sys.stdout.buffer
    carry = b""

    while True:
        try:
            chunk = os.read(0, BUFSIZE)
        except OSError:
            break
        if not chunk:
            break

        secrets = aixle_redact.values()
        buf = aixle_redact.redact_bytes(carry + chunk, secrets)

        hold = splittable_tail(buf, secrets)
        if hold:
            carry, buf = buf[-hold:], buf[:-hold]
        else:
            carry = b""

        if buf:
            out.write(buf)
            out.flush()

    if carry:
        out.write(aixle_redact.redact_bytes(carry))
        out.flush()


if __name__ == "__main__":
    main()
