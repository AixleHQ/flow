"""Forward one CLI hook event to the session's OTLP collector as a log record.

    python3 -I /opt/mitm/otlp_hook.py <service.name> <event> [reply]

Installed as the command of every lifecycle hook of the runtimes that export no
OpenTelemetry of their own (docs/design/agent-telemetry.md §3). The event JSON the CLI
writes on stdin becomes the body of one record, unchanged, posted to the collector in
AIXLE_OTLP_ENDPOINT. The session comes from AIXLE_OTLP_RESOURCE_ATTRIBUTES
(OTEL_RESOURCE_ATTRIBUTES' format). The platform gives the CLI both and the hook inherits
them. Not OTEL_RESOURCE_ATTRIBUTES itself: a CLI whose own telemetry goes to its vendor
would attach the session key to it.

A hook runs inside the agent's turn and some CLIs act on its result: a non-zero exit
blocks the tool (Kiro), stdout is added to the model's context (Kiro, Antigravity). So
this prints only the optional `reply` the CLI expects, always exits 0, and posts from a
detached child so the agent never waits on the collector.
"""

import json
import os
import select
import sys
import time
import urllib.parse
import urllib.request

# otlp-ingest reads at most 10 MiB of a request; a larger body would be cut mid-JSON.
MAX_BODY_BYTES = 8 << 20
TIMEOUT_SECONDS = 10
# A CLI that leaves stdin open (or hands over its terminal) must not hold the hook up.
STDIN_SECONDS = 2
SESSION_ATTRIBUTES = ("terminal_session_token", "terminal_session_key")


def resource_attributes(environ):
    pairs = {}
    for item in environ.get("AIXLE_OTLP_RESOURCE_ATTRIBUTES", "").split(","):
        key, sep, value = item.partition("=")
        if sep:
            pairs[urllib.parse.unquote(key.strip())] = urllib.parse.unquote(value.strip())
    return pairs


def string_value(key, value):
    return {"key": key, "value": {"stringValue": value}}


def export_request(service, event, raw, environ, now_ns):
    resource = resource_attributes(environ)
    if not all(resource.get(key) for key in SESSION_ATTRIBUTES):
        return None

    body = raw.decode("utf-8", errors="replace")
    attributes = [string_value("event.name", event)]
    if len(raw) > MAX_BODY_BYTES:
        body = raw[:MAX_BODY_BYTES].decode("utf-8", errors="ignore")
        attributes.append({"key": "aixle_flow.hook.truncated_from_bytes", "value": {"intValue": str(len(raw))}})

    resource_attrs = [string_value("service.name", service)]
    resource_attrs += [string_value(key, value) for key, value in resource.items() if key != "service.name"]
    record = {
        "timeUnixNano": str(now_ns),
        "observedTimeUnixNano": str(now_ns),
        "body": {"stringValue": body},
        "attributes": attributes,
    }
    return {
        "resourceLogs": [{
            "resource": {"attributes": resource_attrs},
            "scopeLogs": [{"scope": {"name": "aixle_flow.hooks"}, "logRecords": [record]}],
        }]
    }


def post(url, request):
    data = json.dumps(request, separators=(",", ":")).encode("utf-8")
    http = urllib.request.Request(url, data=data, headers={"Content-Type": "application/json"}, method="POST")
    with urllib.request.urlopen(http, timeout=TIMEOUT_SECONDS) as response:
        response.read()


def read_event(stdin):
    if stdin is None or stdin.isatty():
        return b""
    fd = stdin.fileno()
    deadline = time.monotonic() + STDIN_SECONDS
    chunks = []
    while True:
        remaining = deadline - time.monotonic()
        if remaining <= 0 or not select.select([fd], [], [], remaining)[0]:
            break
        chunk = os.read(fd, 1 << 16)
        if not chunk:
            break
        chunks.append(chunk)
    return b"".join(chunks)


def detach():
    """Return True in the child that should do the posting, after the parent exits."""
    if os.fork():
        return False
    os.setsid()
    devnull = os.open(os.devnull, os.O_RDWR)
    for fd in (0, 1, 2):
        os.dup2(devnull, fd)
    return True


def main(argv):
    if len(argv) < 3:
        return
    service, event = argv[1], argv[2]
    reply = argv[3] if len(argv) > 3 else ""
    endpoint = os.environ.get("AIXLE_OTLP_ENDPOINT", "")
    raw = read_event(sys.stdin)
    if reply:
        sys.stdout.write(reply)
    sys.stdout.flush()

    request = export_request(service, event, raw, os.environ, time.time_ns())
    if request is None or not endpoint:
        return
    if not detach():
        return
    try:
        post(endpoint.rstrip("/") + "/v1/logs", request)
    except Exception:
        pass


if __name__ == "__main__":
    try:
        main(sys.argv)
    except BaseException:
        pass
    os._exit(0)
