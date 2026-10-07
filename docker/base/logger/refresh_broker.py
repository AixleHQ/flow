"""
Mitmproxy addon that hands an agent CLI's OAuth refresh to the platform.

Every container of a user holds a copy of the same single-use refresh token. On a
laptop the CLI's processes share one credentials file and refresh under one lockfile,
so the token is spent once; containers share neither, so two busy ones spend it twice
and the second is logged out. The platform's broker (Agents::RefreshBroker) is the
shared lock: it refreshes a token it still holds and answers a token it already
replaced with the tokens that replaced it.

Only requests to the endpoints in CREDENTIAL_REFRESH_TARGETS ("host/path") are
touched. Whenever the broker is unset, unreachable or declines, the request goes on
to the vendor exactly as before.
"""
import asyncio
import json
import os
import urllib.request
from typing import Any, Dict, Optional

from mitmproxy import http  # type: ignore

BROKER_URL = os.environ.get("CREDENTIAL_REFRESH_URL", "").strip()
SESSION_ID = os.environ.get("SESSION_ID", "").strip()
SESSION_KEY = os.environ.get("CREDENTIAL_SYNC_KEY", "").strip()
TARGETS = {
    t.strip().lower()
    for t in os.environ.get("CREDENTIAL_REFRESH_TARGETS", "").split(",")
    if t.strip()
}
# The broker may itself call the vendor; the CLI waits 30 s for its refresh.
TIMEOUT_SECONDS = 25

# mitmdump is started after HTTPS_PROXY is exported, so urllib would otherwise send the
# broker call through this very proxy.
_OPENER = urllib.request.build_opener(urllib.request.ProxyHandler({}))


def _is_target(flow: http.HTTPFlow) -> bool:
    req = flow.request
    if req.method != "POST":
        return False
    return f"{req.pretty_host.lower()}{req.path.split('?', 1)[0]}" in TARGETS


def _ask_broker(payload: bytes) -> Optional[Dict[str, Any]]:
    request = urllib.request.Request(
        BROKER_URL,
        data=payload,
        method="POST",
        headers={
            "Content-Type": "application/json",
            "X-Session-Id": SESSION_ID,
            "X-Agent-Key": SESSION_KEY,
        },
    )
    with _OPENER.open(request, timeout=TIMEOUT_SECONDS) as response:
        if response.status != 200:
            return None
        answer = json.loads(response.read().decode("utf-8"))
    return answer if isinstance(answer, dict) and "status" in answer else None


async def request(flow: http.HTTPFlow) -> None:
    if not (BROKER_URL and SESSION_ID and SESSION_KEY and TARGETS) or not _is_target(flow):
        return

    payload = json.dumps(
        {
            "url": flow.request.pretty_url,
            "content_type": flow.request.headers.get("content-type", ""),
            # Named so Rails' parameter filter (`:token`) keeps it out of the request log.
            "token_request": flow.request.get_text(strict=False) or "",
        }
    ).encode("utf-8")
    try:
        answer = await asyncio.to_thread(_ask_broker, payload)
    except Exception:  # noqa: BLE001 — any failure means "let the vendor answer"
        return
    if answer is None:
        return

    flow.response = http.Response.make(
        int(answer["status"]),
        str(answer.get("body", "")).encode("utf-8"),
        {"Content-Type": str(answer.get("content_type") or "application/json")},
    )
