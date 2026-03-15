/**
 * Node.js HTTP request logger.
 *
 * Patches http2.connect(), https.request(), and http.request() to log
 * all outbound traffic to tracked domains. Works for agents that bypass
 * HTTP_PROXY (e.g. Claude Code, Cursor CLI).
 *
 * http2:  Captures AgentService/Run gRPC calls (Cursor CLI).
 * https:  Captures REST API calls (Claude Code → api.anthropic.com).
 *
 * Inject via: NODE_OPTIONS="--require /opt/mitm/http2-logger.js"
 */
'use strict';

const fs = require('fs');
const http = require('http');
const https = require('https');
const http2 = require('http2');
const path = require('path');

const LOG_PATH = process.env.MITM_LOG_PATH || '/var/log/mitm/http.log';

const _rawDomains = (process.env.MITM_TRACKED_DOMAINS || '').trim();
const TRACKED_DOMAINS = new Set(_rawDomains ? _rawDomains.split(',').map(d => d.trim()).filter(Boolean) : []);

let dirReady = false;

function appendLog(entry) {
  try {
    if (!dirReady) {
      const dir = path.dirname(LOG_PATH);
      if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
      dirReady = true;
    }
    fs.appendFileSync(LOG_PATH, JSON.stringify(entry) + '\n');
  } catch (_) {}
}

function shouldLog(host) {
  if (!host || TRACKED_DOMAINS.size === 0) return TRACKED_DOMAINS.size === 0;
  for (const d of TRACKED_DOMAINS) {
    if (host === d || host.endsWith('.' + d)) return true;
  }
  return false;
}

// ---------------------------------------------------------------------------
// HTTP/2 patch (Cursor CLI gRPC)
// ---------------------------------------------------------------------------
const originalConnect = http2.connect;

http2.connect = function patchedConnect(authority, options) {
  const session = originalConnect.apply(this, arguments);
  const authorityStr = typeof authority === 'string' ? authority : authority.toString();

  let host;
  try { host = new URL(authorityStr).hostname; } catch { host = authorityStr; }
  if (!shouldLog(host)) return session;

  const originalRequest = session.request.bind(session);

  session.request = function patchedRequest(headers, options) {
    const stream = originalRequest(headers, options);
    const reqPath = headers[':path'] || '';
    const requestId = headers['x-request-id'] || '';

    appendLog({
      ts: new Date().toISOString(),
      direction: 'request',
      host,
      path: reqPath,
      headers: { 'x-request-id': requestId },
      _source: 'http2-logger',
    });

    stream.on('response', () => {
      appendLog({
        ts: new Date().toISOString(),
        direction: 'response',
        host,
        path: reqPath,
        headers: { 'x-request-id': requestId },
        _source: 'http2-logger',
      });
    });

    return stream;
  };

  return session;
};

// ---------------------------------------------------------------------------
// HTTP/HTTPS patch (Claude Code, Codex, Gemini, etc.)
// ---------------------------------------------------------------------------
function patchHttpModule(mod, protocol) {
  const originalRequest = mod.request;

  mod.request = function patchedRequest(urlOrOpts, optsOrCb, cb) {
    let host, reqPath;
    try {
      if (typeof urlOrOpts === 'string' || urlOrOpts instanceof URL) {
        const parsed = typeof urlOrOpts === 'string' ? new URL(urlOrOpts) : urlOrOpts;
        host = parsed.hostname;
        reqPath = parsed.pathname;
      } else if (urlOrOpts && typeof urlOrOpts === 'object') {
        host = urlOrOpts.hostname || urlOrOpts.host || '';
        reqPath = urlOrOpts.path || '/';
        if (host.includes(':')) host = host.split(':')[0];
      }
    } catch (_) {
      return originalRequest.apply(this, arguments);
    }

    const req = originalRequest.apply(this, arguments);

    if (!shouldLog(host)) return req;

    appendLog({
      ts: new Date().toISOString(),
      direction: 'request',
      scheme: protocol,
      method: (typeof urlOrOpts === 'object' ? urlOrOpts.method : 'GET') || 'GET',
      host,
      path: reqPath,
      _source: 'node-http-logger',
    });

    req.on('response', (res) => {
      appendLog({
        ts: new Date().toISOString(),
        direction: 'response',
        status_code: res.statusCode,
        host,
        path: reqPath,
        _source: 'node-http-logger',
      });
    });

    return req;
  };
  // http.get() calls http.request() internally, so it's covered by the patch above.
}

patchHttpModule(https, 'https');
patchHttpModule(http, 'http');
