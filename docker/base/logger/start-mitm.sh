#!/bin/bash
# =============================================================================
# MITM Proxy + HTTP/2 Logger Startup Script
#
# Two complementary logging mechanisms:
#   1. mitmproxy (regular proxy mode) — captures http/https via HTTPS_PROXY
#      Works for api2.cursor.sh calls that use Node http/https modules
#   2. http2-logger.js (NODE_OPTIONS --require) — patches http2.connect()
#      Captures AgentService/Run calls that use HTTP/2 directly
#
# Both write to the same MITM_LOG_PATH file.
#
# Usage:
#   source /opt/mitm/start-mitm.sh
#
# Environment variables (optional):
#   MITM_PROXY_PORT   - proxy port (default: 8888)
#   MITM_LOG_PATH     - log file path (default: $WORKSPACE/output/mitmproxy.log)
#   MITM_LOG_MAX_BODY - max body size to log (default: 16000)
#   MITM_DISABLED     - set to "true" to skip starting mitm proxy
# =============================================================================

# Skip if disabled
if [ "$MITM_DISABLED" = "true" ]; then
    echo -e "${YELLOW:-}⏭️  MITM proxy disabled${NC:-}"
    return 0 2>/dev/null || exit 0
fi

# Configuration with defaults
MITM_PROXY_PORT="${MITM_PROXY_PORT:-8888}"
MITM_LOG_PATH="${MITM_LOG_PATH:-${WORKSPACE:-/workspace}/output/mitmproxy.log}"
MITM_LOG_MAX_BODY="${MITM_LOG_MAX_BODY:-0}"
MITM_CA_CERT="${HOME:-/root}/.mitmproxy/mitmproxy-ca-cert.pem"

# Export for mitm_logger.py and http2-logger.js
export MITM_LOG_PATH MITM_LOG_MAX_BODY MITM_TRACKED_DOMAINS

# Ensure log directory exists
mkdir -p "$(dirname "${MITM_LOG_PATH}")" 2>/dev/null || true

echo -e "${CYAN:-}🛡️  Starting MITM proxy on port ${MITM_PROXY_PORT}...${NC:-}"

# Ensure mitmproxy config directory exists (may be on tmpfs)
mkdir -p "${HOME:-/root}/.mitmproxy" 2>/dev/null || true

# Set proxy environment variables for all child processes
HTTP_PROXY="http://localhost:${MITM_PROXY_PORT}"
HTTPS_PROXY="$HTTP_PROXY"
NO_PROXY="localhost,127.0.0.1,::1"
export HTTP_PROXY HTTPS_PROXY NO_PROXY

# Start mitmdump in background with logging addon
mitmdump --listen-host 0.0.0.0 --listen-port "${MITM_PROXY_PORT}" \
    --set block_global=false \
    -q -s /opt/mitm/mitm_logger.py &
MITM_PID=$!

# Wait for CA certificate to be generated (needed for HTTPS interception)
for _ in {1..20}; do
    if [ -f "$MITM_CA_CERT" ]; then
        # Node.js uses NODE_EXTRA_CA_CERTS
        export NODE_EXTRA_CA_CERTS="$MITM_CA_CERT"
        # Create combined cert bundle with system certs + mitmproxy CA
        COMBINED_CERTS="${HOME:-/root}/.mitmproxy/combined-ca-bundle.pem"
        cat /etc/ssl/certs/ca-certificates.crt "$MITM_CA_CERT" > "$COMBINED_CERTS" 2>/dev/null || \
        cat "$MITM_CA_CERT" > "$COMBINED_CERTS"
        export SSL_CERT_FILE="$COMBINED_CERTS"
        break
    fi
    sleep 0.1
done

# HTTP/2 logger: patches http2.connect() to log request headers
# This captures traffic that bypasses HTTPS_PROXY (e.g. AgentService/Run)
export NODE_OPTIONS="${NODE_OPTIONS:+$NODE_OPTIONS }--require /opt/mitm/http2-logger.js"

# Verify startup
if kill -0 $MITM_PID 2>/dev/null; then
    echo -e "${GREEN:-}✅ MITM proxy started (PID: $MITM_PID) - logging to ${MITM_LOG_PATH}${NC:-}"
    echo -e "${GREEN:-}✅ HTTP/2 logger enabled via NODE_OPTIONS${NC:-}"
else
    echo -e "${YELLOW:-}⚠️  MITM proxy failed to start${NC:-}"
fi
