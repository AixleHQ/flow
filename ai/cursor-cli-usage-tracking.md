# Cursor CLI Usage Tracking — Final Solution

## Problem

Cursor CLI does not support OpenTelemetry or any native usage reporting API.
We need to track token usage and costs per agent session for billing and analytics.

## Architecture

```
┌──────────────────────────────────────────────────────┐
│  Docker Container                                     │
│                                                       │
│  ┌─────────────┐     ┌──────────────────────────────┐│
│  │ Cursor CLI  │────▶│ agent.*.api5.cursor.sh       ││
│  │ (Node.js)   │     │ AgentService/Run (HTTP/2)    ││
│  └──────┬──────┘     └──────────────────────────────┘│
│         │                                             │
│  NODE_OPTIONS="--require /opt/mitm/http2-logger.js"   │
│         │                                             │
│         ▼                                             │
│  ┌──────────────┐                                     │
│  │ http.log     │ ← request + response timestamps     │
│  └──────┬───────┘                                     │
│         │                                             │
└─────────┼─────────────────────────────────────────────┘
          │ (collected as artifact on session stop)
          ▼
┌─────────────────────────────────────────────────────┐
│  CursorCliAdapter#collect_usage                      │
│                                                      │
│  1. Parse http.log → RPC windows (request_ts,        │
│     response_ts, x-request-id)                       │
│  2. Single API call to Dashboard API:                │
│     [earliest_request, latest_response + 500ms]      │
│  3. Match each API event to its RPC window           │
│     using [response_ts, response_ts + 500ms]         │
│  4. Persist matched events as UsageStatistic         │
└─────────────────────────────────────────────────────┘
```

## Key Components

### 1. http2-logger.js (injected via NODE_OPTIONS)

Patches `http2.connect()` to intercept `AgentService/Run` calls.
Logs two events per RPC:
- `request` — client sends HEADERS (timestamp = request start)
- `response` — server sends back response HEADERS (timestamp ≈ billing - 270ms)

**Why not mitmproxy?** Cursor CLI uses `http2.connect()` directly for
AgentService/Run, bypassing HTTP_PROXY/HTTPS_PROXY env vars. Standard
proxy can't intercept this traffic.

### 2. mitm_logger.py (mitmproxy addon)

Standard HTTP/HTTPS traffic logger. Used by all agents.
Supports domain filtering via `MITM_TRACKED_DOMAINS` env var.
Cursor CLI adapter sets this to track `cursor.sh` traffic.

### 3. CursorCliAdapter (Ruby)

- `collect_usage` — orchestrates the flow
- `build_rpc_windows` — pairs request/response entries by x-request-id
- `match_windows_to_api` — correlates Dashboard API events to windows
- `fetch_filtered_events` — single API call to Cursor Dashboard

### 4. Dashboard API

`POST https://api2.cursor.sh/aiserver.v1.DashboardService/GetFilteredUsageEvents`

Returns billing events with: timestamp, model, tokenUsage (input, output,
cacheRead, cacheWrite), costs. No session/request IDs — correlation is
time-based only.

## Correlation Algorithm

```
Billing timestamp ≈ response_headers_timestamp + 270ms (±100ms)

For each RPC call:
  Window = [response_ts, response_ts + 500ms]

API event matches if: event.timestamp ∈ Window
```

### Empirical Data (4 measurements)

| Session | billing - response_ts |
|---------|----------------------|
| 228     | +290ms               |
| 229 #1  | +309ms               |
| 229 #2  | +193ms               |
| 231     | +271ms               |

### Parallel Session Safety

Window width of 500ms is narrow enough to prevent overlap.
A single user cannot physically start two agent sessions within 500ms.

## Environment Variables

| Variable | Used by | Description |
|----------|---------|-------------|
| `MITM_LOG_PATH` | http2-logger.js, mitm_logger.py | Shared log file path |
| `MITM_TRACKED_DOMAINS` | mitm_logger.py | Comma-separated domain filter (empty = all) |
| `MITM_LOG_MAX_BODY` | mitm_logger.py | Max body size to log |

## What We Investigated and Ruled Out

1. **cursor-otel-hook (Python)** — no token/cost data in hooks
2. **Native OTEL interception** — complex, fragile, token_counts_visible != billing
3. **iptables transparent proxy** — TLS/HTTP2 issues, root user conflicts
4. **Protobuf stream decoding** — no server-side timestamps or billing IDs in data
5. **HTTP `date` header** — only second-level precision
6. **Trailing headers** — none sent by Cursor server
7. **request_body matching** — Dashboard API doesn't return correlation IDs
