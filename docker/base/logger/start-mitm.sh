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
#   MITM_LOG_PATH     - log file path (default: /var/log/mitm/http.log)
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
MITM_LOG_PATH="${MITM_LOG_PATH:-/var/log/mitm/http.log}"
MITM_LOG_MAX_BODY="${MITM_LOG_MAX_BODY:-0}"

# Export for mitm_logger.py and http2-logger.js
export MITM_LOG_PATH MITM_LOG_MAX_BODY MITM_TRACKED_DOMAINS

# Ensure log directory exists
mkdir -p "$(dirname "${MITM_LOG_PATH}")" 2>/dev/null || true

echo -e "${CYAN:-}🛡️  Starting MITM proxy on port ${MITM_PROXY_PORT}...${NC:-}"

# Seed $HOME/.mitmproxy with the pre-generated CA from the Docker image.
# This avoids the race between mitmdump generating a CA on first start and
# child processes making HTTPS requests before the cert exists.
MITMPROXY_DIR="${HOME:-/root}/.mitmproxy"
mkdir -p "$MITMPROXY_DIR" 2>/dev/null || true
cp /opt/mitm/ca/* "$MITMPROXY_DIR/" 2>/dev/null || true

# TLS trust (MITM TLS to the proxy uses a cert signed by mitm CA):
# - Node: use built-in Mozilla roots for real sites + NODE_EXTRA_CA_CERTS for mitm only.
#   Do NOT use --use-system-ca here: it makes Node rely mostly on SSL_CERT_FILE; a bad/missing
#   bundle then breaks all HTTPS (e.g. "unable to get local issuer certificate", upstream 502).
# - OpenSSL/curl/git/Python: single bundle = Debian CA store + mitm CA (rebuilt every start).
SYSTEM_CA_BUNDLE="/etc/ssl/certs/ca-certificates.crt"
MITM_CA_PEM="$MITMPROXY_DIR/mitmproxy-ca-cert.pem"
COMBINED_CA_PEM="$MITMPROXY_DIR/combined-ca-bundle.pem"
if [ -r "$MITM_CA_PEM" ] && [ -r "$SYSTEM_CA_BUNDLE" ]; then
  cat "$SYSTEM_CA_BUNDLE" "$MITM_CA_PEM" >"$COMBINED_CA_PEM"
  chmod 644 "$COMBINED_CA_PEM" 2>/dev/null || true
fi

export NODE_EXTRA_CA_CERTS="$MITM_CA_PEM"
if [ -r "$COMBINED_CA_PEM" ]; then
  export SSL_CERT_FILE="$COMBINED_CA_PEM"
  export CURL_CA_BUNDLE="$COMBINED_CA_PEM"
  export REQUESTS_CA_BUNDLE="$COMBINED_CA_PEM"
  export GIT_SSL_CAINFO="$COMBINED_CA_PEM"
else
  export SSL_CERT_FILE="$SYSTEM_CA_BUNDLE"
fi

# Set proxy environment variables for all child processes
HTTP_PROXY="http://localhost:${MITM_PROXY_PORT}"
HTTPS_PROXY="$HTTP_PROXY"
NO_PROXY="localhost,127.0.0.1,::1"
export HTTP_PROXY HTTPS_PROXY NO_PROXY

# Chromium/Playwright: trust MITM CA via NSS (~/.pki/nssdb), not only NODE_EXTRA_CA_CERTS.
if command -v certutil >/dev/null 2>&1 && [ -r /opt/mitm/nss-trust-mitm-ca.sh ]; then
  bash /opt/mitm/nss-trust-mitm-ca.sh || echo -e "${YELLOW:-}⚠️  NSS mitm CA import failed (HTTPS via proxy may fail)${NC:-}"
fi

# Start mitmdump in background with logging addon
mitmdump --listen-host 0.0.0.0 --listen-port "${MITM_PROXY_PORT}" \
    --set block_global=false \
    -q -s /opt/mitm/mitm_logger.py &
MITM_PID=$!

# Wait until mitmdump is accepting connections (up to 5 s)
for _ in {1..50}; do
    if bash -c "echo >/dev/tcp/127.0.0.1/${MITM_PROXY_PORT}" 2>/dev/null; then
        break
    fi
    sleep 0.1
done

# HTTP/2 logger: patches http2.connect() to log request headers (trust via NODE_EXTRA_CA_CERTS + built-in roots)
export NODE_OPTIONS="${NODE_OPTIONS:+$NODE_OPTIONS }--require /opt/mitm/http2-logger.js"

# Verify startup
if kill -0 $MITM_PID 2>/dev/null; then
    echo -e "${GREEN:-}✅ MITM proxy started (PID: $MITM_PID) - logging to ${MITM_LOG_PATH}${NC:-}"
    echo -e "${GREEN:-}✅ HTTP/2 logger enabled via NODE_OPTIONS${NC:-}"
else
    echo -e "${YELLOW:-}⚠️  MITM proxy failed to start${NC:-}"
fi
