/**
 * HTTP/2 request logger for AgentService/Run.
 *
 * Cursor CLI uses http2.connect() directly for AgentService/Run calls,
 * bypassing HTTP_PROXY/HTTPS_PROXY. This module patches http2.connect()
 * to capture request and response timestamps for billing correlation.
 *
 * Logs two events per RPC:
 *   1. "request"  — client sends HEADERS (request start)
 *   2. "response" — server sends response HEADERS (≈ billing_ts - 270ms)
 *
 * Does NOT modify data flow — just observes.
 * Inject via: NODE_OPTIONS="--require /opt/mitm/http2-logger.js"
 */
'use strict';

const fs = require('fs');
const http2 = require('http2');
const path = require('path');

const LOG_PATH = process.env.MITM_LOG_PATH || '/var/log/mitm/http.log';
const TRACKED_PATH = '/agent.v1.AgentService/Run';

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

const originalConnect = http2.connect;

http2.connect = function patchedConnect(authority, options) {
  const session = originalConnect.apply(this, arguments);
  const authorityStr = typeof authority === 'string' ? authority : authority.toString();

  let host;
  try {
    host = new URL(authorityStr).hostname;
  } catch {
    host = authorityStr;
  }

  const originalRequest = session.request.bind(session);

  session.request = function patchedRequest(headers, options) {
    const stream = originalRequest(headers, options);
    const reqPath = headers[':path'] || '';

    if (reqPath !== TRACKED_PATH) return stream;

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
