"""
Mitmproxy addon that logs outbound requests AND responses to a file.
Binary bodies (e.g. protobuf) are base64-encoded for safe JSON storage.

Supports domain filtering via MITM_TRACKED_DOMAINS env var (comma-separated).
When set, only requests to listed domains are logged.
When empty, all traffic is logged.
"""
import base64
import datetime
import gzip
import json
import os
import zlib
from pathlib import Path
from typing import Any, Dict, Optional, Set

from mitmproxy import http  # type: ignore

LOG_PATH = Path(os.environ.get("MITM_LOG_PATH", "/var/log/mitm/http.log"))
MAX_BODY = int(os.environ.get("MITM_LOG_MAX_BODY", "0"))  # 0 = unlimited

# Domain filter: only log traffic to these domains (empty = log all)
_raw_domains = os.environ.get("MITM_TRACKED_DOMAINS", "").strip()
TRACKED_DOMAINS: Set[str] = set(d.strip() for d in _raw_domains.split(",") if d.strip())


def _should_log(host: str) -> bool:
    """Check if traffic to this host should be logged (suffix match)."""
    if not TRACKED_DOMAINS:
        return True
    return any(host == d or host.endswith("." + d) for d in TRACKED_DOMAINS)


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


def _decompress(raw: bytes, content_encoding: str) -> Optional[bytes]:
    """Undo Content-Encoding. None means "compressed, and we could not undo it".

    Bodies are captured off the wire (the streaming interceptor in
    responseheaders sees exactly what the server sent), so a gzip'd JSON
    response arrives here still compressed. Decoding those bytes as UTF-8 turns
    the whole body into replacement characters, which is how it used to be
    stored: unparseable, and silently so. Google's code-assist endpoints gzip
    every JSON response, so this is the difference between a usable usage log
    and a log full of U+FFFD.
    """
    enc = (content_encoding or "").lower().strip()
    if not enc or enc == "identity":
        return raw

    try:
        if enc in ("gzip", "x-gzip"):
            return gzip.decompress(raw)
        if enc == "deflate":
            try:
                return zlib.decompress(raw)
            except zlib.error:
                return zlib.decompress(raw, -zlib.MAX_WBITS)
        if enc == "br":
            import brotli  # type: ignore

            return brotli.decompress(raw)
        if enc == "zstd":
            import zstandard  # type: ignore

            return zstandard.ZstdDecompressor().decompress(raw)
    except Exception:
        # Truncated or unsupported — fall through to "keep the bytes as binary"
        # rather than storing a mangled transliteration of them.
        return None
    return None


def _encode_body(
    raw: Optional[bytes], content_type: str, content_encoding: str = ""
) -> Dict[str, Any]:
    """Encode body for JSON storage. Returns dict with body + metadata."""
    if not raw:
        return {"body": "", "body_encoding": "text", "body_truncated": False}

    decoded = _decompress(raw, content_encoding)
    if decoded is None:
        # Still compressed: base64 it, never text.
        truncated = False
        data = raw
        if MAX_BODY > 0 and len(data) > MAX_BODY:
            data = data[:MAX_BODY]
            truncated = True
        return {
            "body": base64.b64encode(data).decode("ascii"),
            "body_encoding": "base64",
            "body_truncated": truncated,
        }
    raw = decoded

    if _is_text_content(content_type) or (not content_type and _looks_like_text(raw)):
        try:
            text = raw.decode("utf-8", errors="replace")
        except Exception:
            text = "<decode-error>"
        truncated = False
        if MAX_BODY > 0 and len(text) > MAX_BODY:
            text = text[:MAX_BODY] + f"...[truncated {len(text) - MAX_BODY} chars]"
            truncated = True
        return {"body": text, "body_encoding": "text", "body_truncated": truncated}

    # Binary content — base64 encode
    truncated = False
    data = raw
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
    body_info = _encode_body(
        req.raw_content, ct, req.headers.get("content-encoding", "")
    )

    return {
        "ts": datetime.datetime.utcnow().isoformat() + "Z",
        "direction": "request",
        "scheme": req.scheme,
        "method": req.method,
        "host": req.host,
        "port": req.port,
        "path": req.path,
        "url": req.url,
        "headers": dict(req.headers),
        "content_length": len(req.raw_content or b""),
        **body_info,
    }


def _serialize_response(flow: http.HTTPFlow) -> Optional[Dict[str, Any]]:
    resp = flow.response
    if resp is None:
        return None

    req = flow.request
    ct = resp.headers.get("content-type", "")
    body_info = _encode_body(
        resp.raw_content, ct, resp.headers.get("content-encoding", "")
    )

    return {
        "ts": datetime.datetime.utcnow().isoformat() + "Z",
        "direction": "response",
        "status_code": resp.status_code,
        "host": req.host,
        "path": req.path,
        "url": req.url,
        "headers": dict(resp.headers),
        "content_length": len(resp.raw_content or b""),
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
    return {
        "ts": datetime.datetime.utcnow().isoformat() + "Z",
        "direction": "response",
        "status_code": resp.status_code,
        "host": req.host,
        "path": req.path,
        "url": req.url,
        "headers": dict(resp.headers),
        "content_length": body_info.get("content_length", 0),
        **body_info,
    }


def _write_entry(entry: Dict[str, Any]) -> None:
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
        body_info = _encode_body(
            bytes(buf), ct, flow.response.headers.get("content-encoding", "")
        )
        entry = _serialize_response_with_body(flow, body_info)
    else:
        entry = _serialize_response(flow)

    if entry:
        _write_entry(entry)
