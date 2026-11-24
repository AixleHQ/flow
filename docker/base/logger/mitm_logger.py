"""
Mitmproxy addon that logs outbound requests AND responses to a file.
Binary bodies (e.g. protobuf) are base64-encoded for safe JSON storage.

What is logged is the platform's call, made per agent (Agents::BaseAdapter#mitm_env):
  * MITM_TRACKED_DOMAINS (comma-separated, suffix match): only traffic to these hosts is
    logged. Set but empty logs nothing; unset logs everything, for a container started
    by hand.
  * MITM_LOG_BODIES (comma-separated `request:<host><path prefix>` or
    `response:<host><path prefix>`, or `none`): the entries that keep their bodies.
    Every other entry keeps its method, URL, status, headers and size. Unset keeps
    every body, for a platform that predates the setting. A model call re-sends the
    whole conversation on every turn, so its bodies are most of a log that nobody
    reads, and they are the customer's code.

Credentials are never written. Two rules, both unconditional:
  * credential-bearing headers (Authorization, Cookie, x-api-key, …) are replaced
    with a marker on every entry — API hosts carry the access token on every single
    request, so this is not an auth-endpoint-only concern;
  * an auth endpoint's request and response BODIES are dropped entirely, because
    that is where refresh tokens live, and a refresh token is the whole grant
    rather than eight hours of one.
The endpoint, method, status and timing survive, which is what makes a token
lifecycle observable in the first place.

A third rule covers the session's own secrets — the values an agent reads through
get_config_item and then sends to the model. Those are not protocol credentials and
no header rule catches them, so every entry is passed through aixle_redact, which
reads the list get_config_item registers before it answers. A body is masked before
it is truncated, after its content-encoding is undone, and — for a streamed response —
with the stream's deltas reassembled: a model streams a value back a few characters
per event, and no single event holds enough of it to match.
"""
import base64
import datetime
import json
import os
import sys
from pathlib import Path
from typing import Any, Dict, List, Optional, Set, Tuple

from mitmproxy import http  # type: ignore
from mitmproxy.net import encoding  # type: ignore

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import aixle_redact  # noqa: E402

LOG_PATH = Path(os.environ.get("MITM_LOG_PATH", "/var/log/mitm/http.log"))
MAX_BODY = int(os.environ.get("MITM_LOG_MAX_BODY", "0"))  # 0 = unlimited

_raw_domains = os.environ.get("MITM_TRACKED_DOMAINS")
LOG_ALL_HOSTS = _raw_domains is None
TRACKED_DOMAINS: Set[str] = set(d.strip().lower() for d in (_raw_domains or "").split(",") if d.strip())


def _host_matches(host: str, domain: str) -> bool:
    host = (host or "").lower()
    return host == domain or host.endswith("." + domain)


def _should_log(host: str) -> bool:
    if LOG_ALL_HOSTS:
        return True
    return any(_host_matches(host, d) for d in TRACKED_DOMAINS)


def _parse_body_rules(raw: Optional[str]) -> Optional[List[Tuple[str, str, str]]]:
    if raw is None:
        return None
    rules = []
    for item in raw.split(","):
        direction, sep, target = item.strip().partition(":")
        if not sep or direction not in ("request", "response") or not target:
            continue
        host, slash, path = target.partition("/")
        rules.append((direction, host.lower(), "/" + path if slash else "/"))
    return rules


BODY_RULES = _parse_body_rules(os.environ.get("MITM_LOG_BODIES"))


def _keeps_body(direction: str, host: str, path: str) -> bool:
    if BODY_RULES is None:
        return True
    path = (path or "").split("?", 1)[0]
    return any(
        d == direction and _host_matches(host, h) and path.startswith(p) for d, h, p in BODY_RULES
    )


# Headers whose value IS a credential. Matched case-insensitively, exactly — a prefix
# match would swallow innocuous headers like `x-api-version`.
CREDENTIAL_HEADERS = frozenset(
    {
        "authorization",
        "proxy-authorization",
        "cookie",
        "set-cookie",
        "x-api-key",
        "api-key",
        "x-auth-token",
        "x-amz-security-token",
        "x-goog-api-key",
    }
)
REDACTED = "<redacted>"

# An auth endpoint: where tokens are minted, refreshed or exchanged. Recognised from the
# path rather than a host list, because every vendor names these differently and a list
# would be wrong the first time one of them moves (Cursor already has).
_AUTH_PATH_MARKERS = (
    "/token",
    "/oauth",
    "/auth",
    "/login",
    "/signin",
    "/sso",
    "/refresh",
    "/credential",
    "/device_authorization",
    "/client/register",
)


def _redact_headers(headers: Dict[str, str]) -> Dict[str, str]:
    return {
        k: (REDACTED if k.lower() in CREDENTIAL_HEADERS else v) for k, v in headers.items()
    }


def _is_auth_endpoint(host: str, path: str) -> bool:
    lowered = f"{host}{path}".lower()
    return any(marker in lowered for marker in _AUTH_PATH_MARKERS)


def _blank_body(reason: str) -> Dict[str, Any]:
    return {"body": f"<omitted: {reason}>", "body_encoding": "text", "body_truncated": False}


def _is_text_content(content_type: str) -> bool:
    """Check if content type is text-based (JSON, text, etc.)."""
    text_types = ("json", "text", "xml", "html", "javascript", "yaml", "csv")
    return any(t in content_type.lower() for t in text_types)


def _looks_like_text(raw: bytes) -> bool:
    """Heuristic: treat as text if first 256 bytes are valid UTF-8 without control chars."""
    try:
        sample = raw[:256].decode("utf-8")
        return not any(c < " " and c not in "\r\n\t" for c in sample)
    except (UnicodeDecodeError, ValueError):
        return False


def _decoded(raw: bytes, content_encoding: str) -> bytes:
    if not content_encoding or content_encoding.strip().lower() == "identity":
        return raw
    try:
        return encoding.decode(raw, content_encoding.strip().lower())
    except Exception:
        return raw


def _encode_body(raw: Optional[bytes], content_type: str, content_encoding: str = "") -> Dict[str, Any]:
    """Encode body for JSON storage. Returns dict with body + metadata."""
    if not raw:
        return {"body": "", "body_encoding": "text", "body_truncated": False}

    raw = _decoded(raw, content_encoding)
    if _is_text_content(content_type) or (not content_type and _looks_like_text(raw)):
        try:
            text = raw.decode("utf-8", errors="replace")
        except Exception:
            text = "<decode-error>"
        text = aixle_redact.mask_body(text)
        truncated = False
        if MAX_BODY > 0 and len(text) > MAX_BODY:
            text = text[:MAX_BODY] + f"...[truncated {len(text) - MAX_BODY} chars]"
            truncated = True
        return {"body": text, "body_encoding": "text", "body_truncated": truncated}

    # Binary content — base64 encode
    truncated = False
    data = aixle_redact.mask_binary(raw)
    if MAX_BODY > 0 and len(data) > MAX_BODY:
        data = data[:MAX_BODY]
        truncated = True
    return {
        "body": base64.b64encode(data).decode("ascii"),
        "body_encoding": "base64",
        "body_truncated": truncated,
    }


def _serialize_request(flow: http.HTTPFlow) -> Dict[str, Any]:
    req = flow.request
    ct = req.headers.get("content-type", "")
    if _is_auth_endpoint(req.host, req.path):
        body_info = _blank_body("auth endpoint")
    elif not _keeps_body("request", req.host, req.path):
        body_info = _blank_body("not logged")
    else:
        body_info = _encode_body(req.raw_content, ct, req.headers.get("content-encoding", ""))

    return {
        "ts": datetime.datetime.utcnow().isoformat() + "Z",
        "direction": "request",
        "scheme": req.scheme,
        "method": req.method,
        "host": req.host,
        "port": req.port,
        "path": req.path,
        "url": req.url,
        "headers": _redact_headers(dict(req.headers)),
        "content_length": len(req.raw_content or b""),
        **body_info,
    }


def _serialize_response(flow: http.HTTPFlow) -> Optional[Dict[str, Any]]:
    resp = flow.response
    if resp is None:
        return None

    req = flow.request
    ct = resp.headers.get("content-type", "")
    if _is_auth_endpoint(req.host, req.path):
        body_info = _blank_body("auth endpoint")
    elif not _keeps_body("response", req.host, req.path):
        body_info = _blank_body("not logged")
    else:
        body_info = _encode_body(resp.raw_content, ct, resp.headers.get("content-encoding", ""))

    # A streamed response has no raw_content; #responseheaders counted what went through.
    streamed = flow.metadata.get("_body_size")
    return {
        "ts": datetime.datetime.utcnow().isoformat() + "Z",
        "direction": "response",
        "status_code": resp.status_code,
        "host": req.host,
        "path": req.path,
        "url": req.url,
        "headers": _redact_headers(dict(resp.headers)),
        "content_length": streamed[0] if streamed else len(resp.raw_content or b""),
        **body_info,
    }


def _serialize_response_with_body(
    flow: http.HTTPFlow, body_info: Dict[str, Any]
) -> Optional[Dict[str, Any]]:
    """Like _serialize_response but uses pre-computed body_info (from stream capture)."""
    resp = flow.response
    if resp is None:
        return None

    req = flow.request
    if _is_auth_endpoint(req.host, req.path):
        body_info = {**body_info, **_blank_body("auth endpoint")}

    return {
        "ts": datetime.datetime.utcnow().isoformat() + "Z",
        "direction": "response",
        "status_code": resp.status_code,
        "host": req.host,
        "path": req.path,
        "url": req.url,
        "headers": _redact_headers(dict(resp.headers)),
        "content_length": body_info.get("content_length", 0),
        **body_info,
    }


def _write_entry(entry: Dict[str, Any]) -> None:
    # The third redaction rule, and the only one about the session rather than the
    # protocol: a value the agent read through get_config_item travels to the model in
    # a request body, so it is in this log verbatim unless it is removed here. The
    # entry is cleaned before serialization so a value carrying a quote is matched in
    # its own form rather than in JSON's escaping of it.
    # The body went through mask_body already; scanning it again would double the cost
    # on the request path for nothing.
    entry = {k: v if k == "body" else aixle_redact.redact_obj(v) for k, v in entry.items()}
    LOG_PATH.parent.mkdir(parents=True, exist_ok=True)
    with LOG_PATH.open("a", encoding="utf-8") as f:
        f.write(json.dumps(entry, ensure_ascii=True) + "\n")


def request(flow: http.HTTPFlow) -> None:
    if not _should_log(flow.request.host):
        return
    _write_entry(_serialize_request(flow))


def responseheaders(flow: http.HTTPFlow) -> None:
    """Enable streaming while capturing full body for logging.

    Without streaming, mitmproxy buffers entire response before forwarding,
    which breaks HTTP/2 server-streaming (e.g. AgentService/Run, SSE).
    A callable interceptor lets us stream AND accumulate the body for logging.
    """
    if not _should_log(flow.request.host):
        flow.response.stream = True
        return

    # A body that is dropped anyway is counted, not held: an auth endpoint's would put a
    # token in memory, and an image layer or a model stream would hold its whole size.
    req = flow.request
    if _is_auth_endpoint(req.host, req.path) or not _keeps_body("response", req.host, req.path):
        size = [0]

        def _count(data: bytes) -> bytes:
            size[0] += len(data)
            return data

        flow.response.stream = _count
        flow.metadata["_body_size"] = size
        return

    buf = bytearray()

    def _intercept(data: bytes) -> bytes:
        buf.extend(data)
        return data

    flow.response.stream = _intercept
    flow.metadata["_body_buf"] = buf


def response(flow: http.HTTPFlow) -> None:
    if not _should_log(flow.request.host):
        return

    buf: Optional[bytearray] = flow.metadata.get("_body_buf")
    if buf is not None:
        ct = flow.response.headers.get("content-type", "")
        body_info = _encode_body(bytes(buf), ct, flow.response.headers.get("content-encoding", ""))
        entry = _serialize_response_with_body(flow, {**body_info, "content_length": len(buf)})
    else:
        entry = _serialize_response(flow)

    if entry:
        _write_entry(entry)
