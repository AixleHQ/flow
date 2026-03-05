/**
 * Standalone Auth Check Service
 *
 * Minimal HTTP server for auth_setup sessions only.
 * Checks if agent authentication is complete by reading a config file
 * and looking for required keys.
 *
 * Endpoints:
 *   GET /auth   — { "authenticated": true/false }
 *   GET /health — { "status": "ok" }
 *
 * Environment:
 *   SESSION_TYPE       — must be "auth_setup"
 *   AUTH_WATCH_PATH    — path to agent config file
 *   AUTH_REQUIRED_KEYS — comma-separated keys to check
 *   WATCHER_PORT       — listen port (default 4040)
 */

const fs = require('fs');
const http = require('http');

const PORT = parseInt(process.env.WATCHER_PORT || '4040', 10);
const SESSION_TYPE = process.env.SESSION_TYPE || null;
const AUTH_WATCH_PATH = process.env.AUTH_WATCH_PATH || null;
const AUTH_REQUIRED_KEYS = (process.env.AUTH_REQUIRED_KEYS || '')
  .split(',')
  .map((k) => k.trim())
  .filter(Boolean);

function checkAuthComplete(configContent) {
  if (AUTH_REQUIRED_KEYS.length === 0) return false;
  try {
    const config = JSON.parse(configContent);
    return AUTH_REQUIRED_KEYS.some((key) => {
      const value = key.split('.').reduce((obj, k) => obj?.[k], config);
      return value !== undefined && value !== null && value !== '';
    });
  } catch {
    return false;
  }
}

const server = http.createServer((req, res) => {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');
  res.setHeader('Content-Type', 'application/json');

  if (req.method === 'OPTIONS') {
    res.writeHead(204);
    res.end();
    return;
  }

  const url = new URL(req.url, `http://${req.headers.host}`);

  if (url.pathname === '/auth') {
    let authenticated = false;
    if (SESSION_TYPE === 'auth_setup' && AUTH_WATCH_PATH) {
      try {
        if (fs.existsSync(AUTH_WATCH_PATH)) {
          authenticated = checkAuthComplete(fs.readFileSync(AUTH_WATCH_PATH, 'utf-8'));
        }
      } catch {
        /* ignore */
      }
    }
    res.writeHead(200);
    res.end(JSON.stringify({ authenticated }));
    return;
  }

  if (url.pathname === '/health') {
    res.writeHead(200);
    res.end(JSON.stringify({ status: 'ok' }));
    return;
  }

  res.writeHead(404);
  res.end(JSON.stringify({ error: 'Not Found' }));
});

server.listen(PORT, '0.0.0.0', () => {
  console.log(`[auth-check] listening on port ${PORT}`);
});

process.on('SIGTERM', () => {
  server.close();
  process.exit(0);
});
process.on('SIGINT', () => {
  server.close();
  process.exit(0);
});
