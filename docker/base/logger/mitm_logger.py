"""
Simple mitmproxy addon that logs outbound requests (host, URL, body) to a file.
"""
import datetime
import json
import os
from pathlib import Path
from typing import Any, Dict

from mitmproxy import http  # type: ignore

LOG_PATH = Path(os.environ.get("MITM_LOG_PATH", "/workspace/output/mitmproxy.log"))
MAX_BODY = int(os.environ.get("MITM_LOG_MAX_BODY", "16000"))


def _serialize_request(flow: http.HTTPFlow) -> Dict[str, Any]:
    req = flow.request

    try:
        body = req.get_text(strict=False)
    except Exception:
        body = "<unavailable>"

    body_truncated = False
    if isinstance(body, str) and len(body) > MAX_BODY:
        body = body[:MAX_BODY] + f"...[truncated {len(body) - MAX_BODY} chars]"
        body_truncated = True

    return {
        "ts": datetime.datetime.utcnow().isoformat() + "Z",
        "scheme": req.scheme,
        "method": req.method,
        "host": req.host,
        "port": req.port,
        "path": req.path,
        "url": req.url,
        "headers": dict(req.headers),
        "content_length": len(req.raw_content or b""),
        "body": body,
        "body_truncated": body_truncated,
    }


def request(flow: http.HTTPFlow) -> None:
    LOG_PATH.parent.mkdir(parents=True, exist_ok=True)
    entry = _serialize_request(flow)
    with LOG_PATH.open("a", encoding="utf-8") as f:
        f.write(json.dumps(entry, ensure_ascii=True) + "\n")
