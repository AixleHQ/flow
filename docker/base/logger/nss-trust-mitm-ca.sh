#!/bin/bash
# Import mitmproxy CA into the NSS database at sql:$HOME/.pki/nssdb.
# Chromium / Playwright on Linux consult this store for user-added trust anchors
# (NODE_EXTRA_CA_CERTS alone is not enough for the browser).
#
# Idempotent. Expects PEM at /opt/mitm/ca/mitmproxy-ca-cert.pem (image build).
# Run as the same user/uid that launches Playwright (container entrypoint user).

set -u

MITM_PEM="${1:-/opt/mitm/ca/mitmproxy-ca-cert.pem}"
if [ ! -r "$MITM_PEM" ]; then
  echo "nss-trust-mitm-ca: CA file not readable: $MITM_PEM" >&2
  exit 1
fi

if ! command -v certutil >/dev/null 2>&1; then
  echo "nss-trust-mitm-ca: certutil not found (install libnss3-tools)" >&2
  exit 1
fi

NSS_DIR="${HOME}/.pki/nssdb"
mkdir -p "$NSS_DIR"
NSS_DB="sql:${NSS_DIR}"

if [ ! -f "${NSS_DIR}/cert9.db" ]; then
  certutil -d "$NSS_DB" -N --empty-password
fi

if certutil -d "$NSS_DB" -L -n "mitmproxy-ca" >/dev/null 2>&1; then
  exit 0
fi

certutil -d "$NSS_DB" -A -t "C,," -n "mitmproxy-ca" -i "$MITM_PEM"
echo "nss-trust-mitm-ca: imported mitmproxy CA into ${NSS_DB}"
