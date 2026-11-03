#!/usr/bin/env python3
"""
Streaming secret redaction for the agent pane.

`tmux pipe-pane` sends the raw PTY stream to two sinks at once: the file the session
collector uploads as terminal_output.log, and /proc/1/fd/1, which is the container's
stdout and therefore the cluster's log stack. Filtering here cleans both.

aixle_redact.TerminalStream does the matching — on the stream's significant
characters, so a value the TUI draws between colour codes or wraps onto the next row
is still found — and holds back only the few characters a secret could still continue
from. The live terminal does not read this pipe (ttyd attaches to tmux directly), so
holding them costs nothing anyone watches; after IDLE_FLUSH seconds without output
they are written anyway, which can leave fewer than aixle_redact.FRAGMENT characters
of a secret that resumes after the pause. The collector masks the whole file again.
"""
import os
import select
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import aixle_redact  # noqa: E402

BUFSIZE = 65536
IDLE_FLUSH = 1.0


def main():
    out = sys.stdout.buffer
    stream = aixle_redact.TerminalStream()
    pending = False

    while True:
        if pending:
            ready, _, _ = select.select([0], [], [], IDLE_FLUSH)
            if not ready:
                out.write(stream.flush())
                out.flush()
                pending = False
                continue
        try:
            chunk = os.read(0, BUFSIZE)
        except OSError:
            break
        if not chunk:
            break

        data = stream.feed(chunk)
        if data:
            out.write(data)
            out.flush()
        pending = True

    out.write(stream.flush())
    out.flush()


if __name__ == "__main__":
    main()
